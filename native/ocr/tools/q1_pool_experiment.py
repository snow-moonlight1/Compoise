#!/usr/bin/env python3
"""Opt-in alternate scratch pools in external source; never edits the runtime.

Compare this uninstrumented candidate with the same SDK/config/input. The
runtime must already disable Net-owned pools. Failed candidates remain evidence.
"""
import argparse
from pathlib import Path
import shutil

from q1_benchmark import REPO


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--source", required=True, type=Path)
    p.add_argument("--out", required=True, type=Path)
    a = p.parse_args()
    if a.out.resolve() == REPO or REPO in a.out.resolve().parents: p.error("external output required")
    a.out.mkdir(parents=True, exist_ok=True)
    source = a.source.read_text(encoding="utf-8")
    changes = {
        "explicit NcnnPpOcrv5(const OcrOptions& opt) : opt_(opt) {}": """explicit NcnnPpOcrv5(const OcrOptions& opt) : opt_(opt)
    {
        scratch_blobs_.set_size_compare_ratio(.75f);
        scratch_workspace_.set_size_compare_ratio(.75f);
        scratch_blobs_.set_size_drop_threshold(2);
        scratch_workspace_.set_size_drop_threshold(2);
    }""",
        "        rec_.opt.use_local_pool_allocator = false;": """        rec_.opt.use_local_pool_allocator = false;
        det_.opt.blob_allocator = rec_.opt.blob_allocator = &scratch_blobs_;
        det_.opt.workspace_allocator = rec_.opt.workspace_allocator = &scratch_workspace_;""",
        "        std::vector<TextLine> boxes;": """        struct ReleaseScratch
        {
            ncnn::PoolAllocator& blobs;
            ncnn::PoolAllocator& workspace;
            ~ReleaseScratch() { blobs.clear(); workspace.clear(); }
        } release{scratch_blobs_, scratch_workspace_};
        std::vector<TextLine> boxes;""",
        "    ncnn::Net det_;": """    ncnn::PoolAllocator scratch_blobs_;
    ncnn::PoolAllocator scratch_workspace_;
    ncnn::Net det_;""",
    }
    for needle, replacement in changes.items():
        assert source.count(needle) == 1, needle
        source = source.replace(needle, replacement)
    (a.out / "ocr_runtime.cpp").write_text(source, encoding="utf-8")
    for name in ("CMakeLists.txt", "ocr_runtime.h", "smoke.cpp"):
        shutil.copyfile(a.source.parent / name, a.out / name)
    print(a.out)


if __name__ == "__main__":
    main()
