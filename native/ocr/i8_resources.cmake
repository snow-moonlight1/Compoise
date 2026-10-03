# Optional reviewed resources, shared by the two desktop bundle installers.
# Ordinary builds do not find Python, ncnn, or any models.
if(DEFINED ENV{WP17_OCR_MODELS_DIR} AND NOT "$ENV{WP17_OCR_MODELS_DIR}" STREQUAL "")
  if(NOT TARGET matrixflow_ocr)
    message(FATAL_ERROR "Official OCR resources require the native OCR target")
  endif()
  set(WP17_I8_MODELS "$ENV{WP17_OCR_MODELS_DIR}")
  if(DEFINED ENV{WP17_OCR_PYTHON})
    set(WP17_I8_PYTHON "$ENV{WP17_OCR_PYTHON}")
  else()
    find_program(WP17_I8_PYTHON NAMES python3 python REQUIRED)
  endif()
  execute_process(COMMAND "${WP17_I8_PYTHON}"
    "${CMAKE_CURRENT_LIST_DIR}/tools/i8_assets.py" --bundle "${WP17_I8_MODELS}"
    RESULT_VARIABLE WP17_I8_ASSET_RESULT)
  if(NOT WP17_I8_ASSET_RESULT EQUAL 0)
    message(FATAL_ERROR "Official OCR resources/licences failed verification")
  endif()
endif()
