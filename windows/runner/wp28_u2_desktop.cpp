#include "wp28_u2_desktop.h"
#ifdef WP28_U2_HARNESS
#include <string>
#include "utils.h"

namespace {
HDESK private_desktop = nullptr;
HDESK original_desktop = nullptr;
std::wstring root;
std::wstring run_namespace;

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
  BY_HANDLE_FILE_INFORMATION metadata{};
  if (!GetFileInformationByHandle(handle, &metadata) ||
      !(metadata.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY)) {
    CloseHandle(handle);
    return {};
  }
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

bool SamePath(const std::wstring& a, const std::wstring& b) {
  return CompareStringOrdinal(a.c_str(), -1, b.c_str(), -1, TRUE) == CSTR_EQUAL;
}

std::wstring DesktopName(HDESK desktop) {
  wchar_t name[256]{};
  DWORD bytes = 0;
  if (!desktop || !GetUserObjectInformationW(desktop, UOI_NAME, name,
                                              sizeof(name), &bytes)) return {};
  return name;
}
}  // namespace

bool Wp28U2ClaimDesktop() {
  // Reject before COM, Flutter, windows or any preferences/credential access.
  if (Environment(L"WP28_U2_RUN") != L"1") return false;
  const auto guid = Environment(L"WP28_U2_NAMESPACE");
  const auto supplied = Environment(L"WP28_U2_ROOT");
  if (!IsGuid(guid) || supplied.empty()) return false;
  wchar_t temporary[32768]{};
  const DWORD temp_size = GetTempPathW(32768, temporary);
  if (!temp_size || temp_size >= 32768) return false;
  const auto temp = CanonicalDirectory(temporary);
  const auto actual = CanonicalDirectory(supplied);
  const auto expected = temp + L"\\wp28-u2-device-" + guid;
  wchar_t full[32768]{};
  const DWORD length = GetFullPathNameW(supplied.c_str(), 32768, full, nullptr);
  if (temp.empty() || actual.empty() || !length || length >= 32768 ||
      !SamePath(actual, expected) || !SamePath(supplied, full) ||
      !SamePath(supplied, actual)) return false;
  original_desktop = GetThreadDesktop(GetCurrentThreadId());
  // Secondary launches share only their fixture's private desktop and pipe.
  private_desktop = CreateDesktopW((L"wp28-u2-" + guid).c_str(), nullptr,
      nullptr, 0, DESKTOP_CREATEWINDOW | DESKTOP_READOBJECTS |
      DESKTOP_WRITEOBJECTS | DESKTOP_ENUMERATE, nullptr);
  if (!private_desktop || !SetThreadDesktop(private_desktop)) {
    Wp28U2ReleaseDesktop();
    return false;
  }
  const HDESK input = OpenInputDesktop(0, FALSE, DESKTOP_READOBJECTS);
  const bool isolated = input && DesktopName(input) != DesktopName(private_desktop);
  if (input) CloseDesktop(input);
  if (!isolated) {
    Wp28U2ReleaseDesktop();
    return false;
  }
  root = actual;
  run_namespace = guid;
  return true;
}

void Wp28U2ReleaseDesktop() {
  if (private_desktop) {
    if (original_desktop) SetThreadDesktop(original_desktop);
    CloseDesktop(private_desktop);
    private_desktop = nullptr;
  }
}

flutter::EncodableMap Wp28U2DesktopStatus(HWND window) {
  const auto desktop_name = DesktopName(GetThreadDesktop(GetCurrentThreadId()));
  const HDESK input = OpenInputDesktop(0, FALSE, DESKTOP_READOBJECTS);
  const bool isolated = input && desktop_name == L"wp28-u2-" + run_namespace &&
      DesktopName(input) != desktop_name;
  if (input) CloseDesktop(input);
  DWORD foreground_pid = 0;
  GetWindowThreadProcessId(GetForegroundWindow(), &foreground_pid);
  flutter::EncodableMap result;
  const auto add = [&](const char* key, flutter::EncodableValue value) {
    result[flutter::EncodableValue(key)] = std::move(value);
  };
  add("nativeGate", flutter::EncodableValue(true));
  add("pid", flutter::EncodableValue(static_cast<int>(GetCurrentProcessId())));
  add("root", flutter::EncodableValue(Utf8FromUtf16(root.c_str())));
  add("namespace", flutter::EncodableValue(Utf8FromUtf16(run_namespace.c_str())));
  add("desktop", flutter::EncodableValue(Utf8FromUtf16(desktop_name.c_str())));
  add("privateDesktop", flutter::EncodableValue(isolated));
  add("foregroundOwned", flutter::EncodableValue(foreground_pid == GetCurrentProcessId()));
  add("windowVisible", flutter::EncodableValue(IsWindowVisible(window) != 0));
  return result;
}
#endif
