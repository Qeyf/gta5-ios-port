#include "BCSampleComparison.h"
#include <cassert>
#include <cstdio>
#include <limits>

static double toLinear(double s) {
    return s<=0.04045 ? s/12.92 : std::pow((s+0.055)/1.055,2.4);
}

int main() {
    // Exact regression values from the 2026-10-16 Apple GPU failure. They are
    // approximately sRGB bytes 188 and186, inside the existing 2.1-code budget.
    auto observed=compareBCSample(0.502808332,0.491086692,1,0,true);
    assert(observed.matches());
    assert(observed.difference*255>1.9 && observed.difference*255<2.1);
    assert(!compareBCSample(0.502808332,0.491086692,1,0,false).matches());

    for(int kind:{1,2,3,7})for(unsigned channel=0;channel<3;channel++) {
        for(int code=0;code<=253;code++) {
            assert(compareBCSample(toLinear(code/255.0),toLinear((code+2)/255.0),kind,channel,true).matches());
            if(code<=252)assert(!compareBCSample(toLinear(code/255.0),toLinear((code+3)/255.0),kind,channel,true).matches());
        }
    }
    // Alpha is linear even on an sRGB view: never apply the RGB transfer to it.
    assert(compareBCSample(0.01,0.015,1,3,true).matches());
    assert(!compareBCSample(0.0,3.0/255,1,3,true).matches());
    assert(compareBCSample(0.0,2.0/255,1,0,false).matches());
    assert(!compareBCSample(0.0,3.0/255,1,0,false).matches());

    // A missing gamma conversion or wrong color is still a failure.
    assert(!compareBCSample(0.5,toLinear(0.5),1,0,true).matches());
    assert(!compareBCSample(1,0,1,0,true).matches());
    for(double invalid:{std::numeric_limits<double>::infinity(),-std::numeric_limits<double>::infinity(),std::numeric_limits<double>::quiet_NaN()}) {
        assert(!compareBCSample(invalid,0.5,1,0,true).matches());
        assert(!compareBCSample(0.5,invalid,6,0,false).matches());
    }
    // Keep the previous BC6H HDR relative/near-zero policy.
    assert(compareBCSample(1000,1005,6,0,false).matches());
    assert(!compareBCSample(1000,1020,6,0,false).matches());
    assert(compareBCSample(0,0.0019,6,0,false).matches());
    assert(!compareBCSample(0,0.0021,6,0,false).matches());
    puts("PASS: reported BC1 sRGB values, complete 8-bit RGB range, linear alpha, real gamma/color errors, nonfinite samples and unchanged BC6H tolerance.");
}
