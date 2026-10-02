#ifndef RUNNER_KWIN_PANEL_STACKING_H_
#define RUNNER_KWIN_PANEL_STACKING_H_

#include <gio/gio.h>

#include <memory>
#include <mutex>
#include <optional>

class KWinPanelStacking : public std::enable_shared_from_this<KWinPanelStacking> {
 public:
  ~KWinPanelStacking();

  void Configure(GDBusConnection* connection, GAsyncReadyCallback callback,
                 gpointer user_data);
  void Dispose(GAsyncReadyCallback callback, gpointer user_data);

 private:
  static void ConfigureOnWorker(GTask* task, gpointer source,
                                gpointer task_data, GCancellable* cancellable);
  static void DisposeOnWorker(GTask* task, gpointer source,
                              gpointer task_data, GCancellable* cancellable);
  GTask* NewTask(GObject* source, GAsyncReadyCallback callback, gpointer user_data);
  bool Load(GError** error);
  std::optional<bool> HasService(GError** error);
  bool LoadFile(const char* path, GError** error);
  bool Run(int script_id, GError** error);
  bool Unload(GError** error);

  GDBusConnection* connection_ = nullptr;
  bool loaded_ = false;
  bool disposed_ = false;
  std::mutex lifecycle_mutex_;
};

#endif  // RUNNER_KWIN_PANEL_STACKING_H_
