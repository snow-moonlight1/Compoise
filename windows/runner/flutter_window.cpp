#include "flutter_window.h"

#include <optional>
#include <string>

#include "single_instance.h"

#include <vector>

#include <flutter/standard_method_codec.h>

#include "flutter/generated_plugin_registrant.h"

namespace {
constexpr int kMatrixFlowHotkeyId = 0x4D46;

// Windows reports a zone key ("China Standard Time"), which the Dart side
// translates through the pinned CLDR table. The current UTC offset and the
// display language are deliberately not consulted here.
std::string CurrentTimeZoneKeyName() {
  DYNAMIC_TIME_ZONE_INFORMATION info;
  if (::GetDynamicTimeZoneInformation(&info) == TIME_ZONE_ID_INVALID) {
    return std::string();
  }
  const std::wstring name(info.TimeZoneKeyName);
  if (name.empty()) return std::string();
  const int size = ::WideCharToMultiByte(CP_UTF8, 0, name.c_str(), -1, nullptr,
                                         0, nullptr, nullptr);
  if (size <= 1) return std::string();
  std::string utf8(static_cast<size_t>(size - 1), '\0');
  ::WideCharToMultiByte(CP_UTF8, 0, name.c_str(), -1, utf8.data(), size,
                        nullptr, nullptr);
  return utf8;
}
}  // namespace

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  hotkey_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(),
          "matrixflow/os14_hotkey", &flutter::StandardMethodCodec::GetInstance());
  hotkey_channel_->SetMethodCallHandler(
      [this](const auto& call, auto result) {
        if (call.method_name() == "hide") {
          ::ShowWindow(GetHandle(), SW_HIDE);
          result->Success(flutter::EncodableValue(::IsWindowVisible(GetHandle()) == 0));
          return;
        }
        if (call.method_name() == "show") {
          SingleInstanceRestoreWindow(GetHandle());
          result->Success(flutter::EncodableValue(::IsWindowVisible(GetHandle()) != 0));
          return;
        }
        if (call.method_name() == "isVisible") {
          result->Success(flutter::EncodableValue(::IsWindowVisible(GetHandle()) != 0));
          return;
        }
        if (call.method_name() == "unregister") {
          if (hotkey_registered_) {
            if (::UnregisterHotKey(GetHandle(), kMatrixFlowHotkeyId) == 0) {
              result->Success(flutter::EncodableValue(false));
              return;
            }
            hotkey_registered_ = false;
          }
          result->Success(flutter::EncodableValue(true));
          return;
        }
        if (call.method_name() != "register" || !call.arguments() ||
            !std::holds_alternative<flutter::EncodableMap>(*call.arguments())) {
          result->NotImplemented();
          return;
        }
        const auto& args = std::get<flutter::EncodableMap>(*call.arguments());
        const auto key_it = args.find(flutter::EncodableValue("keyCode"));
        const auto modifiers_it = args.find(flutter::EncodableValue("modifiers"));
        if (key_it == args.end() || modifiers_it == args.end() ||
            !std::holds_alternative<int>(key_it->second) ||
            !std::holds_alternative<int>(modifiers_it->second)) {
          result->Error("invalid_hotkey", "Invalid key code or modifiers");
          return;
        }
        if (hotkey_registered_) {
          if (::UnregisterHotKey(GetHandle(), kMatrixFlowHotkeyId) == 0) {
            result->Success(flutter::EncodableValue(false));
            return;
          }
          hotkey_registered_ = false;
        }
        const auto key_code = std::get<int>(key_it->second);
        const auto modifiers = std::get<int>(modifiers_it->second);
        // RegisterHotKey returns zero on a conflict or a system-reserved combo.
        hotkey_registered_ =
            ::RegisterHotKey(GetHandle(), kMatrixFlowHotkeyId, modifiers,
                             key_code) != 0;
        result->Success(flutter::EncodableValue(hotkey_registered_));
      });

  single_instance_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(),
          "matrixflow/single_instance",
          &flutter::StandardMethodCodec::GetInstance());
  SingleInstanceSetDispatcher([this](const std::vector<std::vector<std::string>>&
                                         batch) {
    if (!single_instance_channel_) return;
    for (const auto& args : batch) {
      flutter::EncodableList encoded;
      for (const auto& arg : args) {
        encoded.push_back(flutter::EncodableValue(arg));
      }
      single_instance_channel_->InvokeMethod(
          "onSecondInstance",
          std::make_unique<flutter::EncodableValue>(encoded));
    }
  });
  single_instance_channel_->SetMethodCallHandler([](const auto& call,
                                                    auto result) {
    if (call.method_name() == "listen") {
      const auto pending = SingleInstanceListenAndTakePending();
      flutter::EncodableList batch;
      for (const auto& args : pending) {
        flutter::EncodableList encoded;
        for (const auto& arg : args) {
          encoded.push_back(flutter::EncodableValue(arg));
        }
        batch.push_back(flutter::EncodableValue(encoded));
      }
      result->Success(flutter::EncodableValue(batch));
      return;
    }
    if (call.method_name() == "scope") {
      flutter::EncodableMap scope;
      scope[flutter::EncodableValue("scope")] =
          flutter::EncodableValue(SingleInstanceScope());
      result->Success(flutter::EncodableValue(scope));
      return;
    }
    result->NotImplemented();
  });
  SingleInstanceAttachWindow(GetHandle());

  timezone_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(),
          "matrixflow/device_time_zone",
          &flutter::StandardMethodCodec::GetInstance());
  timezone_channel_->SetMethodCallHandler([](const auto& call, auto result) {
    if (call.method_name() == "systemZone") {
      flutter::EncodableMap reply;
      reply[flutter::EncodableValue("platform")] =
          flutter::EncodableValue("windows");
      reply[flutter::EncodableValue("identity")] =
          flutter::EncodableValue(CurrentTimeZoneKeyName());
      result->Success(flutter::EncodableValue(reply));
      return;
    }
    result->NotImplemented();
  });

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  SingleInstanceBeginShutdown();
  SingleInstanceSetDispatcher(nullptr);
  single_instance_channel_.reset();
  timezone_channel_.reset();
  if (hotkey_registered_) {
    ::UnregisterHotKey(GetHandle(), kMatrixFlowHotkeyId);
    hotkey_registered_ = false;
  }
  hotkey_channel_.reset();
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  if (message == kSingleInstanceActivateMessage) {
    SingleInstanceDrainOnUiThread();
    return 0;
  }

  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case WM_HOTKEY:
      if (wparam == kMatrixFlowHotkeyId && hotkey_channel_) {
        hotkey_channel_->InvokeMethod("onHotkey", nullptr);
        return 0;
      }
      break;
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
    case WM_SETTINGCHANGE:
      // Windows documents no SPI_* code for a zone change; the time/date panel
      // broadcasts a settings change instead, so it is forwarded and the Dart
      // side re-reads and compares the identity before re-rendering.
      if (timezone_channel_) {
        timezone_channel_->InvokeMethod("onTimeZoneChanged", nullptr);
      }
      break;
    case WM_TIMECHANGE:
      if (timezone_channel_) {
        timezone_channel_->InvokeMethod("onTimeZoneChanged", nullptr);
      }
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
