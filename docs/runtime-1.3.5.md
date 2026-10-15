# Runtime changes in 1.3.5

The supplied 1.3.4 (13.1) device log covers an A19 Pro at 1172×540 with a 60 FPS
cap. Six combat windows average about 38.1 submitted frames/s. All recorded
frames use the 60 cap; the attachment does not contain a 120 FPS comparison.
Thermal state progresses from nominal through fair to serious. Combat drops
also occur while thermal state is fair and memory headroom exceeds 5 GiB.

There are no demand-read errors or memory-budget clamps during those combat
windows. Native BC texture uploads work with no CPU decoding fallback. Pipeline
skips are sparse compared with millions of draws. Engine profiles show CPU
dependency waits. The old “renderer busy” statistic is CPU wall time and cannot
establish GPU saturation; a background interval contaminates one old FPS window.

## Changes

- Local-file hints previously checked a server-only packed cache and scheduled
  redundant reads into temporary 1 MiB buffers. More than 34,000 hint jobs were
  scheduled in this run. Local mode now acknowledges and drains those hints
  without those jobs/copies; the six authoritative demand readers are unchanged.
  Streaming/server mode retains prefetch and cache behavior.
- Automatic cheat delivery uses console input. Gamepad sequences are preserved
  as an explicit method and remain ordinary gameplay buttons. Touch reset also
  clears queued pulses, minimum-press state and radio selection.
- Gameplay controls require a world milestone and an observed controllable local
  player, and disappear during later cutscenes/no-player transitions. Existing
  phone, prompt and pause-menu layouts remain usable after entering gameplay.
- Gyro reads fresh processed CoreMotion samples. Sensor timestamps drive an
  exponential filter, duplicate polls retain the current rate, and inactive/modal
  sessions discard old state. A dedicated continuous stick curve replaces the
  finger-drag threshold. The engine's eight-bit stick quantization remains.
- Local diagnostics use actual drawable-presented timestamps and completed Metal
  command-buffer GPU timestamps. Bounded foreground windows report frame-time
  percentiles, drawable/slot waits and CPU submission time; suspension epochs
  reject stale callbacks. No external frame reporting is enabled by this change.
- A dedicated Cloudflare relay replaces the unrelated original log service.
  Recipient configuration stays exclusively on the server. File reads happen
  off-main and server acceptance is validated before success is displayed.

## Verification boundary

Portable tests exercise native input sequences, lifecycle fencing, upload-cache
reclamation, bounded frame timing and report validation. Xcode CI compiles all
Swift UI, runs motion/readiness/report tests, tests the real asset scheduler and
cache over loopback HTTP ranges, exercises real Metal resources when a GPU is
available, and launches the native UIKit shell in English/Turkish on iOS 27.

A new physical-device combat run is still required to quantify FPS, frame-time
tails, thermals and gyro feel after these changes. Increasing the heap or advertised
engine core count without such measurements is not a demonstrated optimization.
Moving the same local files into an IPA does not remove the CPU dependency waits.
Further engine scheduling changes need controllable engine source/profiling data;
the native host can already be improved without redistributing game assets.

Apple references:
- https://developer.apple.com/documentation/coremotion/getting-processed-device-motion-data
- https://developer.apple.com/documentation/metal/mtlcommandbuffer/gpustarttime
- https://developer.apple.com/documentation/metal/mtldrawable/addpresentedhandler(_:)
