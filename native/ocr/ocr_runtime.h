#pragma once

#ifdef _WIN32
#define MF_OCR_EXPORT __declspec(dllexport)
#else
#define MF_OCR_EXPORT __attribute__((visibility("default")))
#endif

#ifdef __cplusplus
extern "C" {
#endif

// Asset root contains ncnn/PP_OCRv5_mobile_{det,rec}.ncnn.{param,bin}
// and ncnn/ppocrv5_dict.txt. The caller owns the returned session.
MF_OCR_EXPORT void* mf_ocr_create(const char* assets, int threads);
// Returns a malloc-owned UTF-8 JSON result; every invocation must be freed.
MF_OCR_EXPORT char* mf_ocr_run_file(void* session, const char* image_path);
MF_OCR_EXPORT void mf_ocr_destroy(void* session);
MF_OCR_EXPORT void mf_ocr_free(char* result);

#ifdef __cplusplus
}
#endif
