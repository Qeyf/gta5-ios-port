#pragma once
#include <cstddef>
#include <cstdint>
#include <vector>

// Renderer-thread queue. Retry recipes missing an engine vertex signature only
// after that signature set changes; never rescan a waiting list every idle gap.
class PGPipelineWarmupQueue {
    std::vector<size_t> current, later;
    size_t position=0;
    uint64_t passGeneration=0;
    bool started=false;
public:
    void reset(size_t count) {
        stop();
        current.reserve(count);
        for(size_t i=0;i<count;i++)current.push_back(i);
    }
    bool next(uint64_t generation, size_t &index) {
        if(!started) {passGeneration=generation;started=true;}
        if(position==current.size()) {
            if(later.empty() || passGeneration==generation)return false;
            current.swap(later);later.clear();position=0;passGeneration=generation;
        }
        index=current[position++];
        return true;
    }
    void defer(size_t index) {later.push_back(index);}
    void stop() {current.clear();later.clear();position=0;started=false;}
};
