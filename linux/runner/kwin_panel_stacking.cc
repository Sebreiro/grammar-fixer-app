#include "kwin_panel_stacking.h"

#include <glib/gstdio.h>

#include <string>

#include "kwin_panel_stacking_script.h"

namespace {
constexpr char kService[] = "org.kde.KWin";
constexpr char kInterface[] = "org.kde.kwin.Scripting";
constexpr char kPlugin[] = "com.divertedriver.HotkeyGrammarCorrector.panel-stacking";
constexpr int kCallTimeoutMs = 1000;

GVariant* Call(GDBusConnection* connection, const char* path,
               const char* interface, const char* method, GVariant* arguments,
               const GVariantType* reply_type, GError** error) {
  return g_dbus_connection_call_sync(
      connection, kService, path, interface, method, arguments, reply_type,
      G_DBUS_CALL_FLAGS_NO_AUTO_START, kCallTimeoutMs, nullptr, error);
}

struct TemporaryScript {
  gchar* directory = nullptr;
  gchar* path = nullptr;
  ~TemporaryScript() {
    if (path != nullptr) g_unlink(path);
    if (directory != nullptr) g_rmdir(directory);
    g_free(path);
    g_free(directory);
  }
};
}  // namespace

KWinPanelStacking::~KWinPanelStacking() {
  // Normal teardown calls Dispose and waits. This covers aborted startup too.
  if (loaded_) {
    g_dbus_connection_call(
        connection_, kService, "/Scripting", kInterface, "unloadScript",
        g_variant_new("(s)", kPlugin), nullptr, G_DBUS_CALL_FLAGS_NO_AUTO_START,
        kCallTimeoutMs, nullptr, nullptr, nullptr);
  }
  g_clear_object(&connection_);
}

GTask* KWinPanelStacking::NewTask(GObject* source, GAsyncReadyCallback callback,
                                gpointer user_data) {
  GTask* task = g_task_new(source, nullptr, callback, user_data);
  g_task_set_task_data(
      task, new std::shared_ptr<KWinPanelStacking>(shared_from_this()),
      [](gpointer data) {
        delete static_cast<std::shared_ptr<KWinPanelStacking>*>(data);
      });
  return task;
}

void KWinPanelStacking::Configure(GDBusConnection* connection,
                                 GAsyncReadyCallback callback,
                                 gpointer user_data) {
  g_autoptr(GTask) task = NewTask(G_OBJECT(connection), callback, user_data);
  g_task_run_in_thread(task, ConfigureOnWorker);
}

void KWinPanelStacking::ConfigureOnWorker(GTask* task, gpointer source,
                                         gpointer task_data,
                                         GCancellable* cancellable) {
  const auto stacking = *static_cast<std::shared_ptr<KWinPanelStacking>*>(task_data);
  std::lock_guard<std::mutex> lock(stacking->lifecycle_mutex_);
  if (stacking->disposed_) {
    g_task_return_new_error(task, G_IO_ERROR, G_IO_ERROR_CLOSED,
                            "Panel stacking is disposed");
    return;
  }
  if (stacking->connection_ == nullptr) {
    stacking->connection_ = G_DBUS_CONNECTION(g_object_ref(source));
  }
  if (stacking->loaded_) {
    g_task_return_boolean(task, TRUE);
    return;
  }
  g_autoptr(GError) error = nullptr;
  if (!stacking->Load(&error)) {
    stacking->Unload(nullptr);
    g_task_return_error(task, g_steal_pointer(&error));
    return;
  }
  g_task_return_boolean(task, TRUE);
}

std::optional<bool> KWinPanelStacking::HasService(GError** error) {
  g_autoptr(GVariant) owner = g_dbus_connection_call_sync(
      connection_, "org.freedesktop.DBus", "/org/freedesktop/DBus",
      "org.freedesktop.DBus", "NameHasOwner", g_variant_new("(s)", kService),
      G_VARIANT_TYPE("(b)"), G_DBUS_CALL_FLAGS_NONE, kCallTimeoutMs, nullptr, error);
  if (owner == nullptr) return std::nullopt;
  gboolean available = FALSE;
  g_variant_get(owner, "(b)", &available);
  return available != FALSE;
}

bool KWinPanelStacking::Load(GError** error) {
  const auto available = HasService(error);
  if (!available) return false;
  if (!*available) return true;

  // Recover our runtime script after a crash; no user's scripts are touched.
  g_autoptr(GVariant) unloaded = Call(
      connection_, "/Scripting", kInterface, "unloadScript",
      g_variant_new("(s)", kPlugin), G_VARIANT_TYPE("(b)"), error);
  if (unloaded == nullptr) return false;

  TemporaryScript script;
  script.directory = g_dir_make_tmp("hgc-kwin-XXXXXX", error);
  if (script.directory == nullptr) return false;
  script.path = g_build_filename(script.directory, "panel.js", nullptr);
  if (!g_file_set_contents(script.path, kKWinPanelStackingScript, -1, error)) {
    return false;
  }
  // KWin reads the file asynchronously; retain it until run's reply arrives.
  return LoadFile(script.path, error);
}

bool KWinPanelStacking::LoadFile(const char* path, GError** error) {
  g_autoptr(GVariant) reply = Call(
      connection_, "/Scripting", kInterface, "loadScript",
      g_variant_new("(ss)", path, kPlugin), G_VARIANT_TYPE("(i)"), error);
  if (reply == nullptr) return false;
  gint32 script_id = -1;
  g_variant_get(reply, "(i)", &script_id);
  if (script_id < 0) {
    g_set_error_literal(error, G_IO_ERROR, G_IO_ERROR_FAILED,
                        "KWin refused the panel stacking script");
    return false;
  }
  loaded_ = true;
  return Run(script_id, error);
}

bool KWinPanelStacking::Run(int script_id, GError** error) {
  const std::string modern_name = "Script" + std::to_string(script_id);
  const std::string modern_path = "/Scripting/" + modern_name;
  // Inspect the common parent: Qt may reject an unknown script path instead
  // of returning an empty node, which would otherwise break Plasma 5.
  g_autoptr(GVariant) inspection = Call(
      connection_, "/Scripting", "org.freedesktop.DBus.Introspectable",
      "Introspect", nullptr, G_VARIANT_TYPE("(s)"), error);
  if (inspection == nullptr) return false;
  const gchar* xml = nullptr;
  g_variant_get(inspection, "(&s)", &xml);
  g_autoptr(GDBusNodeInfo) node = g_dbus_node_info_new_for_xml(xml, error);
  if (node == nullptr) return false;
  const std::string legacy_path = "/" + std::to_string(script_id);
  const char* path = legacy_path.c_str();
  for (auto** child = node->nodes; child != nullptr && *child != nullptr; ++child) {
    if (modern_name == (*child)->path) path = modern_path.c_str();
  }
  g_autoptr(GVariant) reply = Call(connection_, path, "org.kde.kwin.Script",
                                  "run", nullptr, G_VARIANT_TYPE("()"), error);
  return reply != nullptr;
}

bool KWinPanelStacking::Unload(GError** error) {
  if (!loaded_) return true;
  g_autoptr(GVariant) reply = Call(
      connection_, "/Scripting", kInterface, "unloadScript",
      g_variant_new("(s)", kPlugin), G_VARIANT_TYPE("(b)"), error);
  if (reply == nullptr) return false;
  loaded_ = false;
  return true;
}

void KWinPanelStacking::Dispose(GAsyncReadyCallback callback, gpointer user_data) {
  g_autoptr(GTask) task = NewTask(nullptr, callback, user_data);
  g_task_run_in_thread(task, DisposeOnWorker);
}

void KWinPanelStacking::DisposeOnWorker(GTask* task, gpointer source,
                                       gpointer task_data,
                                       GCancellable* cancellable) {
  const auto stacking = *static_cast<std::shared_ptr<KWinPanelStacking>*>(task_data);
  std::lock_guard<std::mutex> lock(stacking->lifecycle_mutex_);
  stacking->disposed_ = true;
  g_autoptr(GError) error = nullptr;
  if (!stacking->Unload(&error)) {
    g_task_return_error(task, g_steal_pointer(&error));
    return;
  }
  g_task_return_boolean(task, TRUE);
}
