#include "panel_activation.h"

#ifdef GDK_WINDOWING_WAYLAND
#include <gdk/gdkwayland.h>
#endif

#include <memory>
#include <optional>
#include <string>

#include "kwin_panel_stacking.h"
#include "tray_activation_token.h"

namespace {
struct PanelActivationBridge {
  GtkWindow* window;
  std::shared_ptr<TrayActivationToken> tray_tokens;
  std::shared_ptr<KWinPanelStacking> stacking;
};

struct PanelLifecycleRequest {
  FlMethodCall* call;
  std::shared_ptr<TrayActivationToken> tray_tokens;
  std::shared_ptr<KWinPanelStacking> stacking;
  bool wayland;
  ~PanelLifecycleRequest() { g_object_unref(call); }
};

struct ActivationRequest {
  bool from_tray;
  std::string token;
};

std::optional<ActivationRequest> DecodeActivation(FlValue* args) {
  if (args == nullptr || fl_value_get_type(args) != FL_VALUE_TYPE_MAP) {
    return std::nullopt;
  }
  FlValue* token = fl_value_lookup_string(args, "token");
  FlValue* from_tray = fl_value_lookup_string(args, "fromTray");
  if (from_tray == nullptr || fl_value_get_type(from_tray) != FL_VALUE_TYPE_BOOL ||
      (token != nullptr && fl_value_get_type(token) != FL_VALUE_TYPE_NULL &&
       fl_value_get_type(token) != FL_VALUE_TYPE_STRING)) {
    return std::nullopt;
  }
  return ActivationRequest{
      fl_value_get_bool(from_tray) != FALSE,
      token != nullptr && fl_value_get_type(token) == FL_VALUE_TYPE_STRING
          ? fl_value_get_string(token)
          : ""};
}

std::string PresentationToken(const ActivationRequest& request,
                              const std::string& tray_token) {
  return request.from_tray ? tray_token : request.token;
}

void OnStackingReady(GObject* source, GAsyncResult* result, gpointer user_data) {
  std::unique_ptr<PanelLifecycleRequest> request(
      static_cast<PanelLifecycleRequest*>(user_data));
  g_autoptr(GError) error = nullptr;
  if (!g_task_propagate_boolean(G_TASK(result), &error)) {
    fl_method_call_respond_error(request->call, "panel-stacking-unavailable",
                                error->message, nullptr, nullptr);
    return;
  }
  fl_method_call_respond_success(request->call, nullptr, nullptr);
}

void OnBusReady(GObject* source, GAsyncResult* result, gpointer user_data) {
  std::unique_ptr<PanelLifecycleRequest> request(
      static_cast<PanelLifecycleRequest*>(user_data));
  g_autoptr(GError) error = nullptr;
  g_autoptr(GDBusConnection) connection = g_bus_get_finish(result, &error);
  if (connection == nullptr) {
    fl_method_call_respond_error(request->call, "session-bus-unavailable",
                                "The session bus could not be reached", nullptr,
                                nullptr);
    return;
  }
  request->tray_tokens->Attach(connection);
  if (request->wayland) {
    request->stacking->Configure(connection, OnStackingReady, request.release());
    return;
  }
  fl_method_call_respond_success(request->call, nullptr, nullptr);
}

bool IsWayland(GtkWindow* window) {
#ifdef GDK_WINDOWING_WAYLAND
  return GDK_IS_WAYLAND_DISPLAY(gtk_widget_get_display(GTK_WIDGET(window)));
#else
  return false;
#endif
}

void Present(GtkWindow* window, const std::string& token) {
#ifdef GDK_WINDOWING_WAYLAND
  GdkDisplay* display = gtk_widget_get_display(GTK_WIDGET(window));
  if (GDK_IS_WAYLAND_DISPLAY(display) && !token.empty()) {
    // GTK consumes this display-scoped ID inside the following focus request.
    // Keep the two operations together on GTK's main thread.
    gdk_wayland_display_set_startup_notification_id(display, token.c_str());
  }
#endif
  gtk_window_present(window);
}

void RequestPresentation(PanelActivationBridge* bridge, FlMethodCall* call) {
  const auto activation = DecodeActivation(fl_method_call_get_args(call));
  if (!activation) {
    fl_method_call_respond_error(call, "invalid-activation",
                                "Invalid activation context", nullptr, nullptr);
    return;
  }
  // Every presentation consumes stale tray provenance too. A token supplied by
  // the portal or a plain second launch must never borrow a tray interaction.
  const std::string tray_token = bridge->tray_tokens->Take();
  Present(bridge->window, PresentationToken(*activation, tray_token));
  fl_method_call_respond_success(call, nullptr, nullptr);
}

void OnMethodCall(FlMethodChannel* channel, FlMethodCall* call,
                  gpointer user_data) {
  auto* bridge = static_cast<PanelActivationBridge*>(user_data);
  const gchar* method = fl_method_call_get_name(call);
  if (g_strcmp0(method, "initialize") == 0) {
    auto* request = new PanelLifecycleRequest{
        FL_METHOD_CALL(g_object_ref(call)), bridge->tray_tokens, bridge->stacking,
        IsWayland(bridge->window)};
    g_bus_get(G_BUS_TYPE_SESSION, nullptr, OnBusReady, request);
    return;
  }
  if (g_strcmp0(method, "dispose") == 0) {
    auto* request = new PanelLifecycleRequest{
        FL_METHOD_CALL(g_object_ref(call)), bridge->tray_tokens, bridge->stacking,
        false};
    bridge->stacking->Dispose(OnStackingReady, request);
    return;
  }
  if (g_strcmp0(method, "present") == 0) {
    RequestPresentation(bridge, call);
    return;
  }
  fl_method_call_respond_not_implemented(call, nullptr);
}
}  // namespace

void register_panel_activation(FlView* view) {
  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  g_autoptr(FlMethodChannel) channel = fl_method_channel_new(
      fl_engine_get_binary_messenger(fl_view_get_engine(view)),
      "com.divertedriver.HotkeyGrammarCorrector/panel_activation",
      FL_METHOD_CODEC(codec));
  g_object_set_data_full(G_OBJECT(view), "panel-activation-channel",
                         g_object_ref(channel), g_object_unref);
  auto* bridge = new PanelActivationBridge{
      GTK_WINDOW(gtk_widget_get_toplevel(GTK_WIDGET(view))),
      std::make_shared<TrayActivationToken>(),
      std::make_shared<KWinPanelStacking>()};
  fl_method_channel_set_method_call_handler(
      channel, OnMethodCall, bridge,
      [](gpointer data) { delete static_cast<PanelActivationBridge*>(data); });
}
