#pragma once
#include <cstddef>
#include <cstdint>

// Trimming relinquishes only the ring's ownership. Encoded commands and
// buffer bindings may retain their own references until those uses finish.
template<class Chunks>
bool pg_trim_completed_upload_chunks(Chunks &chunks, std::size_t used,
                                     uint64_t lastSerial, uint64_t completedSerial) {
    if (lastSerial > completedSerial) return false;
    const std::size_t keep = used < chunks.size() ? used + 1 : chunks.size();
    if (chunks.size() > keep) chunks.resize(keep);
    return true;
}
