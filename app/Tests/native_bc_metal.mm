// Real Metal integration test. Include the renderer so its production texture
// creation, upload, views, copies and readbacks run without an engine/game bundle.
#include "../Source/MetalRenderer/MRRenderer.mm"
#include <cassert>
#include <cstdlib>

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

static id<MTLBuffer> sample(Texture *t,uint32_t mip,uint32_t layer,uint32_t dxgi = 0) {
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
  return output;
}

static void compare(id<MTLBuffer> a,id<MTLBuffer> b,int kind) {
  completeGPU();
  assert(a.length == b.length);
  const float *x = (const float *)a.contents, *y = (const float *)b.contents;
  for (size_t i = 0; i < a.length/sizeof(float); i++) {
    assert(std::isfinite(x[i]) && std::isfinite(y[i]));
    float tolerance = kind == 6 ? std::max(0.002f,std::abs(y[i])*0.01f) : 2.1f/255;
    if (std::abs(x[i]-y[i]) > tolerance) {
      fprintf(stderr,"BC%d sample %zu: native %.9g, CPU fallback %.9g, tolerance %.9g\n",kind,i,x[i],y[i],tolerance);
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
    const auto &shadow = t->compressedShadow.at(0);
    bool bytesMatch = shadow.size() == sizeof actual && !memcmp(actual,shadow.data(),sizeof actual);
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

static void checkReadback(Texture *t,uint32_t mip,uint32_t layer) {
  uint32_t w,h,d; mipExtent(t,mip,w,h,d);
  PGBCUploadLayout layout;
  assert(pg_bc_upload_layout(t->bcKind,w,h,1,0,0,SIZE_MAX,&layout));
  const auto &expected = t->compressedShadow.at(((uint64_t)mip<<32)|layer);
  assert(expected.size() == layout.imageBytes && expected.size()+4096 < R->memSize);
  memset(R->mem+4096,0x55,expected.size());
  *(uint32_t *)(R->mem+128) = 1;
  uint32_t p[17] = {t->oid,t->dim == 3 ? mip : mip+layer*t->mips,t->dim == 3 ? 1u : 0u,0,0,layer,w,h,layer+1,
    4096,0,(uint32_t)layout.rowBytes,(uint32_t)layout.imageBytes,0,(uint32_t)layout.imageBytes,128,0};
  readback(p);
  assert(*(uint32_t *)(R->mem+128) == 0);
  assert(!memcmp(R->mem+4096,expected.data(),expected.size()));
}

static void verifyFormat(uint32_t dxgi) {
  Texture *native = makeTexture(dxgi,8,8,4,2,true), *fallback = makeTexture(dxgi,8,8,4,2,false);
  for (uint32_t mip = 0; mip < 4; mip++) uploadPair(native,fallback,mip,0xabc123u+17*dxgi+mip,false);
  // These samples really read the initial uploads on the GPU before an update.
  // Updating the same texture now must use staging and order behind that read.
  id<MTLBuffer> beforeNative = sample(native,0,0), beforeFallback = sample(fallback,0,0);
  uploadPair(native,fallback,0,0x146facbu+dxgi,false);
  id<MTLBuffer> afterNative = sample(native,0,0), afterFallback = sample(fallback,0,0);
  compare(beforeNative,beforeFallback,native->bcKind);
  compare(afterNative,afterFallback,native->bcKind);
  for (uint32_t mip = 0; mip < 4; mip++) for (uint32_t layer = 0; layer < 2; layer++) {
    compare(sample(native,mip,layer),sample(fallback,mip,layer),native->bcKind);
    checkReadback(native,mip,layer); checkReadback(fallback,mip,layer);
  }
  // Odd source padding must repack into block-aligned rows before a Metal blit.
  uploadPair(native,fallback,0,0x9f00812u+dxgi,true);
  compare(sample(native,0,1),sample(fallback,0,1),native->bcKind);

  for (bool destinationNative : {true,false}) {
    Texture *target = makeTexture(dxgi,8,8,4,2,destinationNative);
    copyResource(target->oid,native->oid);
    for (uint32_t mip = 0; mip < 4; mip++) {
      compare(sample(target,mip,1),sample(fallback,mip,1),native->bcKind);
      assert(target->compressedShadow.at(((uint64_t)mip<<32)|1) == native->compressedShadow.at(((uint64_t)mip<<32)|1));
      checkReadback(target,mip,1);
    }
    // Software source to native destination is the reverse mixed-format path.
    copyResource(target->oid,fallback->oid);
    compare(sample(target,0,0),sample(fallback,0,0),native->bcKind);
  }
  // A self copy must snapshot blocks before overwriting the destination.
  for (Texture *t : {native,fallback}) {
    uint32_t region[14] = {t->oid,0,4,4,0,t->oid,0,1,0,0,0,4,4,1};
    copyRegion(region);
  }
  compare(sample(native,0,0),sample(fallback,0,0),native->bcKind);
  assert(native->compressedShadow.at(0) == fallback->compressedShadow.at(0));
  std::vector<uint8_t> beforeInvalid = native->compressedShadow.at(0);
  uint64_t uploadedBeforeInvalid = R->bcNativeUploadBytes;
  uploadTextureBytes(native,0,0,0,0,0,8,8,1,0,0,beforeInvalid.data(),beforeInvalid.size()-1);
  assert(native->compressedShadow.at(0) == beforeInvalid && R->bcNativeUploadBytes == uploadedBeforeInvalid);
  // Both directions of an sRGB/linear reinterpretation use actual SRV views.
  if (native->bcKind == 1 || native->bcKind == 2 || native->bcKind == 3 || native->bcKind == 7) {
    compare(sample(native,0,0,dxgi+1),sample(fallback,0,0,dxgi+1),native->bcKind);
    Texture *s = makeTexture(dxgi+1,8,8,4,2,true), *f = makeTexture(dxgi+1,8,8,4,2,false);
    uploadPair(s,f,0,0x315fca1u+dxgi,false);
    compare(sample(s,0,0,dxgi),sample(f,0,0,dxgi),native->bcKind);
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
    checkReadback(native,0,0);
  }
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
    if (getenv("PG_BC_PROBE_ONLY")) {
      puts("PASS: known BC1 probe only; the full randomized texture suite was not run.");
      return 0;
    }
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
    free(R->mem); delete R; R = nullptr;
    puts("PASS: real GPU BC1–BC7 sampling versus CPU fallback, in-flight and padded uploads, tail mips, array/cube views, sRGB twins, mixed copies, overlap and original-block readbacks.");
    return 0;
  }
}
