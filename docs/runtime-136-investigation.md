# Runtime 1.3.6 evidence and measurement limits

Pinned engine SHA-256: `11ca8d2c04c5e843d18ff4aea4899d72c86973c6b031df334e67c446b2ae83e0`.
The supplied 1.3.5(14.1) iPhone18,2 logs both boot with the 60 FPS engine cap.
They do not demonstrate cap-0/120 Hz performance. Thermal state is nominal/fair,
with no logged memory clamp, asset-read error or ring/fence/readback producer wait.
The late combat sample has a 1,088 ms CPU dependency stall dominated by
`g_VehicleAvoidance.Run`. This identifies an optimization opportunity, not proof
that one setting caused the entire stall. GPU duration is per command buffer;
summing or comparing a single buffer with an 8.33 ms frame budget is misleading.

## Console input

The current log's first RAPIDGT request is followed by raw key 0x49 and
`debug flight toggled (on)` while TEXT_INPUT_BOX receives that same character.
The engine's text queue is independent of raw key state. Send letters only to
the existing UTF-16 ring. Preserve physical console-open and Enter edges.
The native regression failed on the old raw-I press and passes with text-only
letters for RAPIDGT, PAINKILLER and BUZZOFF. Repeated script cheat-status log
messages are not evidence of repeated submitted cheat inputs.

## Controls and recovery

The pinned CLoadingScreens::AreActive (Wasm f34946) reads u32 at 19473636;
the initial-loading script native f51354 reads u8 at 6972816. Both must be clear,
engine input memory initialized and status0 observed before initial controls.
Keep WORLD_READY for graphics diagnostics/capture, independent of player input.
Transient status0 before loading finishes is explicitly tested. Release UI may
not expose the startup UITextView even with --show-log. The exact reported blue
screen route was not reproduced; BootPending only proves an unfinished launch,
not an out-of-memory termination.

## Bounded engine CPU budget

Apple's public `ProcessInfo.activeProcessorCount` supplies the active hardware
count at boot. Keep a separate engine budget: 4 for >=6 active CPUs, otherwise2.
Validated PG_ENGINE_CORES=1..8 overrides remain for paired profiling. The same
immutable budget supplies the logical-core import and -numCores argument.
This is our bounded scheduling policy, not an Apple-prescribed count.

Wasm import71 -> sysconf f90961 -> main f103 sets the engine count at6594340.
Main creates max(1,C-2) dependency workers (f2861, table2226). The gtaSched and
cloth defaults use the same formula. AddScheduler f3088 intersects requested
masks with low-C active bits and constructor f3087 sizes its workers by popcount.

| Pool | Budget2 | Budget4 | Budget6 |
| --- | ---: | ---: | ---: |
| Dependency | 1 | 2 | 4 |
| gtaSched | 1 | 2 | 4 |
| ClothInstanceSched | 1 | 2 | 4 |
| AudSched | 2 | 3 | 4 |
| ShapeTestAsyncSched | 1 | 3 | 4 |
| ptxUpdate | 2 | 4 | 6 |
| These six pools total | 8 | 16 | 26 |

InsertInternal f3111 wakes the same max(1,C-2) dependency count. Queues use CAS,
and completion waits use actual submitted handles. No two-core-only barrier or
host thread-count assumption was found. The registry's32 limit counts schedulers,
not workers. No simultaneous QoS change is made; engine thread-priority labels
currently do not establish native QoS.

References: [Apple CPU scheduling guidance](https://developer.apple.com/videos/play/tech-talks/110147/),
[activeProcessorCount](https://developer.apple.com/documentation/foundation/processinfo/activeprocessorcount),
[ProMotion guidance](https://developer.apple.com/documentation/quartzcore/optimizing-iphone-and-ipad-apps-to-support-promotion-displays),
[LSSupportsGameMode](https://developer.apple.com/documentation/bundleresources/information-property-list/lssupportsgamemode).

After installation, compare the same warm and sustained combat/crowd route with
cap0 at budgets2 and4. Collect actual presentation p50/p95/p99, AI waits,
thermals and an Instruments Game Performance trace if available. Settings changed
in-game take effect on the next game launch as the existing Settings screen says.
Do not label120 FPS achieved until this device run demonstrates it.

## Diagnostic delivery

The actual player's note and combined logs were delivered once. Three small or
empty developer emails were previous setup tests, not duplicated player reports.
No further real-email validation is used. A shared nonblocking submission guard
covers preparation through validated server acceptance/error, across Cancel/reopen.
Simulator URLProtocol tests intercept the real URLSession upload path locally;
Worker tests use a mock EMAIL binding. The recipient stays only in server secrets.
