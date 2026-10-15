# Runtime 1.3.7 evidence

The available new device log is `native-port-previous 2.log`, version1.3.6
(15.1), iPhone18,2 / A19 Pro, Sandbox. The other new attachment did not transfer;
it has not been read. Earlier similarly named logs are different runs.

## Missing controls

The log reaches controllable player status and WORLD_READY but never records
`Gameplay controls ready`. The1.3.6 loading helper incorrectly ORs two distinct
engine natives. Pinned engine SHA-256 remains
`11ca8d2c04c5e843d18ff4aea4899d72c86973c6b031df334e67c446b2ae83e0`.

- f34946, `CLoadingScreens::AreActive`, returns u32[19473636] !=0.
- f51354 reads the separate initial marker, u8[6972816].
- f34944, `CLoadingScreens::Shutdown`, clears that marker only in contexts
  6/8/9/10. All active shutdown routes clear the active context after cleanup.

The helper now matches AreActive exactly, retaining fail-closed bounds/input
initialization checks. The C regression with context0 and initial marker1 failed
before the fix and passes afterward. The UIKit fixture now calls the production
helper with that marker set throughout its loading/player/cutscene sequence,
instead of substituting a loading Bool. The actual device log does not include
the raw globals, so the persistent marker is an engine-supported cause, not a
captured device-memory observation. A new device run must confirm the transition.
Visibility cause bits are logged on change only; no per-frame string formatting.

## Performance

The log requests 120 Hz at Play with cap0, six active CPUs and engine budget4.
World cadence windows:81.6FPS (p50/p95/p99:9/17/17ms), then63.8FPS
(17/26/26ms). RAM is2.1GB used with6.0GB process headroom; Metal uses629–632MB,
thermal state is fair and Low Power Mode is off. Local reads average0.1–0.8ms,
with no slow reads/errors, streaming clamps, ring-full/fence/readback producer
wait, or meaningful drawable/upload-slot wait. More RAM or embedding the same
device-local files is not supported as a remedy by this run.

Render-thread samples include input mapping21% and normal draw passes. Main
samples include render, PVS, rasterizer, particle and control-worker waits. A
sample label is not sufficient to identify its underlying native lock cost.
GPU durations1.60–1.69ms are per command buffer, with5.2–5.4buffers per frame;
they do not establish an8.33ms whole-frame GPU budget.

The host previously used one global wait-queue mutex for every engine/render/
audio address. A preempted worker holding it blocked notification of unrelated
addresses. A deterministic pthread regression forces precisely that scheduling
case: old runtime fails, address-sharded runtime passes. The64 bounded queues
are keyed by actual backing address, preserve shared-address identity across
module instances, retain per-waiter conditions/exact counts/monotonic deadlines,
and compare addresses within each bucket to handle collisions correctly. No
spin waits, extra engine workers, affinity or QoS overrides are introduced.

A Linux-only synthetic workload uses mismatch/zero-timeout and empty notify
(no timed-wait emulation). Seven-run medians for100,000wait+notify pairs/worker:

| Workers | Global mutex | Address queues | Relative throughput |
| --- | ---: | ---: | ---: |
|1|1.503ms|2.303ms|0.65x|
|4|19.214ms|3.312ms|5.80x|
|8|46.983ms|13.301ms|3.53x|

This demonstrates reduced contention, with a small absolute lookup cost in the
single-worker case. It is not an iPhone benchmark or an FPS multiplier. Actual
Apple wait/notify, partial wakes, timeouts, traps and65 backing addresses
(more than the queue count, including wait64) are gated before IPA publication.
Enqueue overlap in that stress test depends on scheduling; it is not proof that
all65 waiters occupy queues simultaneously. The forced-preemption isolation
regression provides the deterministic independent-address progress check.
The independent-address preemption regression also runs20times in source CI.

## Device acceptance

Confirm `Touch visibility: shown` after loading, movement and modal/cheat return;
then compare the same warmed crowd/combat route at120Hz, recording p95/p99,
thermal state and any native CPU stall. Do not call120FPS stable from this host
microbenchmark. Apple's documented Game Mode and ProMotion declarations remain;
the OS retains control of thermal/power scheduling and refresh arbitration.

References: [Apple game performance guidance](https://developer.apple.com/documentation/metal/improving-your-games-graphics-performance-and-settings),
[ProMotion](https://developer.apple.com/documentation/quartzcore/optimizing-iphone-and-ipad-apps-to-support-promotion-displays).
