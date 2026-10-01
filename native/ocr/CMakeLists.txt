cmake_minimum_required(VERSION 3.16)
# Standalone builds need a project. A nested project() clears Flutter's
# CMAKE_INSTALL_PREFIX_INITIALIZED_TO_DEFAULT and installs into Program Files.
if(CMAKE_SOURCE_DIR STREQUAL CMAKE_CURRENT_SOURCE_DIR)
  cmake_policy(SET CMP0091 NEW)
  project(matrixflow_ocr LANGUAGES CXX)
endif()

# All three platforms compile this source. Models and stb_image.h remain
# external until their provenance and redistribution terms are resolved.
# Parent projects pass WP17_STB_DIR as a normal variable. A plain set(CACHE)
# hides that value, so preserve it before declaring the cache entry.
set(_wp17_stb_from_parent "")
if(DEFINED WP17_STB_DIR AND NOT "${WP17_STB_DIR}" STREQUAL "")
  set(_wp17_stb_from_parent "${WP17_STB_DIR}")
endif()
set(WP17_STB_DIR "" CACHE PATH "Directory containing stb_image.h")
if(_wp17_stb_from_parent)
  set(WP17_STB_DIR "${_wp17_stb_from_parent}" CACHE PATH "Directory containing stb_image.h" FORCE)
endif()
set(WP17_NCNN_ROOT "" CACHE PATH "Root with ncnn-android-<abi>/install trees")
# A standalone build has no parent to translate the environment contract, so
# seed the cache from it. An explicit -D still wins because the cache entry
# already exists by the time these lines run.
if(NOT WP17_STB_DIR AND DEFINED ENV{WP17_OCR_STB_DIR} AND NOT "$ENV{WP17_OCR_STB_DIR}" STREQUAL "")
  set(WP17_STB_DIR "$ENV{WP17_OCR_STB_DIR}" CACHE PATH "Directory containing stb_image.h" FORCE)
  message(STATUS "WP17_STB_DIR from WP17_OCR_STB_DIR: ${WP17_STB_DIR}")
endif()
if(NOT WP17_NCNN_ROOT AND DEFINED ENV{WP17_OCR_NCNN_ROOT} AND NOT "$ENV{WP17_OCR_NCNN_ROOT}" STREQUAL "")
  set(WP17_NCNN_ROOT "$ENV{WP17_OCR_NCNN_ROOT}" CACHE PATH "Root with ncnn-android-<abi>/install trees" FORCE)
endif()
if(NOT ncnn_DIR AND DEFINED ENV{WP17_OCR_NCNN_DIR} AND NOT "$ENV{WP17_OCR_NCNN_DIR}" STREQUAL "")
  set(ncnn_DIR "$ENV{WP17_OCR_NCNN_DIR}" CACHE PATH "ncnn package directory")
  message(STATUS "ncnn_DIR from WP17_OCR_NCNN_DIR: ${ncnn_DIR}")
endif()
if(ANDROID AND WP17_NCNN_ROOT)
  set(ncnn_DIR "${WP17_NCNN_ROOT}/ncnn-android-${ANDROID_ABI}/install/lib/cmake/ncnn")
endif()
if(NOT EXISTS "${WP17_STB_DIR}/stb_image.h")
  message(FATAL_ERROR "Set WP17_STB_DIR to the verified external stb_image.h directory")
endif()
find_package(ncnn REQUIRED)
# Android ncnn exports -fno-exceptions after consumer flags. The C ABI still
# needs try/catch, and catch (...) does not require RTTI.
if(ANDROID)
  get_target_property(_wp17_ncnn_options ncnn INTERFACE_COMPILE_OPTIONS)
  if(_wp17_ncnn_options)
    list(REMOVE_ITEM _wp17_ncnn_options "-fno-exceptions")
    set_property(TARGET ncnn PROPERTY INTERFACE_COMPILE_OPTIONS ${_wp17_ncnn_options})
  endif()
endif()

# Flutter's first project() leaves CMP0091 unset, so the MSVC runtime
# property is ignored there and Debug inherits /MDd. The external ncnn
# library is Release /MD, so this directory must use /MD in every config.
if(MSVC)
  foreach(_wp17_flag CMAKE_CXX_FLAGS_DEBUG CMAKE_C_FLAGS_DEBUG)
    if(DEFINED ${_wp17_flag})
      string(REPLACE "/MDd" "/MD" ${_wp17_flag} "${${_wp17_flag}}")
    endif()
  endforeach()
endif()

add_library(matrixflow_ocr SHARED ocr_runtime.cpp)
target_compile_features(matrixflow_ocr PRIVATE cxx_std_17)
target_include_directories(matrixflow_ocr PRIVATE "${WP17_STB_DIR}")
target_link_libraries(matrixflow_ocr PRIVATE ncnn)
if(MSVC)
  set_target_properties(matrixflow_ocr PROPERTIES MSVC_RUNTIME_LIBRARY "MultiThreadedDLL")
  target_compile_options(matrixflow_ocr PRIVATE $<$<CONFIG:Debug>:/MD>)
  target_compile_definitions(matrixflow_ocr PRIVATE
    $<$<CONFIG:Debug>:_ITERATOR_DEBUG_LEVEL=0>)
endif()
set_target_properties(matrixflow_ocr PROPERTIES CXX_VISIBILITY_PRESET hidden)
# The NDK toolchain defaults to -fno-exceptions. The C ABI uses try/catch
# so a native failure still returns JSON instead of aborting the process.
if(ANDROID OR CMAKE_CXX_COMPILER_ID MATCHES "Clang|GNU")
  target_compile_options(matrixflow_ocr PRIVATE -fexceptions)
endif()
if(WIN32)
  target_link_libraries(matrixflow_ocr PRIVATE psapi)
elseif(ANDROID)
  target_link_libraries(matrixflow_ocr PRIVATE log)
endif()

option(WP17_OCR_BUILD_SMOKE "Build a small C ABI caller for runtime validation" OFF)
if(WP17_OCR_BUILD_SMOKE)
  add_executable(matrixflow_ocr_smoke smoke.cpp)
  target_compile_features(matrixflow_ocr_smoke PRIVATE cxx_std_17)
  target_link_libraries(matrixflow_ocr_smoke PRIVATE matrixflow_ocr)
  # The summary line reports peak RSS, which needs psapi on Windows.
  if(WIN32)
    target_link_libraries(matrixflow_ocr_smoke PRIVATE psapi)
  endif()
endif()
