#include <cassert>
#include <cstdio>
#include <memory>
#include <vector>

#if __has_include("NativeFrameUploadCache.h")
#include "NativeFrameUploadCache.h"

int main() {
    std::vector<std::shared_ptr<unsigned>> chunks;
    for (unsigned i = 0; i < 8; ++i) chunks.push_back(std::make_shared<unsigned>(i));
    std::weak_ptr<unsigned> used = chunks[0], spare = chunks[1], excess = chunks[7];
    auto commandBufferOwner = chunks[6];

    // The entire allocation must remain alive until the GPU serial completes.
    assert(!pg_trim_completed_upload_chunks(chunks, 1, 42, 41));
    assert(chunks.size() == 8 && !excess.expired());
    assert(pg_trim_completed_upload_chunks(chunks, 1, 42, 42));
    assert(chunks.size() == 2 && !used.expired() && !spare.expired() && excess.expired());
    // Other references, such as a retained Metal command buffer or a constant
    // buffer binding, keep their resource alive when the ring relinquishes it.
    assert(commandBufferOwner && *commandBufferOwner == 6);

    // Keep one spare for an empty completed frame and never grow while trimming.
    assert(pg_trim_completed_upload_chunks(chunks, 0, 42, 100));
    assert(chunks.size() == 1 && !used.expired() && spare.expired());
    assert(pg_trim_completed_upload_chunks(chunks, 1000, 42, 100));
    assert(chunks.size() == 1);
    chunks.clear();
    assert(pg_trim_completed_upload_chunks(chunks, 0, 0, 0) && chunks.empty());
    puts("PASS: live upload chunks stay retained; completed idle chunks trim with one spare and shared owners intact.");
}
#else
int main() {
    fputs("FAIL: completed upload frames cannot trim their retained peak allocation.\n", stderr);
    return 1;
}
#endif
