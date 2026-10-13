// Minimal Tesseract 5 C API surface used by the WP17-R2 harness.
//
// The declarations below are copied from tesseract-ocr/tesseract
// `include/tesseract/capi.h` (Apache-2.0) - see core/README.md for the pinned
// upstream commit.  We re-declare instead of including the header because the
// Windows binary distribution used here (UB Mannheim 5.4.0.20240606) ships
// `libtesseract-5.dll` but no headers or import library, and re-declaring keeps
// the identical call sites working on Linux and (potentially) Android.
//
// Enum values must stay in sync with tesseract's public headers.
#ifndef WP17R2_TESS_C_API_H
#define WP17R2_TESS_C_API_H

#ifdef __cplusplus
extern "C" {
#endif

typedef struct TessBaseAPI TessBaseAPI;
typedef struct TessPageIterator TessPageIterator;
typedef struct TessResultIterator TessResultIterator;

typedef enum TessPageIteratorLevel
{
    RIL_BLOCK = 0,
    RIL_PARA = 1,
    RIL_TEXTLINE = 2,
    RIL_WORD = 3,
    RIL_SYMBOL = 4
} TessPageIteratorLevel;

typedef enum TessPageSegMode
{
    PSM_OSD_ONLY = 0,
    PSM_AUTO_OSD = 1,
    PSM_AUTO_ONLY = 2,
    PSM_AUTO = 3,
    PSM_SINGLE_COLUMN = 4,
    PSM_SINGLE_BLOCK_VERT_TEXT = 5,
    PSM_SINGLE_BLOCK = 6,
    PSM_SINGLE_LINE = 7,
    PSM_SINGLE_WORD = 8,
    PSM_CIRCLE_WORD = 9,
    PSM_SINGLE_CHAR = 10,
    PSM_SPARSE_TEXT = 11,
    PSM_SPARSE_TEXT_OSD = 12,
    PSM_RAW_LINE = 13,
    PSM_COUNT = 14
} TessPageSegMode;

const char* TessVersion(void);
void TessDeleteText(char* text);
TessBaseAPI* TessBaseAPICreate(void);
void TessBaseAPIDelete(TessBaseAPI* handle);
int TessBaseAPIInit3(TessBaseAPI* handle, const char* datapath, const char* language);
int TessBaseAPISetVariable(TessBaseAPI* handle, const char* name, const char* value);
void TessBaseAPISetPageSegMode(TessBaseAPI* handle, TessPageSegMode mode);
void TessBaseAPISetImage(TessBaseAPI* handle, const unsigned char* imagedata, int width, int height,
                         int bytes_per_pixel, int bytes_per_line);
int TessBaseAPIRecognize(TessBaseAPI* handle, void* monitor);
TessResultIterator* TessBaseAPIGetIterator(TessBaseAPI* handle);
int TessPageIteratorBoundingBox(const TessPageIterator* handle, TessPageIteratorLevel level, int* left,
                                int* top, int* right, int* bottom);
void TessResultIteratorDelete(TessResultIterator* handle);
int TessResultIteratorNext(TessResultIterator* handle, TessPageIteratorLevel level);
char* TessResultIteratorGetUTF8Text(const TessResultIterator* handle, TessPageIteratorLevel level);
float TessResultIteratorConfidence(const TessResultIterator* handle, TessPageIteratorLevel level);

#ifdef __cplusplus
}
#endif

#endif // WP17R2_TESS_C_API_H
