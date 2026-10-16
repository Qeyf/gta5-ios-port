# High-resolution performance work

Scope: FPS only. Preserve selected detail settings, local game-file layout and
the 1.3.7 input fixes. The device capture previously inspected was 1.3.7 (16.1),
Ultra 2346×1080: typical world cadence 22–41 FPS, renderer around 3000–4500
draws/frame, Metal allocation 1.7→3.6 GB, process footprint 3.6→7.7 GB and thermal
state serious.
These are observations, not proof of a leak or of one specific GPU bottleneck.
The resumed workspace no longer contains the two `*3.log` attachments; do not
silently substitute older captures. Original analysis values above were retained
in the conversation. Sustained FPS changes need a fresh physical-device run.

## Rendering

Keep resolution selection as output. Native uses the same engine back buffer;
MetalFX Quality renders 2/3 of each dimension, Performance 1/2. Input respects
the existing engine bounds and aspect ratio. Detail options are untouched.
Use Apple's MTLFXSpatialScaler on the existing MTLCommandBuffer; cache one
configuration with three private output textures. Query the required texture
usage bits, copy the input only when its usage is insufficient, and retain
normal tracked-resource ordering. A documented MPSImageBilinearScale handles
live downsize transitions or a scaler-factory failure. No hand-written upscaler,
extra per-frame command buffer, CPU wait or synthetic/interpolated FPS.
The existing one-to-one present shader and framebuffer-only drawable remain.
Only the final perceptual RGBA8/BGRA8 scene is eligible. Other formats preserve
the complete original frame rather than changing its gamma or cropping it.

Temporal upscaling/interpolation requires explicit motion, depth, jitter and
history-reset data which the engine's PRESENT(textureId) interface doesn't
provide. Additional asset packs do not supply that render contract.

## Texture pressure

Hardware-compressed textures already contain the exact BC blocks. Permanent
CPU duplicates can be avoided by using documented ordered Metal blits for BC
readbacks and compatible copies. Preserve original blocks on decoded fallback
textures; mixed native-to-decoded copies may require an explicit rare GPU wait
before CPU decoding. Keep partial, mip, array, sRGB and overlapping-copy parity.
Do not evict live engine resources or expand memory allowances to hide pressure.

## Pipeline reuse and GPU timing

The original render pipeline cache used the engine input-layout object ID.
Recreating an identical layout therefore requested a new Metal pipeline. Input
layout and vertex signature contents now receive exact stable identities once
at object creation using a standard-library map. The render cache preserves
shader programs, signature remaps, bound-buffer strides, attachments, blend and
topology in its key. Pipeline compilation remains asynchronous; no new cache
eviction or compiler wait is introduced. Session logs report cache lookup hits
and retained pipeline/input-description counts. Device impact is unmeasured.

Each command-buffer completion now carries the renderer frame number. PRESENT
marks the expected number of buffers in that frame. Only complete valid groups
contribute a first-GPU-start to last-GPU-end interval, with mean and p50/p95/p99.
This span includes gaps between buffers and is not GPU occupancy or the sum of
buffer durations. The existing displayed-FPS measurement remains separate.
Partial groups survive reporting-window boundaries; fixed-size history and
foreground epochs exclude stale, invalid and suspension-spanning groups.

Portable tests cover exact input reuse across 20,000 recreated descriptions,
all layout fields, shader signature changes, overlapping/out-of-order and
concurrent GPU callbacks, invalid timestamps and lifecycle boundaries. A real
Metal regression covers recreated/deleted layouts and semantic-register remaps;
it is written but uncompiled/unrun on this Linux host.

For the additional engine inputs required by temporal MetalFX and interpolation,
see [the render input contract](temporal-render-inputs.md).

## Verification and build constraints

The requested nektos/act 0.2.89 binary is verified against its official release
SHA-256. Local portable checks use `-P ubuntu-latest=-self-hosted`, with no Docker
or hosted GitHub Actions minutes. They cannot compile UIKit or execute Metal.
This environment is Linux x86_64 and has no Xcode, macOS or Metal GPU. The Apple
GPU regression and IPA recipe must fail explicitly here, never report a fake
Apple pass or publish an unbuilt Release. Keep changes on a development branch
with `[skip ci]` until an actual Apple build host is available.

References:
- https://developer.apple.com/documentation/metalfx/mtlfxspatialscaler
- https://developer.apple.com/documentation/metalfx/mtlfxspatialscalerbase
- https://developer.apple.com/documentation/metalfx/mtlfxspatialscalerbase/outputtexture
- https://developer.apple.com/documentation/metalperformanceshaders/mpsimagebilinearscale
- https://developer.apple.com/documentation/metal/mtlrenderpipelinestate
- https://developer.apple.com/documentation/metal/mtlcommandbuffer/gpustarttime
- https://developer.apple.com/documentation/metal/mtlcommandbuffer/gpuendtime
- https://developer.apple.com/videos/play/wwdc2025/211/
- https://nektosact.com/usage/runners.html
- https://developer.apple.com/xcode/system-requirements
