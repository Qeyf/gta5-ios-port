#pragma once
#include <cstddef>
#include <cstdint>
#include <map>
#include <utility>
#include <vector>

// Renderer-thread owned. Metal pipeline input descriptions are immutable:
// compare exact contents once at object creation, never an engine object ID.
// std::map equality keeps different descriptions separate without hash aliases.
class PGPipelineInputIds {
    std::map<std::vector<uint32_t>,uint64_t> descriptions;
public:
    uint64_t intern(const uint32_t *words,size_t count) {
        std::vector<uint32_t> key;
        if(count)key.assign(words,words+count);
        return descriptions.try_emplace(std::move(key),descriptions.size()+1).first->second;
    }
    size_t size() const {return descriptions.size();}
};
