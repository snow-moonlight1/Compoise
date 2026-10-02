cmake_minimum_required(VERSION 3.14)
project(runner LANGUAGES CXX)

# Define the application target. To change its name, change BINARY_NAME in the
# top-level CMakeLists.txt, not the value here, or `flutter run` will no longer
# work.
#
# Any new source files that you add to the application should be added here.
add_executable(${BINARY_NAME} WIN32
  "flutter_window.cpp"
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

# Explicit diagnostic builds only; production builds cannot select a test lock.
file(READ "${FLUTTER_MANAGED_DIR}/ephemeral/generated_config.cmake" WP28_U2_FLUTTER_CONFIG)
# Base64 encoding of WP28_U2_HARNESS=true in Flutter's generated DART_DEFINES.
string(FIND "${WP28_U2_FLUTTER_CONFIG}" "V1AyOF9VMl9IQVJORVNTPXRydWU=" WP28_U2_DART_DEFINE)
if("$ENV{WP28_U2_HARNESS_BUILD}" STREQUAL "1")
  if(WP28_U2_DART_DEFINE EQUAL -1)
    message(FATAL_ERROR "WP28_U2_HARNESS_BUILD=1 requires --dart-define=WP28_U2_HARNESS=true")
  endif()
  target_compile_definitions(${BINARY_NAME} PRIVATE "WP28_U2_HARNESS")
elseif(NOT WP28_U2_DART_DEFINE EQUAL -1)
  message(FATAL_ERROR "WP28_U2_HARNESS=true requires WP28_U2_HARNESS_BUILD=1")
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
