#!/usr/bin/env python3
"""Generate opt-in allocator candidates outside the checkout; never edit defaults.

All candidates preserve model/options/CTC/C ABI. The bounded cache clears after
each complete image, including exception unwinding; live tensors are not capped.
"""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import shutil

from q1_benchmark import REPO


def generate(source: Path, out: Path, strategy: str, cache_mib: int = 4):
    out = out.resolve()
    if out == REPO or REPO in out.parents:
        raise ValueError("external output required")
    # Avoid silently replacing evidence or another package's directory.
    out.mkdir(parents=True, exist_ok=False)
    original = source.read_text(encoding="utf-8")
    text = original

    def replace(needle, replacement):
        nonlocal text
        if text.count(needle) != 1:
            raise ValueError(f"expected exactly one source anchor: {needle}")
        text = text.replace(needle, replacement)

    if strategy in ("rec-bounded", "all-bounded"):
        replace('#include "net.h"', '#include "net.h"\n#include "p2_bounded_allocator.h"')
        replace("        std::vector<TextLine> boxes;",
                "        P2ReleaseScratch release{scratch_};\n        std::vector<TextLine> boxes;")
        # Declare BEFORE both Nets: reverse destruction keeps allocator alive
        # through Net teardown. Extractor overrides avoid model-load allocations.
        replace("    ncnn::Net det_;",
                f"    P2BoundedAllocator scratch_{{{cache_mib}u * 1024u * 1024u}};\n    ncnn::Net det_;")
        for net in (["rec_"] if strategy == "rec-bounded" else ["det_", "rec_"]):
            needle = f"        ncnn::Extractor ex = {net}.create_extractor();"
            replace(needle, needle + "\n        ex.set_blob_allocator(&scratch_);"
                    "\n        ex.set_workspace_allocator(&scratch_);")
    elif strategy == "q1-pool":
        # The previous rejected experiment, preserved as an explicit comparator.
        replace("explicit NcnnPpOcrv5(const OcrOptions& opt) : opt_(opt) {}", """explicit NcnnPpOcrv5(const OcrOptions& opt) : opt_(opt)
    {
        scratch_blobs_.set_size_compare_ratio(.75f);
        scratch_workspace_.set_size_compare_ratio(.75f);
        scratch_blobs_.set_size_drop_threshold(2);
        scratch_workspace_.set_size_drop_threshold(2);
    }""")
        replace("        rec_.opt.use_local_pool_allocator = false;", """        rec_.opt.use_local_pool_allocator = false;
        det_.opt.blob_allocator = rec_.opt.blob_allocator = &scratch_blobs_;
        det_.opt.workspace_allocator = rec_.opt.workspace_allocator = &scratch_workspace_;""")
        replace("        std::vector<TextLine> boxes;", """        struct ReleaseScratch
        {
            ncnn::PoolAllocator& blobs;
            ncnn::PoolAllocator& workspace;
            ~ReleaseScratch() { blobs.clear(); workspace.clear(); }
        } release{scratch_blobs_, scratch_workspace_};
        std::vector<TextLine> boxes;""")
        replace("    ncnn::Net det_;", "    ncnn::PoolAllocator scratch_blobs_;\n"
                "    ncnn::PoolAllocator scratch_workspace_;\n    ncnn::Net det_;")
    elif strategy != "q1":
        raise ValueError(f"unknown strategy: {strategy}")
    (out / "ocr_runtime.cpp").write_text(text, encoding="utf-8")
    for name in ("CMakeLists.txt", "ocr_runtime.h", "smoke.cpp"):
        shutil.copyfile(source.parent / name, out / name)
    for name in ("p2_allocator_test.cpp", "p2_bounded_allocator.h"):
        shutil.copyfile(Path(__file__).with_name(name), out / name)
    with (out / "CMakeLists.txt").open("a", encoding="utf-8") as cmake:
        cmake.write('''
# P2 private experiment only; no production build entry is modified.
find_package(Threads REQUIRED)
add_executable(p2_allocator_test p2_allocator_test.cpp)
target_compile_features(p2_allocator_test PRIVATE cxx_std_17)
target_link_libraries(p2_allocator_test PRIVATE ncnn Threads::Threads)
''')
    manifest = {"strategy": strategy, "cache_mib": cache_mib,
                "source_sha256": hashlib.sha256(original.encode()).hexdigest(),
                "candidate_sha256": hashlib.sha256(text.encode()).hexdigest(),
                "allocator_sha256": hashlib.sha256((out / "p2_bounded_allocator.h").read_bytes()).hexdigest(),
                "experimental": True, "production_default_changed": False}
    (out / "p2-manifest.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    return manifest


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, default=REPO / "native/ocr/ocr_runtime.cpp")
    parser.add_argument("--out", type=Path, required=True)
    parser.add_argument("--strategy", choices=("q1", "rec-bounded", "all-bounded", "q1-pool"), required=True)
    parser.add_argument("--cache-mib", type=int, choices=range(1, 17), default=4)
    args = parser.parse_args()
    print(json.dumps(generate(args.source, args.out, args.strategy, args.cache_mib)))


if __name__ == "__main__":
    main()
