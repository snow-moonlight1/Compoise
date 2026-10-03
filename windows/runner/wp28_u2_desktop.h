#ifndef RUNNER_WP28_U2_DESKTOP_H_
#define RUNNER_WP28_U2_DESKTOP_H_
#ifdef WP28_U2_HARNESS
#include <windows.h>
#include <flutter/encodable_value.h>

bool Wp28U2ClaimDesktop();
void Wp28U2ReleaseDesktop();
flutter::EncodableMap Wp28U2DesktopStatus(HWND window);
#endif
#endif
