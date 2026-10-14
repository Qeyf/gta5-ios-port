#include <assert.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>

#if __has_include("NativeBCTextures.h")
#include "NativeBCTextures.h"

static void device_and_descriptor_choose_native_or_fallback(void) {
  for (int kind = 1; kind <= 7; kind++) {
    assert(pg_bc_native_eligible(true, kind, 2, 1024, 512, 11, 1, 1, 8));
    assert(pg_bc_native_eligible(true, kind, 2, 512, 512, 10, 6, 1, 8));
    assert(!pg_bc_native_eligible(false, kind, 2, 1024, 512, 11, 1, 1, 8));
    assert(!pg_bc_native_eligible(true, kind, 3, 1024, 512, 11, 1, 1, 8));
    assert(!pg_bc_native_eligible(true, kind, 1, 1024, 1, 11, 1, 1, 8));
    assert(!pg_bc_native_eligible(true, kind, 2, 7, 8, 3, 1, 1, 8));
    assert(!pg_bc_native_eligible(true, kind, 2, 8, 2, 4, 1, 1, 8));
    assert(!pg_bc_native_eligible(true, kind, 2, 8, 8, 5, 1, 1, 8));
    for (uint32_t bind = 0x20; bind <= 0x80; bind <<= 1)
      assert(!pg_bc_native_eligible(true, kind, 2, 8, 8, 4, 1, 1, bind));
    assert(!pg_bc_native_eligible(true, kind, 2, 8, 8, 4, 1, 4, 8));
  }
  assert(!pg_bc_native_eligible(true, 0, 2, 8, 8, 4, 1, 1, 8));
  assert(!pg_bc_native_eligible(true, 8, 2, 8, 8, 4, 1, 1, 8));
}

static void layouts_keep_block_rows_and_exact_payload_bounds(void) {
  for (int kind = 1; kind <= 7; kind++) {
    const size_t blockBytes = kind == 1 || kind == 4 ? 8 : 16;
    for (uint32_t w = 1; w <= 17; w++) for (uint32_t h = 1; h <= 17; h++) {
      size_t row = ((w+3)/4)*blockBytes, rows = (h+3)/4;
      for (uint32_t depth = 1; depth <= 3; depth++) {
        PGBCUploadLayout layout;
        size_t sourcePitch = row+3, sourceImage = sourcePitch*(rows+2);
        size_t required = (depth-1)*sourceImage+(rows-1)*sourcePitch+row;
        assert(pg_bc_upload_layout(kind,w,h,depth,(uint32_t)sourcePitch,(uint32_t)rows+2,required,&layout));
        assert(layout.rowBytes == row && layout.rows == rows);
        assert(layout.sourceRowPitch == sourcePitch && layout.sourceImagePitch == sourceImage);
        assert(layout.imageBytes == row*rows && layout.totalBytes == row*rows*depth);
        assert(layout.requiredBytes == required);
        // With a single image there is no depth fallback that could mask truncation.
        if (depth == 1) assert(!pg_bc_upload_layout(kind,w,h,1,(uint32_t)sourcePitch,0,required-1,&layout));
        assert(pg_bc_upload_layout(kind,w,h,depth,0,0,row*rows*depth,&layout));
        assert(layout.sourceRowPitch == row && layout.sourceImagePitch == row*rows);
      }
    }
  }
  PGBCUploadLayout layout;
  assert(!pg_bc_upload_layout(0,4,4,1,0,0,16,&layout));
  assert(!pg_bc_upload_layout(1,0,4,1,0,0,16,&layout));
  assert(!pg_bc_upload_layout(1,4,4,1,7,0,16,&layout));
  assert(!pg_bc_upload_layout(7,UINT32_MAX,UINT32_MAX,UINT32_MAX,0,0,SIZE_MAX,&layout));
  // Tight depth images may omit padding after their final row, but they may
  // never overlap the next image to conceal a truncated final block.
  assert(pg_bc_upload_layout(1,8,8,3,24,3,120,&layout));
  assert(layout.sourceImagePitch == 40 && layout.requiredBytes == 120);
  assert(!pg_bc_upload_layout(1,8,8,3,24,3,119,&layout));
  assert(!pg_bc_upload_layout(1,8,8,3,24,1,120,&layout));
}

static void edges_mips_and_partial_regions_follow_metal_blocks(void) {
  assert(pg_bc_region_valid(8,8,0,0,8,8));
  assert(pg_bc_region_valid(7,5,4,4,3,1));
  assert(pg_bc_region_valid(2,2,0,0,2,2));
  assert(pg_bc_region_valid(1,1,0,0,1,1));
  assert(!pg_bc_region_valid(8,8,1,0,4,4));
  assert(!pg_bc_region_valid(8,8,0,0,3,4));
  assert(!pg_bc_region_valid(8,8,4,4,8,4));
  assert(!pg_bc_region_valid(8,8,0,0,0,4));
}

static void padded_source_rows_repack_without_padding_or_overreads(void) {
  PGBCUploadLayout layout;
  uint8_t source[128], packed[64];
  for (size_t i = 0; i < sizeof source; i++) source[i] = (uint8_t)i;
  assert(pg_bc_upload_layout(1,8,8,2,19,3,sizeof source,&layout));
  assert(layout.totalBytes == sizeof packed);
  assert(pg_bc_pack_rows(&layout,source,sizeof source,packed,sizeof packed));
  assert(!memcmp(packed,source,16) && !memcmp(packed+16,source+19,16));
  assert(!memcmp(packed+32,source+57,16) && !memcmp(packed+48,source+76,16));
  assert(!pg_bc_pack_rows(&layout,source,layout.requiredBytes-1,packed,sizeof packed));
  assert(!pg_bc_pack_rows(&layout,source,sizeof source,packed,sizeof packed-1));
}

int main(void) {
  device_and_descriptor_choose_native_or_fallback();
  layouts_keep_block_rows_and_exact_payload_bounds();
  edges_mips_and_partial_regions_follow_metal_blocks();
  padded_source_rows_repack_without_padding_or_overreads();
  puts("PASS: native BC eligibility, block and tail-mip geometry, padded rows, array/depth pitches, exact source bounds and overflow rejection.");
}
#else
int main(void) {
  fputs("FAIL: native BC texture layout and hardware eligibility are not implemented.\n",stderr);
  return 1;
}
#endif
