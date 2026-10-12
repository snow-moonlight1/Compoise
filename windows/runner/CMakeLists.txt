cmake_minimum_required(VERSION 3.14)
project(runner LANGUAGES CXX)

# Define the application target. To change its name, change BINARY_NAME in the
# top-level CMakeLists.txt, not the value here, or `flutter run` will no longer
# work.
#
# Any new source files that you add to the application should be added here.
add_executable(${BINARY_NAME} WIN32
  "flutter_window.cpp"
  "wp15_d3_validation.cpp"
  "main.cpp"
  "single_instance.cpp"
  "utils.cpp"
  "win32_window.cpp"
  "${FLUTTER_MANAGED_DIR}/generated_plugin_registrant.cc"
  "Runner.rc"
  "runner.exe.manifest"
)

# Apply the standard set of build settings. This can be removed for applications
# that need different build settings.
apply_standard_settings(${BINARY_NAME})

file(READ "${FLUTTER_MANAGED_DIR}/ephemeral/generated_config.cmake" FLUTTER_GENERATED_CONFIG)

# D3 native diagnostics require both the build environment and Dart opt-in.
string(FIND "${FLUTTER_GENERATED_CONFIG}" "V1AxNV9EM19ERVZJQ0U9dHJ1ZQ==" WP15_D3_DART_DEFINE)
if("$ENV{WP15_D3_DEVICE_BUILD}" STREQUAL "1")
  if(WP15_D3_DART_DEFINE EQUAL -1)
    message(FATAL_ERROR "WP15_D3_DEVICE_BUILD=1 requires WP15_D3_DEVICE=true")
  endif()
  target_compile_definitions(${BINARY_NAME} PRIVATE "WP15_D3_DEVICE")
elseif(NOT WP15_D3_DART_DEFINE EQUAL -1)
  message(FATAL_ERROR "WP15_D3_DEVICE=true requires WP15_D3_DEVICE_BUILD=1")
endif()

# Add preprocessor definitions for the build version.
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION=\"${FLUTTER_VERSION}\"")
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION_MAJOR=${FLUTTER_VERSION_MAJOR}")
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION_MINOR=${FLUTTER_VERSION_MINOR}")
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION_PATCH=${FLUTTER_VERSION_PATCH}")
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION_BUILD=${FLUTTER_VERSION_BUILD}")

# Disable Windows macros that collide with C++ standard library functions.
target_compile_definitions(${BINARY_NAME} PRIVATE "NOMINMAX")

# Add dependency libraries and include directories. Add any application-specific
# dependencies here.
target_link_libraries(${BINARY_NAME} PRIVATE flutter flutter_wrapper_app)
target_link_libraries(${BINARY_NAME} PRIVATE "dwmapi.lib" "advapi32.lib")
target_include_directories(${BINARY_NAME} PRIVATE "${CMAKE_SOURCE_DIR}")

# Run the Flutter tool portions of the build. This must not be removed.
add_dependencies(${BINARY_NAME} flutter_assemble)
