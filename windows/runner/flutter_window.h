#ifndef RUNNER_FLUTTER_WINDOW_H_
#define RUNNER_FLUTTER_WINDOW_H_

#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <flutter/encodable_value.h>
#include <flutter/method_channel.h>

#include <memory>

#include "win32_window.h"

// A window that does nothing but host a Flutter view.
class FlutterWindow : public Win32Window {
 public:
  // Creates a new FlutterWindow hosting a Flutter view running |project|.
  explicit FlutterWindow(const flutter::DartProject& project);
  virtual ~FlutterWindow();

 protected:
  // Win32Window:
  bool OnCreate() override;
  void OnDestroy() override;
  LRESULT MessageHandler(HWND window, UINT const message, WPARAM const wparam,
                         LPARAM const lparam) noexcept override;

 private:
  // The project to run.
  flutter::DartProject project_;

  // The Flutter instance hosted by this window.
  std::unique_ptr<flutter::FlutterViewController> flutter_controller_;

  // The app-owned global hotkey channel checks the Win32 registration result.
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> hotkey_channel_;
  bool hotkey_registered_ = false;

  // Receives command lines forwarded by later Windows launches.
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>>
      single_instance_channel_;

  // Reports the Windows zone key and forwards WM_SETTINGCHANGE/WM_TIMECHANGE so
  // the schedule can re-render after a system zone change.
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>>
      timezone_channel_;
#ifdef WP15_D3_DEVICE
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>>
      d3_channel_;
#endif
};

#endif  // RUNNER_FLUTTER_WINDOW_H_
