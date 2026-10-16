#pragma once
#include <algorithm>
#include <cmath>
#include <limits>

// Test-only comparison; this does not transform production texture pixels.
struct BCSampleError {
    double difference,tolerance;
    bool matches() const {return std::isfinite(difference) && difference<=tolerance;}
};

// Apple's documented linear -> sRGB transfer. The established 2.1/255 error
// budget describes decoded UNorm code values, not linear light after transfer.
// https://developer.apple.com/library/archive/documentation/Miscellaneous/Conceptual/MetalProgrammingGuide/Mem-Obj/Mem-Obj.html
inline double bcLinearToSrgb(double value) {
    return value<=0.0031308 ? value*12.92 : 1.055*std::pow(value,1.0/2.4)-0.055;
}

inline BCSampleError compareBCSample(double actual,double expected,int kind,unsigned channel,bool srgb) {
    if(!std::isfinite(actual) || !std::isfinite(expected))return {std::numeric_limits<double>::infinity(),0};
    if(srgb && channel<3) {actual=bcLinearToSrgb(actual);expected=bcLinearToSrgb(expected);}
    return {std::abs(actual-expected),kind==6 ? std::max(0.002,std::abs(expected)*0.01) : 2.1/255};
}
