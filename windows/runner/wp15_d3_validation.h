#ifndef RUNNER_WP15_D3_VALIDATION_H_
#define RUNNER_WP15_D3_VALIDATION_H_
#ifdef WP15_D3_DEVICE
#include <windows.h>
#include <flutter/encodable_value.h>
#include <string>

bool Wp15D3ClaimIsolatedProcess();
void Wp15D3ReleaseIsolatedProcess();
flutter::EncodableMap Wp15D3Status(HWND window);
std::string Wp15D3EffectiveZone(const std::string& actual);
bool Wp15D3SetZoneOverride(const std::string* identity);
void Wp15D3ZoneRead();
void Wp15D3WindowEvent(UINT message);
bool Wp15D3SendWindowEvent(HWND window, UINT message);
bool Wp15D3Resize(HWND window, int width, int height);
#endif
#endif
