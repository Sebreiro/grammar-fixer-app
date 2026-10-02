#include <gio/gio.h>
#include <glib/gstdio.h>

#include <memory>
#include <string>
#include <vector>

#include "kwin_panel_stacking.h"
#include "kwin_panel_stacking_script.h"

namespace {
constexpr char kPlugin[] = "com.divertedriver.HotkeyGrammarCorrector.panel-stacking";
constexpr char kScriptingXml[] =
    "<node><interface name='org.kde.kwin.Scripting'>"
    "<method name='loadScript'><arg type='s' direction='in'/>"
    "<arg type='s' direction='in'/><arg type='i' direction='out'/></method>"
    "<method name='unloadScript'><arg type='s' direction='in'/>"
    "<arg type='b' direction='out'/></method></interface></node>";
constexpr char kScriptXml[] =
    "<node><interface name='org.kde.kwin.Script'><method name='run'/>"
    "</interface></node>";

struct Fixture {
  GDBusConnection* service = nullptr;
  GDBusConnection* client = nullptr;
  std::shared_ptr<KWinPanelStacking> stacking;
  std::vector<std::string> calls;
  std::string script_path;
  bool refuse_load = false;
  bool fail_run = false;
  bool stall_run = false;
  GDBusMethodInvocation* pending_run = nullptr;
  guint scripting_registration = 0;
  guint script_registration = 0;
};

GDBusConnection* Connect() {
  g_autoptr(GError) error = nullptr;
  auto* connection = g_dbus_connection_new_for_address_sync(
      g_getenv("DBUS_SESSION_BUS_ADDRESS"),
      static_cast<GDBusConnectionFlags>(G_DBUS_CONNECTION_FLAGS_AUTHENTICATION_CLIENT |
                                       G_DBUS_CONNECTION_FLAGS_MESSAGE_BUS_CONNECTION),
      nullptr, nullptr, &error);
  g_assert_no_error(error);
  return connection;
}

void OnMethod(GDBusConnection* connection, const gchar* sender,
              const gchar* path, const gchar* interface, const gchar* method,
              GVariant* arguments, GDBusMethodInvocation* invocation,
              gpointer user_data) {
  auto* fixture = static_cast<Fixture*>(user_data);
  fixture->calls.emplace_back(method);
  if (g_strcmp0(method, "loadScript") == 0) {
    const gchar* filename = nullptr;
    const gchar* plugin = nullptr;
    g_variant_get(arguments, "(&s&s)", &filename, &plugin);
    g_assert_cmpstr(plugin, ==, kPlugin);
    fixture->script_path = filename;
    g_dbus_method_invocation_return_value(
        invocation, g_variant_new("(i)", fixture->refuse_load ? -1 : 17));
    return;
  }
  if (g_strcmp0(method, "unloadScript") == 0) {
    const gchar* plugin = nullptr;
    g_variant_get(arguments, "(&s)", &plugin);
    g_assert_cmpstr(plugin, ==, kPlugin);
    g_dbus_method_invocation_return_value(invocation, g_variant_new("(b)", TRUE));
    return;
  }
  g_assert_cmpstr(method, ==, "run");
  g_assert_true(g_file_test(fixture->script_path.c_str(), G_FILE_TEST_IS_REGULAR));
  g_autofree gchar* directory = g_path_get_dirname(fixture->script_path.c_str());
  GStatBuf permissions;
  g_assert_cmpint(g_stat(directory, &permissions), ==, 0);
  g_assert_cmpint(permissions.st_mode & 0777, ==, 0700);
  g_autofree gchar* script = nullptr;
  g_assert_true(g_file_get_contents(fixture->script_path.c_str(), &script, nullptr, nullptr));
  g_assert_cmpstr(script, ==, kKWinPanelStackingScript);
  if (fixture->stall_run) {
    fixture->pending_run = G_DBUS_METHOD_INVOCATION(g_object_ref(invocation));
    return;
  }
  if (fixture->fail_run) {
    g_dbus_method_invocation_return_dbus_error(
        invocation, "org.kde.kwin.Scripting.Error", "Script failed");
    return;
  }
  g_dbus_method_invocation_return_value(invocation, g_variant_new("()"));
}

void SetUp(Fixture* fixture, gconstpointer user_data) {
  new (fixture) Fixture();
  fixture->client = Connect();
  fixture->service = Connect();
  fixture->stacking = std::make_shared<KWinPanelStacking>();
  if (g_strcmp0(static_cast<const char*>(user_data), "absent") == 0) return;
  g_autoptr(GError) error = nullptr;
  g_autoptr(GVariant) name = g_dbus_connection_call_sync(
      fixture->service, "org.freedesktop.DBus", "/org/freedesktop/DBus",
      "org.freedesktop.DBus", "RequestName", g_variant_new("(su)", "org.kde.KWin", 0),
      G_VARIANT_TYPE("(u)"), G_DBUS_CALL_FLAGS_NONE, 1000, nullptr, &error);
  g_assert_no_error(error);
  guint32 ownership = 0;
  g_variant_get(name, "(u)", &ownership);
  g_assert_cmpuint(ownership, ==, 1);
  const GDBusInterfaceVTable vtable{OnMethod, nullptr, nullptr, {nullptr}};
  g_autoptr(GDBusNodeInfo) scripting = g_dbus_node_info_new_for_xml(kScriptingXml, nullptr);
  fixture->scripting_registration = g_dbus_connection_register_object(
      fixture->service, "/Scripting", scripting->interfaces[0], &vtable, fixture, nullptr, &error);
  g_assert_no_error(error);
  g_autoptr(GDBusNodeInfo) script = g_dbus_node_info_new_for_xml(kScriptXml, nullptr);
  const char* path = g_strcmp0(static_cast<const char*>(user_data), "legacy") == 0
                         ? "/17" : "/Scripting/Script17";
  fixture->script_registration = g_dbus_connection_register_object(
      fixture->service, path, script->interfaces[0], &vtable, fixture, nullptr, &error);
  g_assert_no_error(error);
}

void TearDown(Fixture* fixture, gconstpointer user_data) {
  fixture->stacking.reset();
  if (fixture->pending_run != nullptr) {
    g_dbus_method_invocation_return_value(fixture->pending_run, g_variant_new("()"));
    g_clear_object(&fixture->pending_run);
  }
  if (fixture->scripting_registration != 0) {
    g_dbus_connection_unregister_object(fixture->service, fixture->scripting_registration);
    g_dbus_connection_unregister_object(fixture->service, fixture->script_registration);
  }
  g_dbus_connection_close_sync(fixture->client, nullptr, nullptr);
  g_dbus_connection_close_sync(fixture->service, nullptr, nullptr);
  g_object_unref(fixture->client);
  g_object_unref(fixture->service);
  fixture->~Fixture();
}

struct Completion {
  GMainLoop* loop;
  GError* error = nullptr;
};

void OnComplete(GObject* source, GAsyncResult* result, gpointer user_data) {
  auto* completion = static_cast<Completion*>(user_data);
  g_task_propagate_boolean(G_TASK(result), &completion->error);
  g_main_loop_quit(completion->loop);
}

GError* Configure(Fixture* fixture) {
  g_autoptr(GMainLoop) loop = g_main_loop_new(nullptr, FALSE);
  Completion completion{loop};
  fixture->stacking->Configure(fixture->client, OnComplete, &completion);
  g_main_loop_run(loop);
  return completion.error;
}

void Dispose(Fixture* fixture) {
  g_autoptr(GMainLoop) loop = g_main_loop_new(nullptr, FALSE);
  Completion completion{loop};
  fixture->stacking->Dispose(OnComplete, &completion);
  g_main_loop_run(loop);
  g_assert_no_error(completion.error);
}

void Lifecycle(Fixture* fixture, gconstpointer user_data) {
  g_autoptr(GError) error = Configure(fixture);
  g_assert_no_error(error);
  g_assert_true((fixture->calls == std::vector<std::string>{"unloadScript", "loadScript", "run"}));
  g_assert_false(g_file_test(fixture->script_path.c_str(), G_FILE_TEST_EXISTS));
  g_autoptr(GError) repeated = Configure(fixture);
  g_assert_no_error(repeated);
  g_assert_cmpuint(fixture->calls.size(), ==, 3);
  Dispose(fixture);
  g_assert_cmpstr(fixture->calls.back().c_str(), ==, "unloadScript");
  g_assert_cmpuint(fixture->calls.size(), ==, 4);
  Dispose(fixture);
  g_assert_cmpuint(fixture->calls.size(), ==, 4);
  g_autoptr(GError) disposed = Configure(fixture);
  g_assert_error(disposed, G_IO_ERROR, G_IO_ERROR_CLOSED);
}

void Absent(Fixture* fixture, gconstpointer user_data) {
  g_autoptr(GError) error = Configure(fixture);
  g_assert_no_error(error);
  g_assert_true(fixture->calls.empty());
  Dispose(fixture);
}

void Rejected(Fixture* fixture, gconstpointer user_data) {
  fixture->refuse_load = true;
  g_autoptr(GError) error = Configure(fixture);
  g_assert_error(error, G_IO_ERROR, G_IO_ERROR_FAILED);
  g_assert_false(g_file_test(fixture->script_path.c_str(), G_FILE_TEST_EXISTS));
  g_assert_cmpuint(fixture->calls.size(), ==, 2);
  Dispose(fixture);
}

void FailedRun(Fixture* fixture, gconstpointer user_data) {
  fixture->fail_run = true;
  g_autoptr(GError) error = Configure(fixture);
  g_assert_nonnull(error);
  g_assert_cmpstr(fixture->calls.back().c_str(), ==, "unloadScript");
  g_assert_false(g_file_test(fixture->script_path.c_str(), G_FILE_TEST_EXISTS));
  Dispose(fixture);
}

void Bounded(Fixture* fixture, gconstpointer user_data) {
  fixture->stall_run = true;
  const gint64 started = g_get_monotonic_time();
  g_autoptr(GError) error = Configure(fixture);
  g_assert_error(error, G_IO_ERROR, G_IO_ERROR_TIMED_OUT);
  g_assert_cmpint(g_get_monotonic_time() - started, <, 3000000);
  g_assert_cmpstr(fixture->calls.back().c_str(), ==, "unloadScript");
  g_assert_false(g_file_test(fixture->script_path.c_str(), G_FILE_TEST_EXISTS));
  Dispose(fixture);
}
}  // namespace

int main(int argc, char** argv) {
  g_test_init(&argc, &argv, nullptr);
  g_test_add("/CAP-1/kwin-lifecycle", Fixture, "modern", SetUp, Lifecycle, TearDown);
  g_test_add("/CAP-1/kwin-plasma5", Fixture, "legacy", SetUp, Lifecycle, TearDown);
  g_test_add("/CAP-1/no-kwin", Fixture, "absent", SetUp, Absent, TearDown);
  g_test_add("/CAP-1/kwin-load-refused", Fixture, "modern", SetUp, Rejected, TearDown);
  g_test_add("/CAP-1/kwin-run-failed", Fixture, "modern", SetUp, FailedRun, TearDown);
  g_test_add("/CAP-1/kwin-timeout", Fixture, "modern", SetUp, Bounded, TearDown);
  return g_test_run();
}
