# Runtime fixes from the 1.3.3 (12.1) device logs

The supplied logs were produced on an iPhone18,2 with an Apple A19 Pro GPU,
iOS 27.2 and an 8,192 MiB application limit. These are observations of the old
build, not benchmark results for the new build.

| Observation | Current run | Previous run |
| --- | ---: | ---: |
| Peak process footprint | 5,342 MiB | 7,796 MiB |
| Lowest available application memory | 2,849 MiB | 395 MiB |
| Median renderer report rate | 45.35 FPS | 57.3 FPS |
| Cloth buffer warnings | 2,328 | 1,107 |

The renderer's “busy ms/frame” measures its CPU worker time; it is not a GPU
execution duration. The samples come from different gameplay and cannot prove
an improvement between builds. Current-run streaming clamps were zero, so
raising memory limits cannot explain or fix all its frame-rate drops.

## Cheat rejection

The pinned engine (`game.wasm` SHA-256
`11ca8d2c04c5e843d18ff4aea4899d72c86973c6b031df334e67c446b2ae83e0`)
publishes input block `0x64748c`. The original cheat bounds check required eight
byte alignment, rejecting this four byte aligned block before a worker could
start. The reference IPA independently confirms this address. The input block
contains atomics no wider than 32 bits; the separate virtual pad remains a
properly aligned 64-bit atomic. The regression exercises the actual engine
address, text delivery, cleanup, and invalid bounds.

No timing, mapping or UTF-16 ring rewrite was necessary: those matched the
working reference. The new log distinguishes rejected, started, delivered and
cancelled input. Delivery still does not claim that the game accepted a cheat.

## Main thread and background GPU use

The old callback posted every engine log line to the main queue, then opened,
sought and closed the log file for each line. The logger now coalesces writes
on a serial background queue, keeps the handle open, retains the last 500 UI
lines and refreshes the visible log at four updates per second. Only lifecycle
and boot progress events reach UIKit. Log sharing and background entry flush
pending writes; the previous played run remains preserved.
Fatal engine traps, stack frames and heap-access faults flush synchronously so
the final diagnostic is not lost when a process exits before the next batch.

The previous log contains a Metal
`kIOGPUCommandBufferCallbackErrorBackgroundExecutionNotPermitted` error. Scene
deactivation now fences future submissions and waits for the last submitted
command buffer to be scheduled. The renderer preserves pending ring commands
until activation; it does not drop fences or query callbacks.

## Memory pressure

The old renderer expanded every BC texture on the CPU even when the GPU
reported BC support. Eligible 2D textures now use native BC formats on capable
devices. Runtime capability, bind flags, dimensions and allocation success
select the native path; all other cases retain decoded textures. Block-row
uploads, tail mips, linear/sRGB views, compressed-shadow readback and mixed
native/decoded copies share the same validated layout. Reports distinguish
native uploads from CPU-decoded bytes. This reduces resource expansion; it
does not establish an on-device FPS percentage or enlarge iOS's memory limit.

Only completed upload-ring slots may relinquish unused chunks. The current
frame's used chunks and one spare stay retained, and resource owners keep their
own references. iOS memory warnings or less than 512 MiB available headroom
request trimming. Health reports include Metal allocation, retained upload
memory, thermal state and Low Power Mode. The existing engine heap, worker
count and streaming safety reserve are preserved.

The speech-memory warning comes from the engine's internal speech allocator;
the previous log also shows a 2,255 ms audio-worker stall. It does not establish
missing assets or insufficient total system RAM. No unverified engine memory
offset or audio-pool enlargement is applied.

Apple guidance:
- [Metal background execution](https://developer.apple.com/documentation/metal/preparing-your-metal-app-to-run-in-the-background)
- [Available application memory](https://developer.apple.com/documentation/os/os_proc_available_memory)
- [Metal feature tables](https://developer.apple.com/metal/Metal-Feature-Set-Tables.pdf)

Physical-device gameplay and cheat acceptance require installation of the new
IPA. Unit, concurrency, API compilation and packaging checks do not substitute
for that test.
