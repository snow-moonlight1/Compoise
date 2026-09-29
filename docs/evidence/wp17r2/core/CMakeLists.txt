cmake_minimum_required(VERSION 3.16)
project(wp17r2_ocr CXX)

# The same source file builds for Windows, Linux and Android; only the
# dependency locations differ.  See docs/WP17_OCR_EVALUATION.md for the exact
# commands used for each platform.
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
if(NOT CMAKE_BUILD_TYPE)
    set(CMAKE_BUILD_TYPE Release)
endif()

option(WP17R2_WITH_TESSERACT "build the Tesseract 5 backend" ON)
set(WP17R2_THIRD_PARTY "${CMAKE_CURRENT_SOURCE_DIR}/third_party" CACHE PATH "directory holding stb_image.h")

# ---------------------------------------------------------------- third party
if(NOT EXISTS "${WP17R2_THIRD_PARTY}/stb_image.h")
    message(FATAL_ERROR
        "stb_image.h not found in ${WP17R2_THIRD_PARTY}. Run tools/fetch_assets.py first "
        "(it downloads stb_image.h, public domain / MIT) and pass "
        "-DWP17R2_THIRD_PARTY=<asset root>/third_party.")
endif()

# ---------------------------------------------------------------------- ncnn
# Point ncnn_DIR / CMAKE_PREFIX_PATH at an ncnn build or install tree, e.g.
#   -Dncnn_DIR=<ncnn>/build/install/lib/cmake/ncnn
find_package(ncnn REQUIRED)
message(STATUS "ncnn found: ${ncnn_DIR}")

add_executable(wp17r2_ocr wp17r2_ocr.cpp)
target_include_directories(wp17r2_ocr PRIVATE "${WP17R2_THIRD_PARTY}")
target_link_libraries(wp17r2_ocr PRIVATE ncnn)

# ---------------------------------------------------------------- tesseract
# We do not need Tesseract headers: core/tess_c_api.h re-declares the small
# C API surface we use.  Only the library has to be locatable.
#   Linux   : libtesseract.so from the distro package
#   Windows : libtesseract-5.dll linked directly (MSVC accepts a DLL as input);
#             the UB Mannheim installer ships no .lib and no headers.
set(WP17R2_TESSERACT_LIB "" CACHE FILEPATH "explicit path to libtesseract (.so/.dylib/.dll)")
set(WP17R2_TESSERACT_ROOT "" CACHE PATH "root of a Tesseract binary distribution")

if(WP17R2_WITH_TESSERACT)
    set(_tess_lib "")
    if(WP17R2_TESSERACT_LIB)
        set(_tess_lib "${WP17R2_TESSERACT_LIB}")
    elseif(WIN32)
        find_file(WP17R2_TESSERACT_DLL NAMES libtesseract-5.dll libtesseract.dll tesseract5.dll
                  HINTS "${WP17R2_TESSERACT_ROOT}" "${WP17R2_TESSERACT_ROOT}/bin"
                        "C:/Program Files/Tesseract-OCR")
        if(WP17R2_TESSERACT_DLL)
            set(_tess_lib "${WP17R2_TESSERACT_DLL}")
        endif()
    else()
        find_library(WP17R2_TESSERACT_SO NAMES tesseract libtesseract
                     HINTS "${WP17R2_TESSERACT_ROOT}/lib")
        if(WP17R2_TESSERACT_SO)
            set(_tess_lib "${WP17R2_TESSERACT_SO}")
        endif()
    endif()

    if(_tess_lib)
        target_compile_definitions(wp17r2_ocr PRIVATE WP17R2_WITH_TESSERACT=1)
        target_link_libraries(wp17r2_ocr PRIVATE "${_tess_lib}")
        message(STATUS "tesseract backend enabled: ${_tess_lib}")
    else()
        message(WARNING
            "Tesseract library not found - building ncnn backend only. "
            "Set -DWP17R2_TESSERACT_LIB=<path> or -DWP17R2_TESSERACT_ROOT=<dir>.")
    endif()
endif()

# ------------------------------------------------------------------ platform
if(WIN32)
    target_link_libraries(wp17r2_ocr PRIVATE psapi)
endif()
if(ANDROID)
    target_link_libraries(wp17r2_ocr PRIVATE log)
endif()
if(UNIX AND NOT APPLE AND NOT ANDROID)
    find_package(Threads REQUIRED)
    target_link_libraries(wp17r2_ocr PRIVATE Threads::Threads)
endif()

install(TARGETS wp17r2_ocr RUNTIME DESTINATION bin)
