#include "MRPipelineSeed.h"
#include <algorithm>

namespace mr {

static bool seedWords(id value, std::vector<uint32_t> &out, size_t count) {
    if(![value isKindOfClass:NSArray.class] || [value count]!=count)return false;
    for(id n in value) {
        if(![n isKindOfClass:NSNumber.class] || [n doubleValue]<0 || [n doubleValue]>UINT32_MAX || [n doubleValue]!=[n unsignedIntValue])return false;
        out.push_back([n unsignedIntValue]);
    }
    return true;
}
static bool seedHash(id value, bool optional=false) {
    if(![value isKindOfClass:NSString.class])return false;
    NSString *s=value;
    if(optional && !s.length)return true;
    if(s.length!=16)return false;
    for(NSUInteger i=0;i<s.length;i++) {
        unichar c=[s characterAtIndex:i];
        if(!((c>='0' && c<='9') || (c>='a' && c<='f')))return false;
    }
    return true;
}
static MTLPixelFormat seedFormat(id value) {
    if(value==NSNull.null)return MTLPixelFormatInvalid;
    static NSDictionary<NSString *,NSNumber *> *formats=@{
        @"bgra8unorm":@(MTLPixelFormatBGRA8Unorm), @"bgra8unorm-srgb":@(MTLPixelFormatBGRA8Unorm_sRGB),
        @"rgba8unorm":@(MTLPixelFormatRGBA8Unorm), @"rgba8unorm-srgb":@(MTLPixelFormatRGBA8Unorm_sRGB),
        @"rgba16float":@(MTLPixelFormatRGBA16Float), @"rgba32float":@(MTLPixelFormatRGBA32Float),
        @"rg11b10ufloat":@(MTLPixelFormatRG11B10Float), @"r32float":@(MTLPixelFormatR32Float),
        @"rg16float":@(MTLPixelFormatRG16Float), @"rg32float":@(MTLPixelFormatRG32Float), @"r8unorm":@(MTLPixelFormatR8Unorm),
        @"depth16unorm":@(MTLPixelFormatDepth16Unorm), @"depth32float":@(MTLPixelFormatDepth32Float),
        @"depth32float-stencil8":@(MTLPixelFormatDepth32Float_Stencil8)
    };
    return [value isKindOfClass:NSString.class] ? (MTLPixelFormat)[formats[value] unsignedIntegerValue] : MTLPixelFormatInvalid;
}

std::vector<PipelineSeed> parsePipelineSeeds(NSData *data) {
    if(!data || data.length>4*1024*1024)return {};
    id document=[NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    if(![document isKindOfClass:NSDictionary.class] || ![document[@"version"] isEqual:@1])return {};
    id recipes=document[@"recipes"];
    if(![recipes isKindOfClass:NSArray.class] || [recipes count]>2000)return {};
    std::vector<PipelineSeed> out;
    for(id rc in recipes) {
        if(![rc isKindOfClass:NSDictionary.class] || !seedHash(rc[@"vs"]) || !seedHash(rc[@"ps"],true))continue;
        PipelineSeed s;
        s.vs=[rc[@"vs"] UTF8String];s.ps=[rc[@"ps"] UTF8String];
        id els=rc[@"el"],colors=rc[@"rt"];
        if(![els isKindOfClass:NSArray.class] || [els count]>32 || ![colors isKindOfClass:NSArray.class] || [colors count]>8)continue;
        bool valid=true;
        uint32_t slots=0;
        size_t slotCount=0;
        for(id element in els) {
            std::vector<uint32_t> w;
            if(!seedWords(element,w,7) || w[3]>=16 || w[5]>1 || vertexFormat(w[2],nullptr)==MTLVertexFormatInvalid) {valid=false;break;}
            if(w[4]>UINT32_MAX-16-3) {valid=false;break;} // Attribute extent + constant-step alignment must not wrap.
            s.elements.push_back({w[0],w[1],w[2],w[3],w[4],w[5],w[6]});
            if(!(slots&(1u<<w[3]))) {slots|=1u<<w[3];slotCount++;}
        }
        if(!valid || !seedWords(rc[@"st"],s.strides,slotCount))continue;
        id blend=rc[@"b"];
        if(blend!=NSNull.null && !seedWords(blend,s.blend,66))continue;
        for(id color in colors) {
            auto format=seedFormat(color);
            if(color!=NSNull.null && (format==MTLPixelFormatInvalid || isDepthFormat(format))) {valid=false;break;}
            s.colors.push_back(format);
        }
        while(!s.colors.empty() && s.colors.back()==MTLPixelFormatInvalid)s.colors.pop_back();
        s.depth=seedFormat(rc[@"ds"]);
        if(![rc[@"ds"] isEqual:@""] && (!isDepthFormat(s.depth) || s.depth==MTLPixelFormatInvalid))valid=false;
        std::vector<uint32_t> numbers;
        if(!seedWords(@[rc[@"n"] ?: NSNull.null,rc[@"ro"] ?: NSNull.null,rc[@"tp"] ?: NSNull.null],numbers,3))continue;
        s.samples=numbers[0];s.readOnly=numbers[1];s.topology=numbers[2];
        if(!valid || (s.samples!=1 && s.samples!=2 && s.samples!=4 && s.samples!=8) || s.readOnly>3 ||
           (s.topology!=1 && s.topology!=2 && s.topology!=4) || (s.colors.empty() && !s.depth))continue;
        out.push_back(std::move(s));
    }
    return out;
}

std::vector<PipelineSeed> loadPipelineSeeds() {
    NSURL *url=[NSBundle.mainBundle URLForResource:@"pipeline-seed" withExtension:@"json"];
    auto out=parsePipelineSeeds(url ? [NSData dataWithContentsOfURL:url] : nil);
    logf("Metal renderer: %zu validated startup pipeline recipes; engine signatures required.",out.size());
    return out;
}
}
