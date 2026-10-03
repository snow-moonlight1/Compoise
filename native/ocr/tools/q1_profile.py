#!/usr/bin/env python3
"""Copy a runtime to an external profiling source tree; production ABI unchanged.

The phase probes only emit numbers/stage names, never image paths or OCR text.
Use the same CMake/SDK/configuration for each copy. Timing includes probe cost;
use q1_benchmark.py's uninstrumented binaries for latency comparisons.
"""
import argparse
from pathlib import Path
import shutil

from q1_benchmark import REPO

HELPER = r'''
static void q1_phase(const char* phase, size_t payload = 0)
{
    unsigned long long rss = 0, hwm = 0;
#ifdef _WIN32
    PROCESS_MEMORY_COUNTERS pmc;
    if (GetProcessMemoryInfo(GetCurrentProcess(), &pmc, sizeof(pmc)))
    {
        rss = pmc.WorkingSetSize / 1024ull;
        hwm = pmc.PeakWorkingSetSize / 1024ull;
    }
#else
    FILE* fp = fopen("/proc/self/status", "r");
    if (fp)
    {
        char line[256];
        while (fgets(line, sizeof(line), fp))
        {
            if (strncmp(line, "VmRSS:", 6) == 0) sscanf(line + 6, "%llu", &rss);
            if (strncmp(line, "VmHWM:", 6) == 0) sscanf(line + 6, "%llu", &hwm);
        }
        fclose(fp);
    }
#endif
    fprintf(stderr, "Q1_STAGE {\"stage\":\"%s\",\"rss_kib\":%llu,\"hwm_kib\":%llu,\"payload\":%llu}\n",
        phase, rss, hwm, static_cast<unsigned long long>(payload));
}
'''


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--source", type=Path, required=True)
    p.add_argument("--out", type=Path, required=True)
    a = p.parse_args()
    target = a.out.resolve()
    if target == REPO or REPO in target.parents: p.error("external output required")
    target.mkdir(parents=True, exist_ok=True)
    source = a.source.read_text(encoding="utf-8")
    anchor = "static std::string json_escape"
    assert source.count(anchor) == 1
    source = source.replace(anchor, HELPER + "\n" + anchor)
    probes = {
        "        det_.opt.num_threads = opt_.threads;": "        q1_phase(\"dict-loaded\");\n",
        "        if (rec_.load_param(rec_param_.c_str())": "        q1_phase(\"det-model\");\n",
        "        return true;\n    }\n\n    bool run": "        q1_phase(\"rec-model\");\n",
        "    bm.w = w;": "    q1_phase(\"stb-rgb\", static_cast<size_t>(w) * h * 3);\n",
        "        out.det_ms = now_ms() - t0;": "        q1_phase(\"det-return\");\n",
        "        const float denorm_vals[1]": "        q1_phase(\"det-extracted\");\n",
        "        // outmat: (num_tokens)": "        q1_phase(\"rec-extracted-width\", target_w);\n",
        "        out.rec_ms = now_ms() - t0;": "        q1_phase(\"rec-return\");\n",
        "        return json_result(result);": "        q1_phase(\"bitmap-released\");\n",
        "    delete static_cast<RuntimeSession*>(opaque);": "    q1_phase(\"before-destroy\");\n",
    }
    for needle, probe in probes.items():
        assert source.count(needle) == 1, needle
        source = source.replace(needle, probe + needle)
    source = source.replace("    delete static_cast<RuntimeSession*>(opaque);",
                            "    delete static_cast<RuntimeSession*>(opaque);\n    q1_phase(\"destroyed\");")
    (target / "ocr_runtime.cpp").write_text(source, encoding="utf-8")
    for name in ("CMakeLists.txt", "ocr_runtime.h", "smoke.cpp"):
        shutil.copyfile(a.source.parent / name, target / name)
    print(target)


if __name__ == "__main__":
    main()
