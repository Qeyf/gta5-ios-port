#pragma once
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include <string.h>

// BC dimensions are in texels; source row/image pitches are in block rows.
// Keep the decoder's existing 256 MB upload bound and tight-depth fallback.
typedef struct {
  size_t rowBytes, rows, sourceRowPitch, sourceImagePitch;
  size_t imageBytes, totalBytes, requiredBytes;
} PGBCUploadLayout;

static inline bool pg_bc_native_eligible(bool supported, int kind, uint32_t dimension,
    uint32_t width, uint32_t height, uint32_t mips, uint32_t layers, uint32_t samples, uint32_t bind) {
  if (!supported || kind < 1 || kind > 7 || dimension != 2 || samples != 1 || (bind & 0xe0) ||
      width < 4 || height < 4 || width > 16384 || height > 16384 || (width & 3) || (height & 3) ||
      !layers || layers > 2048 || !mips) return false;
  uint32_t extent = width > height ? width : height, levels = 1;
  while (extent > 1) { extent >>= 1; levels++; }
  return mips <= levels;
}

static inline bool pg_bc_region_valid(uint32_t mipWidth, uint32_t mipHeight,
    uint32_t x, uint32_t y, uint32_t width, uint32_t height) {
  return width && height && x <= mipWidth && y <= mipHeight &&
    width <= mipWidth-x && height <= mipHeight-y && !(x & 3) && !(y & 3) &&
    (!(width & 3) || width == mipWidth-x) && (!(height & 3) || height == mipHeight-y);
}

static inline bool pg_bc_upload_layout(int kind, uint32_t width, uint32_t height, uint32_t depth,
    uint32_t rowPitch, uint32_t rowsPerImage, size_t sourceSize, PGBCUploadLayout *out) {
  const size_t limit = 256u * 1024u * 1024u;
  if (!out || kind < 1 || kind > 7 || !width || !height || !depth) return false;
  size_t blockBytes = kind == 1 || kind == 4 ? 8 : 16;
  size_t columns = width/4u + (width%4u != 0), rows = height/4u + (height%4u != 0);
  if (columns > limit/blockBytes) return false;
  size_t rowBytes = columns*blockBytes;
  if (rows > limit/rowBytes) return false;
  size_t imageBytes = rowBytes*rows;
  if (depth > limit/imageBytes) return false;
  size_t pitch = rowPitch ? rowPitch : rowBytes;
  if (pitch < rowBytes || rows-1 > (SIZE_MAX-rowBytes)/pitch) return false;
  size_t rowEnd = (rows-1)*pitch+rowBytes;
  if (rowEnd > sourceSize) return false;
  size_t imageRows = rowsPerImage ? rowsPerImage : rows;
  if (imageRows > SIZE_MAX/pitch) return false;
  size_t sourceImage = pitch*imageRows;
  if (depth > 1 && sourceImage > (sourceSize-rowEnd)/(depth-1)) sourceImage = sourceSize/depth;
  if (depth > 1 && (sourceImage < rowEnd || sourceImage > (sourceSize-rowEnd)/(depth-1))) return false;
  *out = (PGBCUploadLayout){rowBytes,rows,pitch,sourceImage,imageBytes,imageBytes*depth,
    (depth-1)*sourceImage+rowEnd};
  return true;
}

static inline bool pg_bc_pack_rows(const PGBCUploadLayout *layout, const void *source,
    size_t sourceSize, void *destination, size_t destinationSize) {
  if (!layout || !source || !destination || !layout->imageBytes ||
      layout->requiredBytes > sourceSize || layout->totalBytes > destinationSize) return false;
  size_t depth = layout->totalBytes/layout->imageBytes;
  for (size_t z = 0; z < depth; z++) for (size_t row = 0; row < layout->rows; row++)
    memcpy((uint8_t *)destination+z*layout->imageBytes+row*layout->rowBytes,
      (const uint8_t *)source+z*layout->sourceImagePitch+row*layout->sourceRowPitch,layout->rowBytes);
  return true;
}
