#include <gio/gio.h>

#include <memory>
#include <string>

#include "tray_activation_token.h"

namespace {
constexpr char kItemPath[] = "/org/ayatana/NotificationItem/test_indicator";
constexpr char kInterface[] = "org.kde.StatusNotifierItem";

struct CallResult {
  GMainLoop* loop;
  GVariant* reply = nullptr;
  GError* error = nullptr;
};

void OnReply(GObject* source, GAsyncResult* result, gpointer user_data) {
  auto* call = static_cast<CallResult*>(user_data);
  call->reply = g_dbus_connection_call_finish(G_DBUS_CONNECTION(source), result, &call->error);
  g_main_loop_quit(call->loop);
}

struct Fixture {
  GDBusConnection* service;
  GDBusConnection* host;
  TrayActivationToken* receiver = nullptr;
};

void SetUp(Fixture* fixture, gconstpointer user_data) {
  g_autoptr(GError) error = nullptr;
  fixture->service = g_bus_get_sync(G_BUS_TYPE_SESSION, nullptr, &error);
  g_assert_no_error(error);
  fixture->host = g_dbus_connection_new_for_address_sync(
      g_getenv("DBUS_SESSION_BUS_ADDRESS"),
      static_cast<GDBusConnectionFlags>(G_DBUS_CONNECTION_FLAGS_AUTHENTICATION_CLIENT |
                                       G_DBUS_CONNECTION_FLAGS_MESSAGE_BUS_CONNECTION),
      nullptr, nullptr, &error);
  g_assert_no_error(error);
  fixture->receiver = new TrayActivationToken();
  fixture->receiver->Attach(fixture->service);
}

void TearDown(Fixture* fixture, gconstpointer user_data) {
  delete fixture->receiver;
  fixture->receiver = nullptr;
  g_dbus_connection_close_sync(fixture->host, nullptr, nullptr);
  g_object_unref(fixture->host);
  g_object_unref(fixture->service);
}

void Call(Fixture* fixture, const gchar* path, const gchar* interface,
          const gchar* member, GVariant* arguments, const gchar* expected_error = nullptr) {
  g_autoptr(GMainLoop) loop = g_main_loop_new(nullptr, FALSE);
  CallResult result{loop};
  g_dbus_connection_call(fixture->host, g_dbus_connection_get_unique_name(fixture->service),
                         path, interface, member, arguments, nullptr,
                         G_DBUS_CALL_FLAGS_NONE, 1000, nullptr, OnReply, &result);
  g_main_loop_run(loop);
  if (expected_error != nullptr) {
    g_assert_nonnull(result.error);
    g_autofree gchar* name = g_dbus_error_get_remote_error(result.error);
    g_assert_cmpstr(name, ==, expected_error);
  } else {
    g_assert_no_error(result.error);
    g_assert_nonnull(result.reply);
  }
  g_clear_error(&result.error);
  g_clear_pointer(&result.reply, g_variant_unref);
}

void Provide(Fixture* fixture, const char* token) {
  Call(fixture, kItemPath, kInterface, "ProvideXdgActivationToken", g_variant_new("(s)", token));
}

void OneUse(Fixture* fixture, gconstpointer user_data) {
  // The library exports no such method. The receiver must answer it itself.
  Provide(fixture, "fresh");
  const std::string token = fixture->receiver->Take();
  g_assert_cmpstr(token.c_str(), ==, "fresh");
  g_assert_true(fixture->receiver->Take().empty());
}

void LatestToken(Fixture* fixture, gconstpointer user_data) {
  Provide(fixture, "old");
  Provide(fixture, "new");
  const std::string token = fixture->receiver->Take();
  g_assert_cmpstr(token.c_str(), ==, "new");
  Provide(fixture, "old");
  Provide(fixture, "");
  g_assert_true(fixture->receiver->Take().empty());
}

void Malformed(Fixture* fixture, gconstpointer user_data) {
  Call(fixture, kItemPath, kInterface, "ProvideXdgActivationToken", g_variant_new("(u)", 1),
       "org.freedesktop.DBus.Error.InvalidArgs");
  g_assert_true(fixture->receiver->Take().empty());
}

void OtherMessages(Fixture* fixture, gconstpointer user_data) {
  Call(fixture, "/unrelated/item", kInterface, "ProvideXdgActivationToken", g_variant_new("(s)", "foreign"),
       "org.freedesktop.DBus.Error.UnknownMethod");
  Call(fixture, kItemPath, "another.Interface", "ProvideXdgActivationToken", g_variant_new("(s)", "foreign"),
       "org.freedesktop.DBus.Error.UnknownMethod");
  Call(fixture, kItemPath, kInterface, "AnotherMethod", g_variant_new("(s)", "foreign"),
       "org.freedesktop.DBus.Error.UnknownMethod");
  g_assert_true(fixture->receiver->Take().empty());
}

void Detached(Fixture* fixture, gconstpointer user_data) {
  delete fixture->receiver;
  fixture->receiver = nullptr;
  Call(fixture, kItemPath, kInterface, "ProvideXdgActivationToken", g_variant_new("(s)", "late"),
       "org.freedesktop.DBus.Error.UnknownMethod");
}

void OnMenuEvent(GDBusConnection* connection, const gchar* sender, const gchar* path,
                 const gchar* interface, const gchar* method, GVariant* arguments,
                 GDBusMethodInvocation* invocation, gpointer user_data) {
  auto* fixture = static_cast<Fixture*>(user_data);
  const std::string token = fixture->receiver->Take();
  g_assert_cmpstr(token.c_str(), ==, "menu");
  g_dbus_method_invocation_return_value(invocation, g_variant_new("()"));
}

void MenuOrdering(Fixture* fixture, gconstpointer user_data) {
  const char* xml = "<node><interface name='com.canonical.dbusmenu'><method name='Event'/></interface></node>";
  g_autoptr(GDBusNodeInfo) node = g_dbus_node_info_new_for_xml(xml, nullptr);
  const GDBusInterfaceVTable vtable{OnMenuEvent, nullptr, nullptr, {nullptr}};
  guint registration = g_dbus_connection_register_object(
      fixture->service, "/Menu", node->interfaces[0], &vtable, fixture, nullptr, nullptr);
  g_assert_cmpuint(registration, !=, 0);

  // Match Plasma's same-connection ordering without waiting for the token reply.
  g_dbus_connection_call(fixture->host, g_dbus_connection_get_unique_name(fixture->service),
                         kItemPath, kInterface, "ProvideXdgActivationToken", g_variant_new("(s)", "menu"),
                         nullptr, G_DBUS_CALL_FLAGS_NONE, 1000, nullptr, nullptr, nullptr);
  Call(fixture, "/Menu", "com.canonical.dbusmenu", "Event", g_variant_new("()"));
  g_assert_true(fixture->receiver->Take().empty());
  g_dbus_connection_unregister_object(fixture->service, registration);
}
}  // namespace

int main(int argc, char** argv) {
  g_test_init(&argc, &argv, nullptr);
  g_test_add("/CAP-1/tray-token-once", Fixture, nullptr, SetUp, OneUse, TearDown);
  g_test_add("/CAP-1/latest-tray-token", Fixture, nullptr, SetUp, LatestToken, TearDown);
  g_test_add("/CAP-1/malformed-token", Fixture, nullptr, SetUp, Malformed, TearDown);
  g_test_add("/CAP-1/unrelated-messages", Fixture, nullptr, SetUp, OtherMessages, TearDown);
  g_test_add("/CAP-1/detached-receiver", Fixture, nullptr, SetUp, Detached, TearDown);
  g_test_add("/CAP-1/token-before-menu-event", Fixture, nullptr, SetUp, MenuOrdering, TearDown);
  return g_test_run();
}
