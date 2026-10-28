// The "org.familyscreentime/platform" channel on Windows (see
// lib/src/platform.dart): the installed apps, their names and icons, the
// monitor's state, the account. In the interface and in the monitor.
#ifndef RUNNER_PLATFORM_CHANNEL_H_
#define RUNNER_PLATFORM_CHANNEL_H_

#include <flutter/binary_messenger.h>
#include <flutter/encodable_value.h>
#include <flutter/method_channel.h>

#include <memory>
#include <string>

class PlatformChannel {
 public:
  explicit PlatformChannel(flutter::BinaryMessenger* messenger);

  // Calls [method] on the Dart side, without arguments.
  void Notify(const std::string& method);

 private:
  void Handle(const flutter::MethodCall<flutter::EncodableValue>& call,
              std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
                  result);

  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;
};

// Whether the monitor runs in this session.
bool MonitorRunning();

// Starts the monitor in this session, unless it runs already.
bool StartMonitor();

// Whether the monitor starts at sign-in: for every account (the
// installer's), or for this one.
bool AutostartSet();

// Makes the monitor start at each sign-in of this account.
void SetAutostart();

// Whether this account is an administrator of the PC.
bool IsAdminAccount();

// Brings the interface to the front, or starts it.
void OpenInterface();

#endif  // RUNNER_PLATFORM_CHANNEL_H_
