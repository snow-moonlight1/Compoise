// P2 opt-in experiment. This header is not included by the production runtime.
#pragma once

#include "allocator.h"
#include <cstddef>
#include <limits>
#include <mutex>

// Session-owned, CPU-only cache. Charged bytes include metadata and ncnn's
// overread padding (not platform malloc bookkeeping); live tensors are never
// capped or truncated.
// Destroy only after all extractors/Mats and their worker threads have ended.
class P2BoundedAllocator final : public ncnn::Allocator
{
public:
    explicit P2BoundedAllocator(size_t limit) : limit_(limit) {}
    ~P2BoundedAllocator() override { clear(); }
    P2BoundedAllocator(const P2BoundedAllocator&) = delete;
    P2BoundedAllocator& operator=(const P2BoundedAllocator&) = delete;

    void* fastMalloc(size_t size) override
    {
        if (size > std::numeric_limits<size_t>::max() - offset() - NCNN_MALLOC_OVERREAD)
            return nullptr;
        {
            std::lock_guard<std::mutex> lock(mutex_);
            Block** best = nullptr;
            for (Block** entry = &head_; *entry; entry = &(*entry)->next)
            {
                const size_t capacity = (*entry)->capacity;
                // At least 75% utilisation, without overflowing size * 4.
                if (capacity >= size && capacity - size <= size / 3 &&
                    (!best || capacity < (*best)->capacity))
                    best = entry;
            }
            if (best)
            {
                Block* block = *best;
                *best = block->next;
                cached_ -= charge(block->capacity);
                return reinterpret_cast<unsigned char*>(block) + offset();
            }
        }
        auto* block = static_cast<Block*>(ncnn::fastMalloc(offset() + size));
        if (!block)
            return nullptr;
        block->capacity = size;
        block->next = nullptr;
        return reinterpret_cast<unsigned char*>(block) + offset();
    }

    void fastFree(void* pointer) override
    {
        if (!pointer)
            return;
        auto* block = reinterpret_cast<Block*>(static_cast<unsigned char*>(pointer) - offset());
        const size_t bytes = charge(block->capacity);
        {
            std::lock_guard<std::mutex> lock(mutex_);
            if (bytes <= limit_ - cached_)
            {
                block->next = head_;
                head_ = block;
                cached_ += bytes;
                return;
            }
        }
        ncnn::fastFree(block);
    }

    // Only free dead buffers. Live buffers are never in this list; clear is
    // safe during allocation/free, but is not a barrier for caller lifetimes.
    void clear()
    {
        Block* released;
        {
            std::lock_guard<std::mutex> lock(mutex_);
            released = head_;
            head_ = nullptr;
            cached_ = 0;
        }
        while (released)
        {
            Block* next = released->next;
            ncnn::fastFree(released);
            released = next;
        }
    }

    size_t cached_bytes() const
    {
        std::lock_guard<std::mutex> lock(mutex_);
        return cached_;
    }

private:
    struct Block { size_t capacity; Block* next; };
    static constexpr size_t offset()
    {
        return (sizeof(Block) + NCNN_MALLOC_ALIGN - 1) / NCNN_MALLOC_ALIGN * NCNN_MALLOC_ALIGN;
    }
    static constexpr size_t charge(size_t size) { return offset() + size + NCNN_MALLOC_OVERREAD; }
    const size_t limit_;
    mutable std::mutex mutex_;
    Block* head_ = nullptr;
    size_t cached_ = 0;
};

struct P2ReleaseScratch
{
    P2BoundedAllocator& allocator;
    ~P2ReleaseScratch() { allocator.clear(); }
};
