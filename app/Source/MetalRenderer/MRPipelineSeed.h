#pragma once
#include "MRInternal.h"

namespace mr {
// Only immutable pipeline inputs. Vertex semantic/register signatures must be
// captured from CREATE_SHADER, never inferred from element order or this file.
struct PipelineSeed {
    std::string vs,ps;
    std::vector<LayoutEl> elements;
    std::vector<uint32_t> strides,blend;
    std::vector<MTLPixelFormat> colors;
    MTLPixelFormat depth=MTLPixelFormatInvalid;
    uint32_t samples=1,readOnly=0,topology=4;
};
std::vector<PipelineSeed> parsePipelineSeeds(NSData *data);
std::vector<PipelineSeed> loadPipelineSeeds();
}
