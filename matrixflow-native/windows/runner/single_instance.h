#ifndef RUNNER_SINGLE_INSTANCE_H_
#define RUNNER_SINGLE_INSTANCE_H_

#include <windows.h>

#include <functional>
#include <string>
#include <vector>

// Posted to the primary window when another launch forwarded its arguments.
constexpr UINT kSingleInstanceActivateMessage = WM_APP + 0x21;

// One batch of command-line arguments from a secondary launch.
using SingleInstanceDispatcher =
    std::function<void(const std::vector<std::vector<std::string>>&)>;

// Returns true when this process owns the per-user instance and may open the
// task library. Returns false when it forwarded its arguments to that owner,
// or when it refused to start so it would not become a second writer.
// |exit_code| is set only when this function returns false.
bool SingleInstanceClaim(const std::vector<std::string>& arguments,
                         int* exit_code);

void SingleInstanceAttachWindow(HWND window);
void SingleInstanceBeginShutdown();
void SingleInstanceSetDispatcher(SingleInstanceDispatcher dispatcher);
std::vector<std::vector<std::string>> SingleInstanceListenAndTakePending();
std::string SingleInstanceScope();
void SingleInstanceRestoreWindow(HWND window);
void SingleInstanceDrainOnUiThread();

#endif  // RUNNER_SINGLE_INSTANCE_H_
