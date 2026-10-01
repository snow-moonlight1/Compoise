// WP17-I1/I4 smoke caller for the C ABI.
//
// usage: matrixflow_ocr_smoke <assets root> <image.png> [more.png ...]
//
// One line of raw JSON per image, then a machine-readable summary line that
// records how many images succeeded, the wall time and the peak RSS of this
// process. The summary is only emitted by this tool: the shipped C ABI result
// is unchanged, so the measured numbers never depend on test-only fields.
#include "ocr_runtime.h"

#include <chrono>
#include <cstdio>
#include <cstring>
#include <string>

#ifdef _WIN32
#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <windows.h>
#include <psapi.h>
#else
#include <cstdlib>
#endif

static double now_ms()
{
    using clock = std::chrono::steady_clock;
    return std::chrono::duration<double, std::milli>(clock::now().time_since_epoch()).count();
}

static unsigned long long peak_rss_kb()
{
#ifdef _WIN32
    PROCESS_MEMORY_COUNTERS pmc;
    if (GetProcessMemoryInfo(GetCurrentProcess(), &pmc, sizeof(pmc)))
        return (unsigned long long)(pmc.PeakWorkingSetSize / 1024ull);
    return 0;
#else
    FILE* fp = fopen("/proc/self/status", "r");
    if (!fp)
        return 0;
    char line[256];
    unsigned long long hwm = 0;
    while (fgets(line, sizeof(line), fp))
    {
        if (strncmp(line, "VmHWM:", 6) == 0)
        {
            sscanf(line + 6, "%llu", &hwm);
            break;
        }
    }
    fclose(fp);
    return hwm;
#endif
}

int main(int argc, char** argv)
{
    if (argc < 3)
    {
        fprintf(stderr, "usage: matrixflow_ocr_smoke <assets root> <image.png> [more.png ...]\n");
        return 2;
    }

    void* session = mf_ocr_create(argv[1], 4);
    if (!session)
    {
        fprintf(stderr, "mf_ocr_create returned null\n");
        return 3;
    }

    const int count = argc - 2;
    int succeeded = 0;
    const double start = now_ms();
    for (int i = 0; i < count; i++)
    {
        char* result = mf_ocr_run_file(session, argv[2 + i]);
        if (!result)
        {
            printf("{\"path\":\"%s\",\"error\":\"native result allocation failed\"}\n", argv[2 + i]);
            continue;
        }
        puts(result);
        if (strstr(result, "\"error\":\"\"") != nullptr && strstr(result, "\"text\":") != nullptr)
            succeeded++;
        mf_ocr_free(result);
    }
    const double elapsed = now_ms() - start;
    const unsigned long long peak = peak_rss_kb();
    mf_ocr_destroy(session);

    printf("{\"summary\":{\"images\":%d,\"succeeded\":%d,\"elapsed_ms\":%.1f,\"peak_rss_kb\":%llu}}\n",
           count, succeeded, elapsed, peak);
    return succeeded == count ? 0 : 4;
}
