#include "ocr_runtime.h"

#include <cstdio>
#include <cstring>

int main(int argc, char** argv)
{
    if (argc != 3)
    {
        fprintf(stderr, "usage: matrixflow_ocr_smoke <assets root> <image.png>\n");
        return 2;
    }
    void* session = mf_ocr_create(argv[1], 4);
    char* result = mf_ocr_run_file(session, argv[2]);
    if (!result)
    {
        mf_ocr_destroy(session);
        return 3;
    }
    puts(result);
    const bool ok = strstr(result, "\"error\":\"\"") != nullptr &&
                    strstr(result, "\"text\":") != nullptr;
    mf_ocr_free(result);
    mf_ocr_destroy(session);
    return ok ? 0 : 4;
}
