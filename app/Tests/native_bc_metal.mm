// Real Metal integration test. Include the renderer so its production texture
// creation, upload, views, copies and readbacks run without an engine/game bundle.
#include "../Source/MetalRenderer/MRRenderer.mm"
#include <cassert>
#include <cstdlib>
#include <chrono>
#include <thread>
#include "BCSampleComparison.h"

// A drawable may be unavailable while previously encoded GPU work still runs.
@interface PGNoDrawableTestLayer : CAMetalLayer
@end
@implementation PGNoDrawableTestLayer
- (id<CAMetalDrawable>)nextDrawable { return nil; }
@end

extern "C" void pg_log(const char *line) { fprintf(stderr,"%s\n",line); }
extern "C" uint32_t PGGraphicsNotify(uint64_t) { return 0; }
extern "C" uint32_t PGGraphicsWait(uint64_t,uint32_t,int64_t) { return 0; }
namespace mr {
void frameReportsInstall(id<MTLDevice>) {}
void frameReportsRecord(double,double,uint64_t,bool,const FrameWork &) {}
}

static id<MTLComputePipelineState> samplingPipeline;
static id<MTLComputePipelineState> nearestSamplingPipeline;
static uint32_t nextTextureId = 1;

static void completeGPU() {
  if (!R->cmd) return;
  id<MTLCommandBuffer> buffer = R->cmd;
  uint64_t serial = R->serial;
  commit(CReadback);
  [buffer waitUntilCompleted];
  assert(buffer.status == MTLCommandBufferStatusCompleted);
  waitSerial(serial);
}

static Texture *makeTexture(uint32_t dxgi,uint32_t width,uint32_t height,uint32_t mips,uint32_t layers,bool native) {
  R->bcTextures = native;
  uint32_t words[] = {nextTextureId++,2,width,height,1,mips,layers,dxgi,8,1};
  createTexture(words);
  Texture *out = texture(words[0]);
  assert(out && out->tex);
  FormatInfo expected = mapFormat(dxgi,8,native && pg_bc_native_eligible(true,out->bcKind,2,width,height,mips,layers,1,8));
  assert(out->format == expected.format);
  assert(out->hardwareBC == (native && pg_bc_native_eligible(true,out->bcKind,2,width,height,mips,layers,1,8)));
  return out;
}

static std::vector<uint8_t> blocks(int kind,size_t count,uint32_t seed) {
  std::vector<uint8_t> out(count);
  for (size_t i = 0; i < count; i++) {
    seed ^= seed<<13; seed ^= seed>>17; seed ^= seed<<5;
    out[i] = (uint8_t)seed;
  }
  size_t blockBytes = bcBlockBytes(kind);
  for (size_t at = 0; at < count; at += blockBytes) {
    if (kind == 6) out[at] &= 0xfc;  // BC6H mode 0 is valid.
    if (kind == 7) out[at] = (out[at]&0x80)|0x40; // BC7 mode 6 is valid.
  }
  return out;
}

static void uploadPair(Texture *native,Texture *fallback,uint32_t mip,uint32_t seed,bool oddPitch) {
  uint32_t w,h,d; mipExtent(native,mip,w,h,d);
  PGBCUploadLayout tight;
  assert(pg_bc_upload_layout(native->bcKind,w,h,native->depthOrLayers,0,0,SIZE_MAX,&tight));
  std::vector<uint8_t> source = blocks(native->bcKind,tight.totalBytes,seed);
  uint32_t pitch = (uint32_t)tight.rowBytes+(oddPitch ? 3 : 16), rows = (uint32_t)tight.rows+2;
  size_t imageBytes = (size_t)pitch*rows;
  std::vector<uint8_t> padded(imageBytes*native->depthOrLayers,0xa5);
  for (uint32_t layer = 0; layer < native->depthOrLayers; layer++) for (size_t row = 0; row < tight.rows; row++)
    memcpy(padded.data()+layer*imageBytes+row*pitch,source.data()+layer*tight.imageBytes+row*tight.rowBytes,tight.rowBytes);
  for (Texture *t : {native,fallback})
    uploadTextureBytes(t,mip,0,0,0,0,w,h,t->depthOrLayers,pitch,rows,padded.data(),padded.size());
}

struct BCTextureSamples {
  id<MTLBuffer> values;
  bool srgb;
};

static BCTextureSamples sample(Texture *t,uint32_t mip,uint32_t layer,uint32_t dxgi = 0) {
  View srv(OSrv,0);
  srv.res = t->oid; srv.fmt = dxgi; srv.a = mip; srv.b = 1; srv.c = layer;
  ResBinding binding{}; binding.kind = RTexture; binding.dim = D2;
  id<MTLTexture> source = srvTexture(&srv,t,binding);
  assert(source);
  id<MTLBuffer> output = [R->device newBufferWithLength:source.width*source.height*16 options:MTLResourceStorageModeShared];
  assert(output);
  endEncoders();
  id<MTLComputeCommandEncoder> encoder = [commandBuffer() computeCommandEncoder];
  [encoder setComputePipelineState:samplingPipeline];
  [encoder setTexture:source atIndex:0];
  [encoder setBuffer:output offset:0 atIndex:0];
  [encoder dispatchThreads:MTLSizeMake(source.width,source.height,1) threadsPerThreadgroup:MTLSizeMake(8,8,1)];
  [encoder endEncoding];
  t->lastUse = R->serial;
  MTLPixelFormat format=source.pixelFormat;
  bool srgb=format==MTLPixelFormatBC1_RGBA_sRGB || format==MTLPixelFormatBC2_RGBA_sRGB ||
    format==MTLPixelFormatBC3_RGBA_sRGB || format==MTLPixelFormatBC7_RGBAUnorm_sRGB ||
    format==MTLPixelFormatRGBA8Unorm_sRGB || format==MTLPixelFormatBGRA8Unorm_sRGB;
  uint32_t requested=dxgi ? dxgi : t->dxgi;
  bool expectedSrgb=requested==72 || requested==75 || requested==78 || requested==99;
  assert(srgb==expectedSrgb && "Sampled BC SRV must honor the requested DXGI color space.");
  return {output,srgb};
}

static void compare(BCTextureSamples a,BCTextureSamples b,int kind,const char *stage = "unspecified") {
  completeGPU();
  assert(a.values.length == b.values.length);
  assert(a.srgb==b.srgb && "Native and fallback SRVs must expose the same color space.");
  const float *x = (const float *)a.values.contents, *y = (const float *)b.values.contents;
  for (size_t i = 0; i < a.values.length/sizeof(float); i++) {
    auto error=compareBCSample(x[i],y[i],kind,(unsigned)(i%4),a.srgb);
    if (!error.matches()) {
      const char *space=a.srgb && i%4<3 ? "sRGB encoded UNorm" : kind==6 ? "linear HDR" : "linear UNorm";
      fprintf(stderr,"BC%d [%s] sample %zu: native %.9g, CPU fallback %.9g, error %.9g, tolerance %.9g (%s)\n",kind,stage,i,x[i],y[i],error.difference,error.tolerance,space);
      abort();
    }
  }
}

static id<MTLBuffer> probeBaseTexture(id<MTLTexture> source,id<MTLComputePipelineState> pipeline) {
  id<MTLBuffer> out = [R->device newBufferWithLength:source.width*source.height*16 options:MTLResourceStorageModeShared];
  assert(out);
  memset(out.contents,0xcd,out.length);
  endEncoders();
  id<MTLComputeCommandEncoder> encoder = [commandBuffer() computeCommandEncoder];
  [encoder setComputePipelineState:pipeline];
  [encoder setTexture:source atIndex:0];
  [encoder setBuffer:out offset:0 atIndex:0];
  [encoder dispatchThreads:MTLSizeMake(source.width,source.height,1) threadsPerThreadgroup:MTLSizeMake(4,4,1)];
  [encoder endEncoding];
  return out;
}

static bool probeIsSolidRed(id<MTLBuffer> buffer) {
  const float *values = (const float *)buffer.contents;
  for (size_t i = 0; i < buffer.length/sizeof(float); i++) {
    float expected = i%4 == 0 || i%4 == 3 ? 1 : 0;
    if (!std::isfinite(values[i]) || std::abs(values[i]-expected) > 0.001f) return false;
  }
  return true;
}

static void probeBC1UploadsAndReads() {
  bool correct = true;
  const uint8_t solidRed[] = {0x00,0xf8,0x00,0x00,0x00,0x00,0x00,0x00};
  for (bool padded : {false,true}) {
    Texture *t = makeTexture(71,4,4,1,1,true);
    uploadTextureBytes(t,0,0,0,0,0,4,4,1,padded ? 16 : 8,0,solidRed,sizeof solidRed);
    completeGPU();
    uint8_t actual[sizeof solidRed] = {};
    [t->tex getBytes:actual bytesPerRow:8 bytesPerImage:0 fromRegion:MTLRegionMake2D(0,0,4,4) mipmapLevel:0 slice:0];
    assert(t->compressedShadow.empty() && "Native BC blocks must not be permanently duplicated on the CPU.");
    bool bytesMatch = !memcmp(actual,solidRed,sizeof actual);
    // Bind the base texture directly: this probe has no array, mip or SRV view.
    id<MTLBuffer> read = probeBaseTexture(t->tex,samplingPipeline);
    id<MTLBuffer> sampled = probeBaseTexture(t->tex,nearestSamplingPipeline);
    completeGPU();
    const float *r = (const float *)read.contents, *s = (const float *)sampled.contents;
    bool readCorrect = probeIsSolidRed(read), sampleCorrect = probeIsSolidRed(sampled);
    fprintf(stderr,"BC1 probe %s: format=%lu storage=%lu type=%lu, raw blocks=%s [%02x %02x %02x %02x %02x %02x %02x %02x], read=(%.6g %.6g %.6g %.6g) %s, nearest sample=(%.6g %.6g %.6g %.6g) %s\n",
      padded ? "GPU blit from padded source" : "CPU replace from tight source",
      (unsigned long)t->tex.pixelFormat,(unsigned long)t->tex.storageMode,(unsigned long)t->tex.textureType,
      bytesMatch ? "match" : "MISMATCH",actual[0],actual[1],actual[2],actual[3],actual[4],actual[5],actual[6],actual[7],
      r[0],r[1],r[2],r[3],readCorrect ? "correct" : "INCORRECT",s[0],s[1],s[2],s[3],sampleCorrect ? "correct" : "INCORRECT");
    correct &= bytesMatch && readCorrect && sampleCorrect;
  }
  assert(correct && "Known BC1 bytes must survive both uploads and read/sample correctly without texture views.");
}

static void probeBC1PartialUpdates() {
  const uint8_t red[] = {0x00,0xf8,0,0,0,0,0,0}, blue[] = {0x1f,0x00,0,0,0,0,0,0};
  uint8_t fullRed[32], expected[32];
  for (unsigned i = 0; i < 4; i++) memcpy(fullRed+i*8,red,8);
  memcpy(expected,fullRed,sizeof expected); memcpy(expected+24,blue,8);
  bool correct = true;
  for (bool staged : {false,true}) {
    Texture *t = makeTexture(71,8,8,1,1,true);
    uploadTextureBytes(t,0,0,0,0,0,8,8,1,16,0,fullRed,sizeof fullRed);
    completeGPU();
    id<MTLBuffer> before = nil;
    if (staged) {
      before = probeBaseTexture(t->tex,samplingPipeline);
      t->lastUse = R->serial; // Same bookkeeping as an encoded production draw.
    }
    uploadTextureBytes(t,0,0,4,4,0,4,4,1,8,0,blue,sizeof blue);
    id<MTLBuffer> after = probeBaseTexture(t->tex,samplingPipeline);
    completeGPU();
    uint8_t actual[32] = {};
    [t->tex getBytes:actual bytesPerRow:16 bytesPerImage:0 fromRegion:MTLRegionMake2D(0,0,8,8) mipmapLevel:0 slice:0];
    bool rawCorrect = !memcmp(actual,expected,sizeof actual);
    bool shadowCorrect = t->compressedShadow.empty();
    bool gpuCorrect = true;
    const float *values = (const float *)after.contents;
    for (unsigned y = 0; y < 8; y++) for (unsigned x = 0; x < 8; x++) for (unsigned channel = 0; channel < 4; channel++) {
      bool bottomRight = x >= 4 && y >= 4;
      float expectedValue = channel == 3 || (bottomRight ? channel == 2 : channel == 0) ? 1 : 0;
      float value = values[(y*8+x)*4+channel];
      if (!std::isfinite(value) || std::abs(value-expectedValue) > 0.001f) gpuCorrect = false;
    }
    bool beforeCorrect = !before || probeIsSolidRed(before);
    const float *bottom = values+(4*8+4)*4;
    fprintf(stderr,"BC1 partial %s: no duplicate CPU blocks=%s, GPU raw blocks=%s [top-left %02x %02x, bottom-right %02x %02x], top-left=(%.6g %.6g %.6g %.6g), bottom-right=(%.6g %.6g %.6g %.6g), pixels=%s, preceding read=%s\n",
      staged ? "GPU staging after encoded read" : "GPU staging without pending reads",
      shadowCorrect ? "correct" : "INCORRECT",rawCorrect ? "correct" : "INCORRECT",actual[0],actual[1],actual[24],actual[25],
      values[0],values[1],values[2],values[3],bottom[0],bottom[1],bottom[2],bottom[3],
      gpuCorrect ? "correct" : "INCORRECT",beforeCorrect ? "correct or absent" : "INCORRECT");
    correct &= rawCorrect && shadowCorrect && gpuCorrect && beforeCorrect;
  }
  assert(correct && "Partial BC1 updates must preserve untouched blocks before and after prior GPU reads.");
}

static void checkReadback(Texture *t,uint32_t mip,uint32_t layer,Texture *reference=nullptr) {
  if(!reference)reference=t;
  uint32_t w,h,d; mipExtent(t,mip,w,h,d);
  PGBCUploadLayout layout;
  assert(pg_bc_upload_layout(t->bcKind,w,h,1,0,0,SIZE_MAX,&layout));
  const auto &expected = reference->compressedShadow.at(((uint64_t)mip<<32)|layer);
  assert(expected.size() == layout.imageBytes && expected.size()+4096 < R->memSize);
  memset(R->mem+4096,0x55,expected.size());
  *(uint32_t *)(R->mem+128) = 1;
  uint32_t p[17] = {t->oid,t->dim == 3 ? mip : mip+layer*t->mips,t->dim == 3 ? 1u : 0u,0,0,layer,w,h,layer+1,
    4096,0,(uint32_t)layout.rowBytes,(uint32_t)layout.imageBytes,0,(uint32_t)layout.imageBytes,128,0};
  uint64_t serial=R->serial;
  readback(p);
  completeGPU();
  if(R->serial>serial)waitSerial(serial);
  assert(*(uint32_t *)(R->mem+128) == 0);
  assert(!memcmp(R->mem+4096,expected.data(),expected.size()));
}

static void probeBC1SrgbComparison() {
  // Exact first block reconstructed from the failing deterministic upload.
  // The pinned CPU decoder produces R=186 at pixel8; the supplied virtual GPU
  // reported an sRGB result near R=188. Preserve the original code-value budget.
  const uint8_t block[]={0xe5,0xe7,0xc9,0x65,0xd0,0xda,0x06,0x43};
  Texture *native=makeTexture(71,4,4,1,1,true),*fallback=makeTexture(71,4,4,1,1,false);
  for(Texture *t:{native,fallback})uploadTextureBytes(t,0,0,0,0,0,4,4,1,8,0,block,sizeof block);
  checkReadback(native,0,0,fallback); // Compressed data must still match exactly.
  compare(sample(native,0,0),sample(fallback,0,0),1,"known quantized BC1 linear view");
  compare(sample(native,0,0,72),sample(fallback,0,0,72),1,"known quantized BC1 sRGB view");
  puts("PASS: known BC1 block retains exact bytes and the same quantization budget across linear/sRGB views.");
}

static void checkPartialPaddedReadback(Texture *native,Texture *fallback) {
  // Capture the right block-column in both rows of array slice 1. Destination
  // padding/guards must survive, and a following upload must not change this
  // pending readback's original bytes.
  PGBCUploadLayout full,region;
  assert(pg_bc_upload_layout(native->bcKind,8,8,1,0,0,SIZE_MAX,&full));
  assert(pg_bc_upload_layout(native->bcKind,4,8,1,0,0,SIZE_MAX,&region));
  const auto original=fallback->compressedShadow.at(1);
  const uint32_t pitch=(uint32_t)region.rowBytes+13;
  const size_t span=region.rows*pitch+16;
  std::vector<uint8_t> expected(span,0x55);
  for(size_t row=0;row<region.rows;row++)
    memcpy(expected.data()+row*pitch,original.data()+row*full.rowBytes+bcBlockBytes(native->bcKind),region.rowBytes);
  memset(R->mem+4096,0x55,span);
  *(uint32_t *)(R->mem+128)=1;
  uint32_t p[17]={native->oid,native->mips,1,4,0,0,8,8,1,4096,0,pitch,(uint32_t)span,0,(uint32_t)span,128,0};
  uint64_t serial=R->serial;
  readback(p);
  assert(R->serial>serial && "A valid native BC readback must submit its GPU copy.");
  assert(native->lastUse==serial && "Readback must prevent early CPU replacement of its source.");
  const auto replacement=blocks(native->bcKind,full.imageBytes*native->depthOrLayers,0x6578ac1u+native->bcKind);
  for(Texture *t:{native,fallback})
    uploadTextureBytes(t,0,0,0,0,0,8,8,t->depthOrLayers,(uint32_t)full.rowBytes,0,replacement.data(),replacement.size());
  completeGPU();
  waitSerial(serial);
  assert(*(uint32_t *)(R->mem+128)==0);
  assert(!memcmp(R->mem+4096,expected.data(),span));
  checkReadback(native,0,1,fallback);
  compare(sample(native,0,1),sample(fallback,0,1),native->bcKind,"upload after partial padded readback");
}

static void verifyOverlappingCopy(uint32_t dxgi) {
  Texture *native=makeTexture(dxgi,12,4,1,1,true),*fallback=makeTexture(dxgi,12,4,1,1,false);
  uploadPair(native,fallback,0,0x2c39e61u+dxgi,false);
  const auto original=fallback->compressedShadow.at(0);
  auto expected=original;
  size_t block=bcBlockBytes(native->bcKind);
  // [A,B,C] -> [A,A,B]: source and destination share the middle block.
  memcpy(expected.data()+block,original.data(),2*block);
  for(Texture *t:{native,fallback}) {
    uint32_t p[14]={t->oid,0,4,0,0,t->oid,0,1,0,0,0,8,4,1};
    copyRegion(p);
  }
  assert(fallback->compressedShadow.at(0)==expected);
  assert(native->compressedShadow.empty());
  checkReadback(native,0,0,fallback);
  compare(sample(native,0,0),sample(fallback,0,0),native->bcKind,"overlapping two-block self-copy");
}

static void verifyFormat(uint32_t dxgi) {
  Texture *native = makeTexture(dxgi,8,8,4,2,true), *fallback = makeTexture(dxgi,8,8,4,2,false);
  for (uint32_t mip = 0; mip < 4; mip++) uploadPair(native,fallback,mip,0xabc123u+17*dxgi+mip,false);
  // These samples really read the initial uploads on the GPU before an update.
  // Updating the same texture now must use staging and order behind that read.
  auto beforeNative = sample(native,0,0), beforeFallback = sample(fallback,0,0);
  uploadPair(native,fallback,0,0x146facbu+dxgi,false);
  auto afterNative = sample(native,0,0), afterFallback = sample(fallback,0,0);
  compare(beforeNative,beforeFallback,native->bcKind,"in-flight sample before update");
  compare(afterNative,afterFallback,native->bcKind,"in-flight sample after update");
  for (uint32_t mip = 0; mip < 4; mip++) for (uint32_t layer = 0; layer < 2; layer++) {
    char stage[64]; snprintf(stage,sizeof stage,"initial chain mip %u layer %u",mip,layer);
    compare(sample(native,mip,layer),sample(fallback,mip,layer),native->bcKind,stage);
    checkReadback(native,mip,layer,fallback); checkReadback(fallback,mip,layer);
  }
  // Odd source padding must repack into block-aligned rows before a Metal blit.
  uploadPair(native,fallback,0,0x9f00812u+dxgi,true);
  compare(sample(native,0,1),sample(fallback,0,1),native->bcKind,"odd-padded source upload layer 1");
  checkPartialPaddedReadback(native,fallback);
  verifyOverlappingCopy(dxgi);

  for (bool destinationNative : {true,false}) {
    Texture *target = makeTexture(dxgi,8,8,4,2,destinationNative);
    copyResource(target->oid,native->oid);
    for (uint32_t mip = 0; mip < 4; mip++) {
      char stage[80]; snprintf(stage,sizeof stage,"CopyResource native source to %s destination mip %u layer 1",destinationNative ? "native" : "decoded",mip);
      compare(sample(target,mip,1),sample(fallback,mip,1),native->bcKind,stage);
      if(target->hardwareBC)assert(target->compressedShadow.empty());
      checkReadback(target,mip,1,fallback);
    }
    // Software source to native destination is the reverse mixed-format path.
    copyResource(target->oid,fallback->oid);
    compare(sample(target,0,0),sample(fallback,0,0),native->bcKind,destinationNative ? "CopyResource decoded source to native destination layer 0" : "CopyResource decoded source to decoded destination layer 0");
  }
  // A self copy must snapshot blocks before overwriting the destination.
  for (Texture *t : {native,fallback}) {
    uint32_t region[14] = {t->oid,0,4,4,0,t->oid,0,1,0,0,0,4,4,1};
    copyRegion(region);
  }
  compare(sample(native,0,0),sample(fallback,0,0),native->bcKind,"self-copy 4x4 block to bottom-right of 8x8 mip");
  assert(native->compressedShadow.empty());
  checkReadback(native,0,0,fallback);
  std::vector<uint8_t> beforeInvalid = fallback->compressedShadow.at(0);
  uint64_t uploadedBeforeInvalid = R->bcNativeUploadBytes;
  uploadTextureBytes(native,0,0,0,0,0,8,8,1,0,0,beforeInvalid.data(),beforeInvalid.size()-1);
  assert(native->compressedShadow.empty() && R->bcNativeUploadBytes == uploadedBeforeInvalid);
  checkReadback(native,0,0,fallback);
  // Both directions of an sRGB/linear reinterpretation use actual SRV views.
  if (native->bcKind == 1 || native->bcKind == 2 || native->bcKind == 3 || native->bcKind == 7) {
    compare(sample(native,0,0,dxgi+1),sample(fallback,0,0,dxgi+1),native->bcKind,"linear texture sampled through sRGB SRV");
    Texture *s = makeTexture(dxgi+1,8,8,4,2,true), *f = makeTexture(dxgi+1,8,8,4,2,false);
    for(uint32_t mip=0;mip<4;mip++)uploadPair(s,f,mip,0x315fca1u+dxgi+mip,false);
    compare(sample(s,0,0,dxgi),sample(f,0,0,dxgi),native->bcKind,"sRGB texture sampled through linear SRV");
    // Different native Metal formats must snapshot their exact BC bytes via
    // the staging buffer, preserving bits without a gamma conversion.
    copyResource(s->oid,native->oid);
    copyResource(f->oid,fallback->oid);
    checkReadback(s,0,1,fallback);
    compare(sample(s,0,1),sample(f,0,1),native->bcKind,"native linear to sRGB copy");
    uploadPair(s,f,0,0xa17c4e3u+dxgi,false);
    copyResource(native->oid,s->oid);
    copyResource(fallback->oid,f->oid);
    checkReadback(native,0,1,f);
    compare(sample(native,0,1),sample(fallback,0,1),native->bcKind,"native sRGB to linear copy");
  }
}

static void verifyFormatSelection() {
  struct Expected { uint32_t dxgi; MTLPixelFormat format; };
  for (Expected e : {
      Expected{71,MTLPixelFormatBC1_RGBA}, {72,MTLPixelFormatBC1_RGBA_sRGB},
      {74,MTLPixelFormatBC2_RGBA}, {75,MTLPixelFormatBC2_RGBA_sRGB},
      {77,MTLPixelFormatBC3_RGBA}, {78,MTLPixelFormatBC3_RGBA_sRGB},
      {80,MTLPixelFormatBC4_RUnorm}, {83,MTLPixelFormatBC5_RGUnorm},
      {95,MTLPixelFormatBC6H_RGBUfloat}, {98,MTLPixelFormatBC7_RGBAUnorm}, {99,MTLPixelFormatBC7_RGBAUnorm_sRGB}}) {
    assert(mapFormat(e.dxgi,8,true).format == e.format);
    assert(mapFormat(e.dxgi,8,false).format != e.format);
  }
}

static void verifyThreeDimensionalFallback() {
  R->bcTextures = true;
  uint32_t words[] = {nextTextureId++,3,8,8,3,4,1,71,8,1};
  createTexture(words);
  Texture *t = texture(words[0]);
  assert(t && t->tex && !t->hardwareBC && t->format == MTLPixelFormatRGBA8Unorm);
  std::vector<uint8_t> source = blocks(1,96,0x3d5f21ab);
  uploadTextureBytes(t,0,0,0,0,0,8,8,3,0,0,source.data(),source.size());
  for (uint32_t layer = 0; layer < 3; layer++) {
    const auto &shadow = t->compressedShadow.at(layer);
    assert(shadow.size() == 32 && !memcmp(shadow.data(),source.data()+layer*32,32));
    checkReadback(t,0,layer);
  }
  // Also require the actual decoded 3D texture to contain the expected pixels.
  size_t decodedSize = 0;
  void *decoded = PGDecodeBC(1,8,8,3,0,0,source.data(),source.size(),&decodedSize);
  assert(decoded && decodedSize == 8*8*3*4);
  std::vector<uint8_t> actual(decodedSize);
  [t->tex getBytes:actual.data() bytesPerRow:32 bytesPerImage:256 fromRegion:MTLRegionMake3D(0,0,0,8,8,3) mipmapLevel:0 slice:0];
  assert(!memcmp(decoded,actual.data(),decodedSize));
  free(decoded);
}

static void verifyTightAndOversizedSourceStrides() {
  // A one-block row occupies eight bytes even when its source stride is huge.
  // External pitches must never escape into Metal's bounded row-stride API.
  for (uint32_t pitch : {0u, 0xfffffff8u}) {
    Texture *native = makeTexture(71,4,4,1,1,true), *fallback = makeTexture(71,4,4,1,1,false);
    std::vector<uint8_t> source = blocks(1,8,0x4a16ca1u);
    for (Texture *t : {native,fallback})
      uploadTextureBytes(t,0,0,0,0,0,4,4,1,pitch,0,source.data(),source.size());
    compare(sample(native,0,0),sample(fallback,0,0),1);
    checkReadback(native,0,0,fallback);
  }
}

static void verifyForegroundWorkAfterSuspendedCommit() {
  // Reproduce a non-present commit crossing scene suspension. The next PRESENT
  // must not label the old frame's accumulated wall time as foreground CPU.
  R->work.submit=30000;
  PGMetalRendererSetAppActive(false);
  std::atomic<bool> entered{false};
  std::thread render([&]{@autoreleasepool {entered.store(true);commit(CIdle);}});
  while(!entered.load())std::this_thread::yield();
  PGMetalRendererSetAppActive(true);
  render.join();
  auto timing=R->frameTiming;
  double at=CACurrentMediaTime();
  timing->presented(timing->epoch(),at);
  present(0);
  PGFrameTimingSnapshot stats;
  assert(timing->takeSnapshot(at+11,stats));
  assert(stats.submitted==1 && stats.submitMs<1000);
  id<MTLCommandBuffer> final=lastSubmitted;
  [final waitUntilCompleted];waitSerial(R->serial-1);
  puts("PASS: production non-present commit/PRESENT drops suspension-spanning work.");
}

static void verifyNoDrawableScalerReadLifetime() {
  if(![MTLFXSpatialScalerDescriptor supportsDevice:R->device])return;
  completeGPU();
  Texture *source=makeTexture(28,384,216,1,1,false);
  std::vector<uint8_t> pixels(384*216*4,255);
  uploadTextureBytes(source,0,0,0,0,0,384,216,1,384*4,0,pixels.data(),pixels.size());
  PGNoDrawableTestLayer *layer=[PGNoDrawableTestLayer new];
  layer.device=R->device;layer.pixelFormat=MTLPixelFormatBGRA8Unorm;
  R->layer=layer;
  PGMetalRendererSetPresentationSize(768,432);
  uint64_t serial=R->serial;
  present(source->oid);
  assert(R->upscaler.usesMetalFX());
  assert(source->lastUse==serial && "MetalFX reads must protect the source even without a drawable.");
  id<MTLCommandBuffer> submitted=lastSubmitted;
  [submitted waitUntilCompleted];waitSerial(serial);
  assert(submitted.status==MTLCommandBufferStatusCompleted);
  PGMetalRendererSetPresentationSize(0,0);R->upscaler.reset();R->layer=nil;
  puts("PASS: production no-drawable PRESENT retains scaler source lifetime bookkeeping.");
}

static void verifyPipelineInputReuse() {
  NSError *error=nil;
  NSString *source=@"#include <metal_stdlib>\nusing namespace metal;\nstruct Input {float2 position [[attribute(0)]];float2 offset [[attribute(1)]];};\nstruct Output {float4 p [[position]];};\nvertex Output cacheVertex(Input v [[stage_in]]) {return {float4(v.position+v.offset,0,1)};}\nfragment float4 cacheFragment() {return float4(1,0,0,1);}";
  id<MTLLibrary> library=[R->device newLibraryWithSource:source options:nil error:&error];
  assert(library);
  ShaderInfo vertexInfo,pixelInfo;
  vertexInfo.uid=10001;vertexInfo.function=[library newFunctionWithName:@"cacheVertex"];
  vertexInfo.inputs={0,1};
  pixelInfo.uid=10002;pixelInfo.function=[library newFunctionWithName:@"cacheFragment"];pixelInfo.outputs={0};
  Shader vertex(0),pixel(0);vertex.info=&vertexInfo;pixel.info=&pixelInfo;
  const uint32_t signature[]={17,0,0,15,18,0,1,15};
  vertex.sig={{17,0,0,15},{18,0,1,15}};
  vertex.signatureIdentity=R->pipelineInputs.intern(signature,8);
  PassInfo previous=R->passInfo;
  R->passInfo=PassInfo{};R->passInfo.colors[0]=MTLPixelFormatBGRA8Unorm;
  R->passInfo.colorCount=1;R->passInfo.key=0x138ca;
  const uint32_t before=R->pipesMade;
  uint32_t a[]={nextTextureId++,2,17,0,16,0,0,0,0,18,0,16,0,8,0,0};
  uint32_t b[]={nextTextureId++,2,17,0,16,0,0,0,0,18,0,16,0,8,0,0};
  createLayout(a);createLayout(b);
  Pipe *first=getPipeline(&vertex,&pixel,R->objs.as<Layout>(a[0],OLayout));
  Pipe *recreated=getPipeline(&vertex,&pixel,R->objs.as<Layout>(b[0],OLayout));
  assert(first==recreated && R->pipesMade==before+1 && "Equal vertex input layouts must share one actual Metal pipeline.");
  destroyObject(a[0]);destroyObject(b[0]);
  uint32_t c[]={nextTextureId++,2,17,0,16,0,0,0,0,18,0,16,0,8,0,0};createLayout(c);
  assert(getPipeline(&vertex,&pixel,R->objs.as<Layout>(c[0],OLayout))==first);
  // The same shader program with another semantic-to-register signature must
  // not accidentally reuse a descriptor built from the preceding signature.
  const uint32_t remapped[]={17,0,1,15,18,0,0,15};
  vertex.sig={{17,0,1,15},{18,0,0,15}};
  vertex.signatureIdentity=R->pipelineInputs.intern(remapped,8);
  Pipe *different=getPipeline(&vertex,&pixel,R->objs.as<Layout>(c[0],OLayout));
  assert(different!=first && R->pipesMade==before+2);
  auto deadline=std::chrono::steady_clock::now()+std::chrono::seconds(10);
  while(R->pipesPending.load() && std::chrono::steady_clock::now()<deadline)
    std::this_thread::sleep_for(std::chrono::milliseconds(1));
  assert(!R->pipesPending.load() && first->state && different->state);
  destroyObject(c[0]);R->passInfo=previous;
  puts("PASS: real Metal pipeline reuse across recreated/deleted layouts and separate vertex signatures.");
}

static bool verifySeedParserAndWarmPipeline() {
  // This is a real Metal test, not a substitute for execution on an Apple host.
  if(NSProcessInfo.processInfo.thermalState>=NSProcessInfoThermalStateSerious) {
    fputs("SKIP: host thermal pressure prevents the production startup warmup policy; no warmup GPU validation performed.\n",stderr);
    return false;
  }
  NSString *json=@"{\"version\":1,\"recipes\":[{\"vs\":\"0123456789abcdef\",\"ps\":\"\",\"el\":[[17,0,16,0,0,0,0]],\"st\":[8],\"b\":null,\"rt\":[],\"ds\":\"depth32float\",\"n\":1,\"ro\":0,\"tp\":4}]}";
  auto seeds=parsePipelineSeeds([json dataUsingEncoding:NSUTF8StringEncoding]);
  assert(seeds.size()==1 && seeds[0].strides[0]==8 && seeds[0].depth==MTLPixelFormatDepth32Float);
  for(NSString *bad in @[@"{}",@"[]",@"{\"version\":2,\"recipes\":[]}",
                         [json stringByReplacingOccurrencesOfString:@"depth32float" withString:@"unknown"],
                         [json stringByReplacingOccurrencesOfString:@"[17,0,16,0,0,0,0]" withString:@"[17,0,16,16,0,0,0]"],
                         [json stringByReplacingOccurrencesOfString:@"[17,0,16,0,0,0,0]" withString:@"[17,0,16,0,4294967295,0,0]"]])
    assert(parsePipelineSeeds([bad dataUsingEncoding:NSUTF8StringEncoding]).empty());
  NSError *error=nil;
  NSString *source=@"#include <metal_stdlib>\nusing namespace metal;\nstruct In {float2 p [[attribute(0)]];};\nvertex float4 seedVertex(In v [[stage_in]]) {return float4(v.p,0.5,1);}";
  id<MTLLibrary> library=[R->device newLibraryWithSource:source options:nil error:&error];
  assert(library);
  ShaderInfo vertexInfo;vertexInfo.uid=11001;vertexInfo.stage=0;
  vertexInfo.function=[library newFunctionWithName:@"seedVertex"];vertexInfo.inputs={0};
  assert(vertexInfo.function);
  auto vertex=std::make_unique<Shader>(0);vertex->info=&vertexInfo;vertex->sig={{17,0,0,15}};
  const uint32_t signature[]={17,0,0,15};
  vertex->signatureIdentity=R->pipelineInputs.intern(signature,4);
  R->warmupStopped=false;R->worldSince=0;R->warmupGeneration=1;
  R->drawsAtPresent=R->draws;
  R->requestsAtPresent=R->drawRequests;
  R->pipelineSeeds=seeds;R->warmupQueue.reset(seeds.size());
  // With no engine signature, no descriptor/compile is allowed.
  uint32_t before=R->pipesMade;
  warmupPipelines();
  assert(R->pipesMade==before);
  R->warmupShaders[seeds[0].vs]=std::move(vertex);R->warmupGeneration++;
  uint32_t layoutWords[]={nextTextureId++,1,17,0,16,0,0,0,0};createLayout(layoutWords);
  Layout *layout=R->objs.as<Layout>(layoutWords[0],OLayout);
  uint32_t bufferId=nextTextureId++;
  auto *stream=new Buffer(bufferId);stream->buf=[R->device newBufferWithLength:32 options:MTLResourceStorageModeShared];
  stream->size=stream->bytes=32;R->objs.set(bufferId,stream);
  auto previousVB=R->vb[0];R->vb[0]={bufferId,8,0};
  PassInfo previousPass=R->passInfo;
  R->passInfo=PassInfo{};R->passInfo.depth=MTLPixelFormatDepth32Float;
  R->passInfo.key=passPipelineKey(R->passInfo);
  uint32_t previousBlend=R->blendId,previousTopo=R->topo,previousLayout=R->layout;
  R->blendId=0;R->topo=4;R->layout=layoutWords[0];
  Pipe *previousLast=R->lastPipe;
  bool previousDirty=R->pipeDirty;
  auto deadline=std::chrono::steady_clock::now()+std::chrono::seconds(10);
  // OS preemption may consume a complete soft-budget slice before any submit.
  while(R->pipesMade==before && !R->warmupStopped && std::chrono::steady_clock::now()<deadline) {
    warmupPipelines();
    if(R->pipesMade==before)std::this_thread::sleep_for(std::chrono::milliseconds(1));
  }
  if(R->warmupStopped) {
    fputs("SKIP: pressure stopped startup warmup during the Metal regression.\n",stderr);
    return false;
  }
  assert(R->pipesMade==before+1);
  assert(R->vb[0].buf==bufferId && R->vb[0].stride==8 && R->layout==layoutWords[0]);
  assert(R->passInfo.key==passPipelineKey(R->passInfo) && R->lastPipe==previousLast && R->pipeDirty==previousDirty);
  Shader *actual=R->warmupShaders.at(seeds[0].vs).get();
  uint64_t used=R->warmupUsed;
  Pipe *pipe=getPipeline(actual,nullptr,layout);
  // A cached driver compile may complete before this first demand lookup.
  assert(R->pipesMade==before+1 && (pipe->prewarmed || R->warmupUsed==used+1));
  deadline=std::chrono::steady_clock::now()+std::chrono::seconds(10);
  while(R->pipesPending.load() && std::chrono::steady_clock::now()<deadline)
    std::this_thread::sleep_for(std::chrono::milliseconds(1));
  assert(!R->pipesPending.load() && pipe->state);
  assert(getPipeline(actual,nullptr,layout)==pipe && R->warmupUsed==used+1 && !pipe->prewarmed);
  assert(getPipeline(actual,nullptr,layout)==pipe && R->warmupUsed==used+1);

  // Missing and bound zero-stride streams generate the same constant-step
  // descriptor and must reuse it. Nonzero stride remains a distinct pipeline.
  R->vb[0]={};Pipe *constant=getPipeline(actual,nullptr,layout);
  R->vb[0]={bufferId,0,0};assert(getPipeline(actual,nullptr,layout)==constant && constant!=pipe);
  deadline=std::chrono::steady_clock::now()+std::chrono::seconds(10);
  while(R->pipesPending.load() && std::chrono::steady_clock::now()<deadline)
    std::this_thread::sleep_for(std::chrono::milliseconds(1));
  assert(!R->pipesPending.load() && constant->state);

  R->drawRequests+=301; // Even skipped draws stop speculative work.
  warmupPipelines();
  assert(R->warmupStopped && R->pipelineSeeds.empty() && R->warmupShaders.empty());
  R->vb[0]=previousVB;R->passInfo=previousPass;R->blendId=previousBlend;
  R->topo=previousTopo;R->layout=previousLayout;R->drawsAtPresent=R->draws;
  R->requestsAtPresent=R->drawRequests;
  destroyObject(layoutWords[0]);destroyObject(bufferId);
  puts("PASS: parsed startup recipe, required actual signature, same Metal warm/demand pipeline, zero-stride reuse and unchanged live state.");
  return true;
}

int main() {
  @autoreleasepool {
    verifyFormatSelection();
    id<MTLDevice> device = MTLCreateSystemDefaultDevice();
    if (!device || !device.supportsBCTextureCompression) {
      fputs("SKIP: real Metal GPU with BC texture support is unavailable; no GPU validation performed.\n",stderr);
      return 77;
    }
    R = new Renderer(); R->device = device; R->queue = [device newCommandQueue];
    R->completion = dispatch_semaphore_create(0);
    R->memSize = 1<<20; R->mem = (uint8_t *)calloc(1,R->memSize);
    assert(R->queue && R->mem);
    NSError *error = nil;
    NSString *shader = @"#include <metal_stdlib>\nusing namespace metal;\nkernel void readPixels(texture2d<float,access::read> image [[texture(0)]],device float4 *out [[buffer(0)]],uint2 p [[thread_position_in_grid]]) { if(p.x<image.get_width()&&p.y<image.get_height()) out[p.y*image.get_width()+p.x]=image.read(p); }\nkernel void samplePixels(texture2d<float,access::sample> image [[texture(0)]],device float4 *out [[buffer(0)]],uint2 p [[thread_position_in_grid]]) { constexpr sampler nearest(coord::normalized,filter::nearest,address::clamp_to_edge); if(p.x<image.get_width()&&p.y<image.get_height()) out[p.y*image.get_width()+p.x]=image.sample(nearest,(float2(p)+0.5f)/float2(image.get_width(),image.get_height()),level(0.0f)); }";
    id<MTLLibrary> library = [device newLibraryWithSource:shader options:nil error:&error];
    assert(library);
    samplingPipeline = [device newComputePipelineStateWithFunction:[library newFunctionWithName:@"readPixels"] error:&error];
    assert(samplingPipeline);
    nearestSamplingPipeline = [device newComputePipelineStateWithFunction:[library newFunctionWithName:@"samplePixels"] error:&error];
    assert(nearestSamplingPipeline);
    fprintf(stderr,"Testing production BC texture paths on %s\n",device.name.UTF8String);
    probeBC1UploadsAndReads();
    probeBC1PartialUpdates();
    if (getenv("PG_BC_PROBE_ONLY")) {
      puts("PASS: known BC1 probe only; the full randomized texture suite was not run.");
      return 0;
    }
    probeBC1SrgbComparison();
    for (uint32_t dxgi : {71u,74u,77u,80u,83u,95u,98u}) verifyFormat(dxgi);
    Texture *unaligned = makeTexture(71,7,5,3,1,true);
    assert(!unaligned->hardwareBC && unaligned->format == MTLPixelFormatRGBA8Unorm);
    Texture *cube = makeTexture(71,8,8,4,6,true);
    View srv(OSrv,0); srv.res = cube->oid; srv.b = 4;
    ResBinding binding{}; binding.kind = RTexture; binding.dim = DCube;
    id<MTLTexture> cubeView = srvTexture(&srv,cube,binding);
    assert(cubeView && cubeView.textureType == MTLTextureTypeCube);
    verifyThreeDimensionalFallback();
    completeGPU();
    assert(R->bcNativeCreated && R->bcFallbackCreated && R->bcNativeUploadBytes && R->bcDecodedBytes);
    Texture *small = makeTexture(71,1024,1024,1,1,true), *large = makeTexture(71,1024,1024,1,1,false);
    assert(small->tex.allocatedSize > 0 && small->tex.allocatedSize < large->tex.allocatedSize);
    fprintf(stderr,"BC1 1024x1024 GPU allocation: native %lu bytes, decoded %lu bytes\n",
      (unsigned long)small->tex.allocatedSize,(unsigned long)large->tex.allocatedSize);
    verifyTightAndOversizedSourceStrides();
    verifyPipelineInputReuse();
    if(!verifySeedParserAndWarmPipeline())return 77;
    verifyNoDrawableScalerReadLifetime();
    verifyForegroundWorkAfterSuspendedCommit();
    free(R->mem); delete R; R = nullptr;
    puts("PASS: real GPU BC1–BC7 sampling versus CPU fallback, in-flight and padded uploads, tail mips, array/cube views, sRGB twins, mixed copies, overlap and original-block readbacks.");
    return 0;
  }
}
