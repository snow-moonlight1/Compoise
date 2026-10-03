#include "wp15_d3_validation.h"
#ifdef WP15_D3_DEVICE
#include <optional>

namespace {
std::wstring root;
std::wstring run_namespace;
HANDLE isolated_mutex = nullptr;
HDESK private_desktop = nullptr;
HDESK original_desktop = nullptr;
std::optional<std::string> zone_override;
int reads = 0;
int settings_events = 0;
int time_events = 0;

std::wstring Environment(const wchar_t* key) {
  wchar_t value[32768]{};
  const DWORD size = GetEnvironmentVariableW(key, value, 32768);
  return size && size < 32768 ? std::wstring(value, size) : std::wstring();
}

bool IsGuid(const std::wstring& value) {
  if (value.size() != 36) return false;
  for (size_t i = 0; i < value.size(); ++i) {
    const bool dash = i == 8 || i == 13 || i == 18 || i == 23;
    if (dash ? value[i] != L'-' :
        !((value[i] >= L'0' && value[i] <= L'9') ||
          (value[i] >= L'a' && value[i] <= L'f'))) return false;
  }
  return true;
}

std::wstring CanonicalDirectory(const std::wstring& path) {
  const HANDLE handle = CreateFileW(path.c_str(), 0,
      FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE, nullptr,
      OPEN_EXISTING, FILE_FLAG_BACKUP_SEMANTICS, nullptr);
  if (handle == INVALID_HANDLE_VALUE) return {};
  wchar_t value[32768]{};
  const DWORD size = GetFinalPathNameByHandleW(handle, value, 32768,
                                             FILE_NAME_NORMALIZED);
  CloseHandle(handle);
  if (!size || size >= 32768) return {};
  std::wstring result(value, size);
  if (result.rfind(L"\\\\?\\", 0) == 0) result.erase(0, 4);
  while (!result.empty() && result.back() == L'\\') result.pop_back();
  return result;
}

bool SamePath(const std::wstring& left, const std::wstring& right) {
  return CompareStringOrdinal(left.c_str(), -1, right.c_str(), -1, TRUE) == CSTR_EQUAL;
}

std::string Utf8(const std::wstring& value) {
  const int size = WideCharToMultiByte(CP_UTF8, 0, value.data(),
      static_cast<int>(value.size()), nullptr, 0, nullptr, nullptr);
  std::string result(static_cast<size_t>(size), '\0');
  if (size) WideCharToMultiByte(CP_UTF8, 0, value.data(),
      static_cast<int>(value.size()), result.data(), size, nullptr, nullptr);
  return result;
}

std::wstring DesktopName(HDESK desktop) {
  wchar_t name[256]{};
  DWORD bytes = 0;
  if (!desktop || !GetUserObjectInformationW(desktop, UOI_NAME, name,
                                              sizeof(name), &bytes)) return {};
  return name;
}

bool CreatePrivateDesktop(const std::wstring& guid) {
  // No SwitchDesktop, input injection or host focus operation is permitted.
  // Assign before COM, Flutter or any application window is created.
  original_desktop = GetThreadDesktop(GetCurrentThreadId());
  private_desktop = CreateDesktopW((L"wp15-d3-" + guid).c_str(), nullptr,
      nullptr, 0, DESKTOP_CREATEWINDOW | DESKTOP_READOBJECTS |
      DESKTOP_WRITEOBJECTS | DESKTOP_ENUMERATE, nullptr);
  if (!private_desktop || !SetThreadDesktop(private_desktop)) return false;
  const HDESK input = OpenInputDesktop(0, FALSE, DESKTOP_READOBJECTS);
  const bool isolated = input && DesktopName(input) != DesktopName(private_desktop);
  if (input) CloseDesktop(input);
  return isolated;
}

}  // namespace

bool Wp15D3ClaimIsolatedProcess() {
  if (Environment(L"WP15_D3_RUN") != L"1") return false;
  const auto guid = Environment(L"WP15_D3_NAMESPACE");
  const auto supplied = Environment(L"WP15_D3_ROOT");
  if (!IsGuid(guid) || supplied.empty()) return false;
  wchar_t temporary[32768]{};
  if (!GetTempPathW(32768, temporary)) return false;
  const auto temp = CanonicalDirectory(temporary);
  const auto actual = CanonicalDirectory(supplied);
  const auto expected = temp + L"\\wp15-d3-device-" + guid;
  wchar_t full[32768]{};
  const DWORD length = GetFullPathNameW(supplied.c_str(), 32768, full, nullptr);
  // Existing directory, immediate canonical OS-temp child, exact GUID leaf;
  // reject junctions, dot components, relative roots and another user's data.
  if (temp.empty() || actual.empty() || !length || length >= 32768 ||
      !SamePath(actual, expected) || !SamePath(supplied, full) ||
      !SamePath(supplied, actual)) return false;
  const std::wstring name = L"Local\\Compoise.WP15D3." + guid;
  isolated_mutex = CreateMutexW(nullptr, TRUE, name.c_str());
  if (!isolated_mutex || GetLastError() == ERROR_ALREADY_EXISTS) {
    Wp15D3ReleaseIsolatedProcess();
    return false;
  }
  root = actual;
  run_namespace = guid;
  if (!CreatePrivateDesktop(guid)) {
    Wp15D3ReleaseIsolatedProcess();
    return false;
  }
  return true;
}

void Wp15D3ReleaseIsolatedProcess() {
  if (private_desktop) {
    if (original_desktop) SetThreadDesktop(original_desktop);
    CloseDesktop(private_desktop);
    private_desktop = nullptr;
  }
  if (isolated_mutex) {
    CloseHandle(isolated_mutex);
    isolated_mutex = nullptr;
  }
}

flutter::EncodableMap Wp15D3Status(HWND window) {
  RECT client{};
  GetClientRect(window, &client);
  flutter::EncodableMap result;
  const auto add = [&](const char* key, flutter::EncodableValue value) {
    result[flutter::EncodableValue(key)] = std::move(value);
  };
  add("nativeGate", flutter::EncodableValue(true));
  add("root", flutter::EncodableValue(Utf8(root)));
  add("namespace", flutter::EncodableValue(Utf8(run_namespace)));
  add("pid", flutter::EncodableValue(static_cast<int>(GetCurrentProcessId())));
  add("isolatedMutex", flutter::EncodableValue(isolated_mutex != nullptr));
  add("windowVisible", flutter::EncodableValue(IsWindowVisible(window) != 0));
  const auto desktop_name = DesktopName(GetThreadDesktop(GetCurrentThreadId()));
  add("desktop", flutter::EncodableValue(Utf8(desktop_name)));
  const HDESK input = OpenInputDesktop(0, FALSE, DESKTOP_READOBJECTS);
  const bool isolated = input && desktop_name == L"wp15-d3-" + run_namespace &&
      DesktopName(input) != desktop_name;
  if (input) CloseDesktop(input);
  add("privateDesktop", flutter::EncodableValue(isolated));
  DWORD foreground_pid = 0;
  GetWindowThreadProcessId(GetForegroundWindow(), &foreground_pid);
  add("foregroundOwned", flutter::EncodableValue(foreground_pid == GetCurrentProcessId()));
  add("clientWidth", flutter::EncodableValue(client.right));
  add("clientHeight", flutter::EncodableValue(client.bottom));
  add("reads", flutter::EncodableValue(reads));
  add("settingsEvents", flutter::EncodableValue(settings_events));
  add("timeEvents", flutter::EncodableValue(time_events));
  add("queryInjected", flutter::EncodableValue(zone_override.has_value()));
  return result;
}

std::string Wp15D3EffectiveZone(const std::string& actual) {
  return zone_override.value_or(actual);
}

bool Wp15D3SetZoneOverride(const std::string* identity) {
  if (!identity) { zone_override.reset(); return true; }
  if (*identity != "Tokyo Standard Time" && *identity != "Eastern Standard Time" &&
      *identity != "China Standard Time" && *identity != "D3 unmapped identity") return false;
  zone_override = *identity;
  return true;
}
void Wp15D3ZoneRead() { ++reads; }
void Wp15D3WindowEvent(UINT message) {
  if (message == WM_SETTINGCHANGE) ++settings_events;
  if (message == WM_TIMECHANGE) ++time_events;
}
bool Wp15D3SendWindowEvent(HWND window, UINT message) {
  if (!IsWindow(window) ||
      (message != WM_SETTINGCHANGE && message != WM_TIMECHANGE)) return false;
  const int before = message == WM_SETTINGCHANGE ? settings_events : time_events;
  // WM_SETTINGCHANGE may carry a pointer and is a synchronous Windows message.
  // Dispatch only to this process's HWND, never HWND_BROADCAST.
  SendMessageW(window, message, 0, 0);
  const int after = message == WM_SETTINGCHANGE ? settings_events : time_events;
  return after == before + 1;
}
bool Wp15D3Resize(HWND window, int width, int height) {
  if (width < 200 || width > 2400 || height < 400 || height > 1600) return false;
  RECT bounds{0, 0, width, height};
  const auto style = static_cast<DWORD>(GetWindowLongPtrW(window, GWL_STYLE));
  const auto extended = static_cast<DWORD>(GetWindowLongPtrW(window, GWL_EXSTYLE));
  using Adjust = BOOL(WINAPI*)(LPRECT, DWORD, BOOL, DWORD, UINT);
  const auto adjust = reinterpret_cast<Adjust>(GetProcAddress(
      GetModuleHandleW(L"user32.dll"), "AdjustWindowRectExForDpi"));
  if (adjust) adjust(&bounds, style, FALSE, extended, GetDpiForWindow(window));
  else AdjustWindowRectEx(&bounds, style, FALSE, extended);
  return SetWindowPos(window, HWND_BOTTOM, 0, 0, bounds.right - bounds.left,
      bounds.bottom - bounds.top, SWP_NOMOVE | SWP_NOACTIVATE) != 0;
}
#endif
