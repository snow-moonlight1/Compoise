#include "single_instance.h"

#include <aclapi.h>
#include <sddl.h>

#include <cstdint>
#include <cstring>
#include <mutex>

namespace {

constexpr DWORD kForwardBudgetMs = 30000;
constexpr size_t kMaxArguments = 64;
constexpr size_t kMaxArgumentBytes = 32768;
constexpr size_t kMaxMessageBytes = 65536;
constexpr uint32_t kAckDelivered = 0;
constexpr uint32_t kAckBusy = 1;
constexpr uint32_t kAckRejected = 2;

enum class ForwardResult { delivered, busyTimedOut, unavailable, rejected };

struct State {
  std::mutex mu;
  HANDLE owner_mutex = nullptr;
  HANDLE pipe = nullptr;
  std::wstring pipe_name;
  std::string scope = "uninitialized";
  HWND window = nullptr;
  bool listening = false;
  bool shutting_down = false;
  bool pending_show = false;
  SingleInstanceDispatcher dispatcher;
  std::vector<std::vector<std::string>> pending;
};

State& Gate() {
  static State* state = new State();
  return *state;
}

void AppendU32(std::string* out, uint32_t value) {
  char bytes[4] = {
      static_cast<char>(value & 0xff),
      static_cast<char>((value >> 8) & 0xff),
      static_cast<char>((value >> 16) & 0xff),
      static_cast<char>((value >> 24) & 0xff),
  };
  out->append(bytes, 4);
}

bool ReadU32(const uint8_t* data, size_t size, size_t* offset, uint32_t* value) {
  if (*offset + 4 > size) return false;
  *value = static_cast<uint32_t>(data[*offset]) |
           (static_cast<uint32_t>(data[*offset + 1]) << 8) |
           (static_cast<uint32_t>(data[*offset + 2]) << 16) |
           (static_cast<uint32_t>(data[*offset + 3]) << 24);
  *offset += 4;
  return true;
}

bool ReadU64(const uint8_t* data, size_t size, size_t* offset, uint64_t* value) {
  uint32_t low = 0;
  uint32_t high = 0;
  if (!ReadU32(data, size, offset, &low) || !ReadU32(data, size, offset, &high)) {
    return false;
  }
  *value = static_cast<uint64_t>(low) | (static_cast<uint64_t>(high) << 32);
  return true;
}

bool CurrentUserSid(std::wstring* sid) {
  HANDLE token = nullptr;
  if (!OpenProcessToken(GetCurrentProcess(), TOKEN_QUERY, &token)) return false;
  DWORD length = 0;
  GetTokenInformation(token, TokenUser, nullptr, 0, &length);
  std::vector<uint8_t> buffer(length);
  if (!GetTokenInformation(token, TokenUser, buffer.data(), length, &length)) {
    CloseHandle(token);
    return false;
  }
  CloseHandle(token);
  auto* user = reinterpret_cast<TOKEN_USER*>(buffer.data());
  LPWSTR text = nullptr;
  if (!ConvertSidToStringSidW(user->User.Sid, &text) || text == nullptr) {
    return false;
  }
  *sid = text;
  LocalFree(text);
  return true;
}

bool UserOnlyAttributes(const std::wstring& sid, PSECURITY_DESCRIPTOR* descriptor,
                        SECURITY_ATTRIBUTES* attributes) {
  const std::wstring sddl = L"D:P(A;;GA;;;" + sid + L")";
  if (!ConvertStringSecurityDescriptorToSecurityDescriptorW(
          sddl.c_str(), SDDL_REVISION_1, descriptor, nullptr)) {
    return false;
  }
  attributes->nLength = sizeof(SECURITY_ATTRIBUTES);
  attributes->lpSecurityDescriptor = *descriptor;
  attributes->bInheritHandle = FALSE;
  return true;
}

bool EncodeArguments(const std::vector<std::string>& arguments, std::string* out) {
  if (arguments.size() > kMaxArguments) return false;
  std::string body = "MFSI1";
  AppendU32(&body, static_cast<uint32_t>(arguments.size()));
  for (const auto& argument : arguments) {
    if (argument.size() > kMaxArgumentBytes) return false;
    AppendU32(&body, static_cast<uint32_t>(argument.size()));
    body.append(argument);
  }
  if (body.size() > kMaxMessageBytes) return false;
  *out = std::move(body);
  return true;
}

bool DecodeArguments(const uint8_t* data, size_t size,
                     std::vector<std::string>* arguments) {
  if (size < 9 || std::memcmp(data, "MFSI1", 5) != 0) return false;
  size_t offset = 5;
  uint32_t count = 0;
  if (!ReadU32(data, size, &offset, &count) || count > kMaxArguments) return false;
  std::vector<std::string> decoded;
  decoded.reserve(count);
  for (uint32_t i = 0; i < count; ++i) {
    uint32_t length = 0;
    if (!ReadU32(data, size, &offset, &length) || length > kMaxArgumentBytes) {
      return false;
    }
    if (offset + length > size) return false;
    decoded.emplace_back(reinterpret_cast<const char*>(data + offset), length);
    offset += length;
  }
  if (offset != size) return false;
  *arguments = std::move(decoded);
  return true;
}

void WriteAck(HANDLE pipe, uint32_t status, uint64_t window) {
  uint8_t bytes[12];
  for (int i = 0; i < 4; ++i) {
    bytes[i] = static_cast<uint8_t>((status >> (8 * i)) & 0xff);
  }
  for (int i = 0; i < 8; ++i) {
    bytes[4 + i] = static_cast<uint8_t>((window >> (8 * i)) & 0xff);
  }
  DWORD written = 0;
  WriteFile(pipe, bytes, sizeof(bytes), &written, nullptr);
}

DWORD WINAPI PipeServerThread(LPVOID) {
  HANDLE pipe = Gate().pipe;
  while (pipe != nullptr) {
    BOOL connected = ConnectNamedPipe(pipe, nullptr);
    if (!connected && GetLastError() != ERROR_PIPE_CONNECTED) {
      if (GetLastError() == ERROR_NO_DATA || GetLastError() == ERROR_BROKEN_PIPE) {
        DisconnectNamedPipe(pipe);
        continue;
      }
      Sleep(50);
      continue;
    }

    std::vector<uint8_t> buffer(kMaxMessageBytes);
    DWORD read = 0;
    BOOL ok = ReadFile(pipe, buffer.data(), static_cast<DWORD>(buffer.size()), &read,
                       nullptr);
    std::vector<std::string> arguments;
    bool parsed = ok && DecodeArguments(buffer.data(), read, &arguments);
    uint32_t status = kAckRejected;
    uint64_t window_value = 0;
    if (parsed) {
      std::lock_guard<std::mutex> lock(Gate().mu);
      if (Gate().shutting_down) {
        status = kAckBusy;
      } else {
        Gate().pending.push_back(arguments);
        Gate().pending_show = true;
        window_value = static_cast<uint64_t>(
            reinterpret_cast<uintptr_t>(Gate().window));
        status = kAckDelivered;
      }
    }
    WriteAck(pipe, status, window_value);
    FlushFileBuffers(pipe);
    DisconnectNamedPipe(pipe);
    if (status == kAckDelivered && window_value != 0) {
      PostMessage(reinterpret_cast<HWND>(static_cast<uintptr_t>(window_value)),
                  kSingleInstanceActivateMessage, 0, 0);
    }
  }
  return 0;
}

HANDLE CreateOwnerPipe(const std::wstring& pipe_name, SECURITY_ATTRIBUTES* attributes) {
  return CreateNamedPipeW(
      pipe_name.c_str(),
      PIPE_ACCESS_DUPLEX | FILE_FLAG_FIRST_PIPE_INSTANCE,
      PIPE_TYPE_MESSAGE | PIPE_READMODE_MESSAGE | PIPE_WAIT | PIPE_REJECT_REMOTE_CLIENTS,
      1, static_cast<DWORD>(kMaxMessageBytes), static_cast<DWORD>(kMaxMessageBytes),
      0, attributes);
}

struct AcquireResult {
  bool primary = false;
  bool failed = false;
  bool existing = false;
};

AcquireResult TryAcquire(const std::wstring& sid, SECURITY_ATTRIBUTES* attributes) {
  AcquireResult result;
  std::wstring mutex_name = L"Global\\MatrixFlow.SingleInstance." + sid;
  std::string scope = "per-user-global";
  HANDLE mutex = CreateMutexW(attributes, TRUE, mutex_name.c_str());
  DWORD error = GetLastError();
  if (mutex == nullptr && error == ERROR_ACCESS_DENIED) {
    mutex_name = L"Local\\MatrixFlow.SingleInstance." + sid;
    scope = "per-session-mutex-with-per-user-pipe";
    mutex = CreateMutexW(attributes, TRUE, mutex_name.c_str());
    error = GetLastError();
  }
  if (mutex == nullptr) {
    result.failed = true;
    return result;
  }
  if (error == ERROR_ALREADY_EXISTS) {
    CloseHandle(mutex);
    result.existing = true;
    Gate().pipe_name = L"\\\\.\\pipe\\MatrixFlow.SingleInstance." + sid;
    return result;
  }

  const std::wstring pipe_name = L"\\\\.\\pipe\\MatrixFlow.SingleInstance." + sid;
  HANDLE pipe = CreateOwnerPipe(pipe_name, attributes);
  if (pipe == INVALID_HANDLE_VALUE || pipe == nullptr) {
    ReleaseMutex(mutex);
    CloseHandle(mutex);
    Gate().pipe_name = pipe_name;
    result.existing = true;
    return result;
  }

  Gate().owner_mutex = mutex;
  Gate().pipe = pipe;
  Gate().pipe_name = pipe_name;
  Gate().scope = scope;
  HANDLE thread = CreateThread(nullptr, 0, PipeServerThread, nullptr, 0, nullptr);
  if (thread == nullptr) {
    CloseHandle(pipe);
    Gate().pipe = nullptr;
    ReleaseMutex(mutex);
    CloseHandle(mutex);
    Gate().owner_mutex = nullptr;
    result.failed = true;
    return result;
  }
  CloseHandle(thread);
  result.primary = true;
  return result;
}

void ActivateForeignWindow(uint64_t raw) {
  HWND window = reinterpret_cast<HWND>(static_cast<uintptr_t>(raw));
  if (window == nullptr || !IsWindow(window)) return;
  DWORD process_id = 0;
  GetWindowThreadProcessId(window, &process_id);
#ifndef WP28_U2_HARNESS
  if (process_id != 0) AllowSetForegroundWindow(process_id);
#endif
  SingleInstanceRestoreWindow(window);
}

ForwardResult Forward(const std::wstring& pipe_name,
                      const std::vector<std::string>& arguments) {
  std::string message;
  if (!EncodeArguments(arguments, &message)) return ForwardResult::rejected;
  const DWORD started = GetTickCount();
  while (GetTickCount() - started < kForwardBudgetMs) {
    const DWORD elapsed = GetTickCount() - started;
    const DWORD remaining = kForwardBudgetMs - elapsed;
    const DWORD slice = remaining < 2000 ? remaining : 2000;
    if (!WaitNamedPipeW(pipe_name.c_str(), slice)) {
      Sleep(100);
      continue;
    }
    HANDLE client = CreateFileW(pipe_name.c_str(), GENERIC_READ | GENERIC_WRITE, 0,
                                nullptr, OPEN_EXISTING, 0, nullptr);
    if (client == INVALID_HANDLE_VALUE) {
      Sleep(100);
      continue;
    }
    DWORD mode = PIPE_READMODE_MESSAGE;
    SetNamedPipeHandleState(client, &mode, nullptr, nullptr);
    DWORD written = 0;
    if (!WriteFile(client, message.data(), static_cast<DWORD>(message.size()),
                   &written, nullptr) ||
        written != message.size()) {
      CloseHandle(client);
      Sleep(100);
      continue;
    }
    uint8_t ack[12];
    DWORD read = 0;
    if (!ReadFile(client, ack, sizeof(ack), &read, nullptr) || read != sizeof(ack)) {
      CloseHandle(client);
      Sleep(100);
      continue;
    }
    CloseHandle(client);
    size_t offset = 0;
    uint32_t status = 0;
    uint64_t window = 0;
    if (!ReadU32(ack, sizeof(ack), &offset, &status) ||
        !ReadU64(ack, sizeof(ack), &offset, &window)) {
      return ForwardResult::rejected;
    }
    if (status == kAckDelivered) {
      ActivateForeignWindow(window);
      return ForwardResult::delivered;
    }
    if (status == kAckBusy) {
      Sleep(200);
      continue;
    }
    return ForwardResult::rejected;
  }
  return ForwardResult::busyTimedOut;
}

void ShowFailure(bool existing) {
  const wchar_t* text =
      existing
          ? L"Compoise \x5df2\x5728\x8fd0\x884c\xff0c\x4f46\x8fd9\x6b21\x542f\x52a8\x65e0\x6cd5\x628a\x53c2\x6570\x4ea4\x7ed9\x73b0\x6709\x7a97\x53e3\x3002\n"
            L"Compoise is already running, but this launch could not reach it.\n"
            L"\x8bf7\x5148\x5173\x95ed\x73b0\x6709\x7a97\x53e3\x540e\x518d\x8bd5\x3002"
          : L"Compoise \x65e0\x6cd5\x5efa\x7acb\x5355\x5b9e\x4f8b\x4fdd\x62a4\xff0c\x56e0\x6b64\x6ca1\x6709\x6253\x5f00\x4efb\x52a1\x5e93\x3002\n"
            L"Compoise could not create its single-instance lock, so it did not open the task library.";
  MessageBoxW(nullptr, text, L"Compoise", MB_OK | MB_ICONWARNING | MB_SETFOREGROUND);
}

}  // namespace

bool SingleInstanceClaim(const std::vector<std::string>& arguments, int* exit_code) {
  std::wstring sid;
  if (!CurrentUserSid(&sid)) {
    ShowFailure(false);
    *exit_code = 2;
    return false;
  }
  PSECURITY_DESCRIPTOR descriptor = nullptr;
  SECURITY_ATTRIBUTES attributes{};
  if (!UserOnlyAttributes(sid, &descriptor, &attributes)) {
    ShowFailure(false);
    *exit_code = 2;
    return false;
  }

  bool saw_existing = false;
  std::wstring lock_identity = sid;
#ifdef WP28_U2_HARNESS
  wchar_t probe_namespace[64]{};
  const DWORD length = GetEnvironmentVariableW(
      L"WP28_U2_NAMESPACE", probe_namespace, 64);
  if (length != 36) {
    LocalFree(descriptor);
    *exit_code = 2;
    return false;
  }
  for (DWORD i = 0; i < length; ++i) {
    const wchar_t c = probe_namespace[i];
    if (!((c >= L'0' && c <= L'9') || (c >= L'a' && c <= L'f') || c == L'-')) {
      LocalFree(descriptor);
      *exit_code = 2;
      return false;
    }
  }
  lock_identity += L".WP28-U2.";
  lock_identity += probe_namespace;
#endif
  for (int attempt = 0; attempt < 3; ++attempt) {
    AcquireResult acquired = TryAcquire(lock_identity, &attributes);
    if (acquired.failed) {
      LocalFree(descriptor);
      ShowFailure(false);
      *exit_code = 2;
      return false;
    }
    if (acquired.primary) {
      LocalFree(descriptor);
      return true;
    }
    saw_existing = true;
    const ForwardResult forwarded = Forward(Gate().pipe_name, arguments);
    if (forwarded == ForwardResult::delivered) {
      LocalFree(descriptor);
      *exit_code = 0;
      return false;
    }
    if (forwarded == ForwardResult::rejected) {
      LocalFree(descriptor);
      ShowFailure(true);
      *exit_code = 2;
      return false;
    }
    Sleep(200);
  }
  LocalFree(descriptor);
  ShowFailure(saw_existing);
  *exit_code = 2;
  return false;
}

void SingleInstanceAttachWindow(HWND window) {
  bool post = false;
  {
    std::lock_guard<std::mutex> lock(Gate().mu);
    Gate().window = window;
    post = Gate().pending_show || !Gate().pending.empty();
  }
  if (post && window != nullptr) {
    PostMessage(window, kSingleInstanceActivateMessage, 0, 0);
  }
}

void SingleInstanceBeginShutdown() {
  std::lock_guard<std::mutex> lock(Gate().mu);
  Gate().shutting_down = true;
  Gate().window = nullptr;
}

void SingleInstanceSetDispatcher(SingleInstanceDispatcher dispatcher) {
  std::lock_guard<std::mutex> lock(Gate().mu);
  Gate().dispatcher = std::move(dispatcher);
}

std::vector<std::vector<std::string>> SingleInstanceListenAndTakePending() {
  std::lock_guard<std::mutex> lock(Gate().mu);
  Gate().listening = true;
  std::vector<std::vector<std::string>> batch = std::move(Gate().pending);
  Gate().pending.clear();
  return batch;
}

std::string SingleInstanceScope() {
  std::lock_guard<std::mutex> lock(Gate().mu);
  return Gate().scope;
}

void SingleInstanceRestoreWindow(HWND window) {
  if (window == nullptr || !IsWindow(window)) return;
#ifdef WP28_U2_HARNESS
  ShowWindow(window, SW_SHOWNOACTIVATE);
#else
  if (IsIconic(window)) {
    ShowWindow(window, SW_RESTORE);
  } else {
    ShowWindow(window, SW_SHOW);
  }
  SetForegroundWindow(window);
#endif
}

void SingleInstanceDrainOnUiThread() {
  HWND window = nullptr;
  bool listening = false;
  std::vector<std::vector<std::string>> batch;
  SingleInstanceDispatcher dispatcher;
  {
    std::lock_guard<std::mutex> lock(Gate().mu);
    window = Gate().window;
    listening = Gate().listening;
    dispatcher = Gate().dispatcher;
    Gate().pending_show = false;
    if (listening) {
      batch.swap(Gate().pending);
    }
  }
  if (window != nullptr) SingleInstanceRestoreWindow(window);
  if (listening && dispatcher && !batch.empty()) dispatcher(batch);
}
