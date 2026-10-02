#ifndef RUNNER_TRAY_ACTIVATION_TOKEN_H_
#define RUNNER_TRAY_ACTIVATION_TOKEN_H_

#include <gio/gio.h>

#include <memory>
#include <mutex>
#include <string>

// Ayatana 0.5.93 shares g_bus_get's connection but lacks KDE's token method.
// The filter adds that method without altering indicator/menu ownership.
class TrayActivationToken {
 public:
  TrayActivationToken();
  ~TrayActivationToken();
  TrayActivationToken(const TrayActivationToken&) = delete;
  TrayActivationToken& operator=(const TrayActivationToken&) = delete;

  void Attach(GDBusConnection* connection);
  std::string Take();

 private:
  struct PendingToken {
    std::mutex mutex;
    std::string value;
  };

  static GDBusMessage* Filter(GDBusConnection* connection,
                             GDBusMessage* message,
                             gboolean incoming,
                             gpointer user_data);
  static GDBusMessage* AcceptToken(GDBusMessage* message,
                                   const std::shared_ptr<PendingToken>& pending);
  std::shared_ptr<PendingToken> pending_;
  GDBusConnection* connection_ = nullptr;
  guint filter_id_ = 0;
};

#endif  // RUNNER_TRAY_ACTIVATION_TOKEN_H_
