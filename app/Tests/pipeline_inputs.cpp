#include "NativePipelineInputs.h"
#include <array>
#include <cassert>
#include <cstdio>

int main() {
    PGPipelineInputIds inputs;
    const std::array<uint32_t,7> layout={17,0,16,0,0,0,0};
    const uint64_t original=inputs.intern(layout.data(),layout.size());
    for(unsigned object=0;object<20000;object++) {
        const auto recreated=layout;
        assert(inputs.intern(recreated.data(),recreated.size())==original &&
               "Equal input descriptions must reuse a pipeline identity across recreated engine objects.");
    }
    assert(inputs.size()==1);
    for(size_t field=0;field<layout.size();field++) {
        auto changed=layout;changed[field]++;
        assert(inputs.intern(changed.data(),changed.size())!=original);
    }
    const std::array<uint32_t,4> signature={17,0,0,15},remapped={17,0,1,15};
    assert(inputs.intern(signature.data(),signature.size())!=inputs.intern(remapped.data(),remapped.size()));
    assert(inputs.intern(signature.data(),signature.size())==inputs.intern(signature.data(),signature.size()));
    // Empty and prefix descriptions must remain distinct; object addresses and
    // hash collisions cannot stand in for the descriptor's actual contents.
    assert(inputs.intern(nullptr,0)!=inputs.intern(layout.data(),1));
    assert(inputs.intern(layout.data(),1)!=inputs.intern(layout.data(),2));
    assert(inputs.intern(nullptr,0)==inputs.intern(nullptr,0));
    puts("PASS: exact pipeline input reuse across 20000 recreated objects, every layout field, signature remaps, lengths and empty inputs.");
}
