#include "tray_activation_token.h"

#include <utility>

namespace {
bool IsTokenCall(GDBusMessage* message) {
  const gchar* path = g_dbus_message_get_path(message);
  return g_dbus_message_get_message_type(message) ==
             G_DBUS_MESSAGE_TYPE_METHOD_CALL &&
         g_strcmp0(g_dbus_message_get_interface(message),
                   "org.kde.StatusNotifierItem") == 0 &&
         g_strcmp0(g_dbus_message_get_member(message),
                   "ProvideXdgActivationToken") == 0 &&
         path != nullptr &&
         g_str_has_prefix(path, "/org/ayatana/NotificationItem/");
}
}  // namespace

TrayActivationToken::TrayActivationToken()
    : pending_(std::make_shared<PendingToken>()) {}

TrayActivationToken::~TrayActivationToken() {
  if (connection_ != nullptr) {
    g_dbus_connection_remove_filter(connection_, filter_id_);
    g_object_unref(connection_);
  }
}

void TrayActivationToken::Attach(GDBusConnection* connection) {
  if (connection_ != nullptr) {
    return;
  }
  connection_ = G_DBUS_CONNECTION(g_object_ref(connection));
  // A removed filter may still be running on the bus worker. Its storage
  // therefore outlives the receiver until GLib invokes the destroy notifier.
  auto* pending = new std::shared_ptr<PendingToken>(pending_);
  filter_id_ = g_dbus_connection_add_filter(
      connection_, Filter, pending, [](gpointer data) {
        delete static_cast<std::shared_ptr<PendingToken>*>(data);
      });
}

std::string TrayActivationToken::Take() {
  std::lock_guard<std::mutex> lock(pending_->mutex);
  return std::exchange(pending_->value, std::string());
}

GDBusMessage* TrayActivationToken::Filter(GDBusConnection* connection,
                                        GDBusMessage* message,
                                        gboolean incoming,
                                        gpointer user_data) {
  if (!incoming || !IsTokenCall(message)) {
    return message;
  }
  const auto pending = *static_cast<std::shared_ptr<PendingToken>*>(user_data);
  g_autoptr(GDBusMessage) reply = AcceptToken(message, pending);
  if (!(g_dbus_message_get_flags(message) & G_DBUS_MESSAGE_FLAGS_NO_REPLY_EXPECTED)) {
    g_dbus_connection_send_message(
        connection, reply, G_DBUS_SEND_MESSAGE_FLAGS_NONE, nullptr, nullptr);
  }
  g_object_unref(message);
  return nullptr;
}

GDBusMessage* TrayActivationToken::AcceptToken(
    GDBusMessage* message, const std::shared_ptr<PendingToken>& pending) {
  GVariant* body = g_dbus_message_get_body(message);
  if (body == nullptr || !g_variant_is_of_type(body, G_VARIANT_TYPE("(s)"))) {
    return g_dbus_message_new_method_error_literal(
        message, "org.freedesktop.DBus.Error.InvalidArgs",
        "Expected one activation token string");
  }
  const gchar* token = nullptr;
  g_variant_get(body, "(&s)", &token);
  {
    // Store before the next menu Event is dispatched. GTK is deliberately
    // untouched on this bus worker thread.
    std::lock_guard<std::mutex> lock(pending->mutex);
    pending->value = token;
  }
  GDBusMessage* reply = g_dbus_message_new_method_reply(message);
  g_dbus_message_set_body(reply, g_variant_new("()"));
  return reply;
}
