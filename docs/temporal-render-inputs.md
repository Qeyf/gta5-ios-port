# Engine inputs for temporal MetalFX

Spatial MetalFX is implemented in the 1.3.8 development branch. Temporal
upscaling and frame interpolation need additional engine data, as specified by
Apple. The current `PRESENT(textureId)` command exposes only the final image,
including the game UI. That is insufficient to configure either temporal
feature correctly. Neither feature is advertised as implemented.

## Useful source files to supply

If available from the web-port/engine developer:

- `wgpu_backend.h` and `wgpu_backend.cpp`: the graphics command producer and
  command-ring protocol referenced by this project's renderer.
- `wgpu_worker.js`: the web renderer used as the reference for that protocol.
- The engine render-pass source that produces scene color, depth and motion
  vectors, controls projection jitter, and schedules tone mapping/game UI.
- The matching shader sources/reflection for those passes. This project's
  generated `shader-reflection.jsonl` is useful metadata but does not by itself
  establish the per-frame camera/jitter/motion contract.

Additional texture packs or another copy of runtime `data/` do not identify
these engine signals. If source is unavailable, a real-device Metal frame
capture and shader reflection can help investigate what already exists, but
cannot establish a correct temporal integration in advance.

## Required per-frame information

| Input | Contract that must be verified |
| --- | --- |
| Scene color | Correct pre-postprocessing/pre-UI pass, render dimensions, pixel format and linear/perceptual/HDR convention |
| Depth | Corresponding frame/resolution, sampleable texture, near/far and reversed-depth convention |
| Motion vectors | Camera and object motion; coordinate convention, direction, units/scales and valid/reset regions |
| Projection jitter | Actual sample offsets used to render that frame, matching motion and depth |
| Exposure | Matching exposure/auto-exposure configuration for the selected color pipeline |
| Reset | Camera cuts, scene loads, resize and invalid history must reset temporal accumulation |
| UI/tonemap boundary | Interpolation follows tone mapping; UI must be composited using one of Apple's documented approaches |

Use Apple's feature/device checks and descriptors once these inputs are known.
Keep resources correctly ordered on the existing Metal queue; do not read depth
or motion back to the CPU each frame. Do not substitute zero/fabricated vectors,
an unrelated depth texture or duplicated presents for valid engine data.

For sustained 120 displayed FPS, the complete producer/renderer/presentation
path needs an approximately 8.33 ms cadence. Interpolation changes presentation
rate and has input/pacing/UI requirements; it does not make simulation or input
updates run at that rate. Validate actual frame times, thermal state, image
quality and control latency on the same iPhone route.

Wasm is a portable code compilation format. The current app already translates
that engine to ARM64 at build time. A 120 GB versus 21 GB asset-size comparison
does not establish that Wasm compressed the game data, or identify the rendering
bottleneck; the actual asset contents/code must be compared separately.

References:

- https://developer.apple.com/documentation/metalfx
- https://developer.apple.com/videos/play/wwdc2022/10103/
- https://developer.apple.com/videos/play/wwdc2025/211/
- https://webassembly.org/docs/high-level-goals/
