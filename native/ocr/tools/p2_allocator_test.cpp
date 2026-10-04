// Explicit private experiment target; does not open a device or load a model.
#include "p2_bounded_allocator.h"
#include <atomic>
#include <cstdint>
#include <cstring>
#include <iostream>
#include <stdexcept>
#include <thread>
#include <vector>

static void require(bool value)
{
    if (!value) throw std::runtime_error("P2 allocator invariant failed");
}

int main()
{
    constexpr size_t cap = 64 * 1024;
    P2BoundedAllocator pool(cap);
    require(!pool.fastMalloc(std::numeric_limits<size_t>::max()));
    pool.fastFree(nullptr);
    void* first = pool.fastMalloc(4096);
    require(first && reinterpret_cast<uintptr_t>(first) % NCNN_MALLOC_ALIGN == 0);
    // ncnn kernels may overread this padding even at the logical end.
    memset(first, 0x5a, 4096 + NCNN_MALLOC_OVERREAD);
    pool.fastFree(first);
    require(pool.cached_bytes() > 4096 && pool.cached_bytes() <= cap);
    void* reused = pool.fastMalloc(3072);
    require(reused == first);
    pool.clear(); // must leave live allocations intact
    require(pool.cached_bytes() == 0 && static_cast<unsigned char*>(reused)[3071] == 0x5a);
    pool.fastFree(reused);
    void* huge = pool.fastMalloc(cap * 2);
    require(huge);
    pool.fastFree(huge);
    require(pool.cached_bytes() <= cap);
    try
    {
        P2ReleaseScratch release{pool};
        throw std::runtime_error("simulated caller exception");
    }
    catch (const std::runtime_error&) {}
    require(pool.cached_bytes() == 0);

    std::atomic<bool> failed{false};
    std::vector<std::thread> workers;
    for (int worker = 0; worker < 8; ++worker)
        workers.emplace_back([&, worker] {
            try
            {
                for (int iteration = 0; iteration < 3000; ++iteration)
                {
                    size_t bytes = 128 + (iteration * 97u + worker * 37u) % 8192;
                    auto* pointer = static_cast<unsigned char*>(pool.fastMalloc(bytes));
                    require(pointer && reinterpret_cast<uintptr_t>(pointer) % NCNN_MALLOC_ALIGN == 0);
                    memset(pointer, worker + 1, bytes);
                    if (iteration % 17 == 0) pool.clear();
                    require(pointer[0] == worker + 1 && pointer[bytes - 1] == worker + 1);
                    pool.fastFree(pointer);
                    require(pool.cached_bytes() <= cap);
                }
            }
            catch (...) { failed = true; }
        });
    for (auto& worker : workers) worker.join();
    require(!failed);
    pool.clear();
    require(pool.cached_bytes() == 0);
    std::cout << "alignment/overread/cap/reuse/live-clear/unwind/8-thread: PASS\n";
}
