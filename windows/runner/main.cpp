#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include "flutter_window.h"
#include "single_instance.h"
#include "utils.h"
#include "wp15_d3_validation.h"

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

#ifdef WP15_D3_DEVICE
  if (!Wp15D3ClaimIsolatedProcess()) return 2;
#endif

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);
  WindowsValidationTrace("COM initialized");

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  // A second process must exit before Flutter or the task library starts.
#ifndef WP15_D3_DEVICE
  int forwarded_exit = EXIT_SUCCESS;
  if (!SingleInstanceClaim(command_line_arguments, &forwarded_exit)) {
    ::CoUninitialize();
    return forwarded_exit;
  }

#endif

  flutter::DartProject project(L"data");
  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  Win32Window::Point origin(10, 10);
  Win32Window::Size size(1280, 720);
  if (!window.Create(L"Compoise", origin, size)) {
    window.Destroy();
    ::CoUninitialize();
#ifdef WP15_D3_DEVICE
    Wp15D3ReleaseIsolatedProcess();
#endif
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  WindowsValidationTrace("message loop exited");
  // window_manager's destroy posts WM_QUIT without destroying the HWND.
  // Tear down the derived window/engine while COM and the window are still
  // alive. The base destructor cannot dispatch FlutterWindow::OnDestroy.
  window.Destroy();
  WindowsValidationTrace("COM uninitialize begin");
  ::CoUninitialize();
  WindowsValidationTrace("COM uninitialize end");
#ifdef WP15_D3_DEVICE
  Wp15D3ReleaseIsolatedProcess();
#endif
  return EXIT_SUCCESS;
}
