# BC1 sRGB validation failure — 2026-10-16

The first post-merge Apple verification run failed at
[run 38915206927](https://github.com/Qeyf/gta5-ios-port/actions/runs/38915206927),
source `a7313c907f112dfe56dead072c1f2dedce106c37`. Xcode 27.0 compiled the
graphics harnesses. On the Apple Paravirtual device, known BC1 uploads, raw
block readbacks, red/blue sampling and ordered partial updates passed. The
randomized suite then aborted on a linear texture sampled through an sRGB SRV:

```text
BC1 sample 32: native 0.502808332, CPU fallback 0.491086692,
tolerance 0.00823529344
```

## Reproduction and cause

Replaying the deterministic upload reconstructs the first compressed block as
`e5 e7 c9 65 d0 da 06 43`. Pixel 8 selects palette entry 2. The checksum-verified
pinned bcdec decoder produces RGBA8 `(186,232,52,255)` there.

Apple documents that an sRGB texture's RGB components are converted to linear
values when read/sampled. The comparison applied its existing decoded-UNorm
`2.1/255` budget directly to these nonlinear-transformed results. Applying
Apple's inverse transfer to the reported red values yields sRGB codes
`187.986922` and `186.011175`: a difference of `1.975747` code values, within
that original budget. Their linear difference is `0.011721640`, which exceeds
the incorrectly reused `0.008235294` bound. This establishes an error in the
test's color-space accounting; it is not evidence that all remaining GPU paths
pass or that every possible BC decode discrepancy is acceptable.

## Fix and retained checks

- Compare sRGB RGB samples in encoded UNorm space using Apple's documented
  piecewise transfer. Read the color-space flag from the actual Metal SRV pixel
  format, including native BC and decoded fallback formats; assert that the
  native and fallback views agree and honor the requested DXGI sRGB/linear
  direction. No stage-name guessing.
- Keep alpha and linear views in linear space, with the original UNorm budget.
  Preserve BC6H relative/near-zero tolerance and reject all nonfinite samples.
- Preserve exact compressed-byte readbacks, upload ordering, mixed/sRGB copies
  and the full randomized GPU suite. No checks are skipped and no global
  tolerance is increased. Production texture/decode behavior is unchanged.
- Add the exact known block to the GPU harness and a shared test-only comparison
  helper with a portable regression for the reported values, the full 8-bit
  RGB range, alpha, wrong gamma/color, nonfinite values and BC6H behavior.
- Cast CoreGraphics bitmap flags to `CGBitmapInfo` before combining them,
  addressing the separate C++ enum-conversion warning with the same flags.

## Verification limits

The portable regression failed on the supplied values before the comparison
fix and passed afterward. Local `nektos/act` portable checks exercise the same
helper used by the Apple GPU harness. No hosted workflow is dispatched by this
fix; commits use `[skip ci]`. The source branch is based on the user's merged
main commit, not the already merged PR #1 branch.

This host is Linux and cannot execute the new Metal probe, compile the changed
Objective-C++ with Apple's SDK, or produce an IPA. The original run demonstrates
Apple compilation of the preceding source only. Re-run Apple verification on
the corrected commit before claiming the GPU suite or IPA build succeeds.

References:

- https://developer.apple.com/documentation/metal/mtlpixelformat
- https://developer.apple.com/documentation/metal/mtlpixelformat/bc1_rgba_srgb
- https://developer.apple.com/library/archive/documentation/Miscellaneous/Conceptual/MetalProgrammingGuide/Mem-Obj/Mem-Obj.html
- https://developer.apple.com/documentation/coregraphics/cgbitmapinfo

## BC4 follow-up after the sRGB fix

[Run 38922541709](https://github.com/Qeyf/gta5-ios-port/actions/runs/38922541709),
source `0c5010e58d34ff21a180ba0351d381222d4b22be`, passed the known BC1 sRGB
probe and reached BC4. It failed a decoded-source to native-destination copy
comparison at sample 40: native `0.361519605`, CPU fallback `0.352941185`.

The deterministic source block is `02 e0 8a 20 2f 4e bc 14`, endpoints 2/224.
Sample 40 is the red component of full-image pixel (2,1), block-local pixel 6,
selector 3. Its ideal unsigned interpolated value is `90.8/255`. The existing
upstream decoder's legacy BC4 mode truncates this to 90; the library's documented
`BCDEC_BC4BC5_PRECISE` mode rounds it to 91. The reported GPU value is equivalent
to 92.187499/255. Against 91, the discrepancy is 1.187499 code values instead of
2.187499, inside the unchanged 2.1-code budget. These observations motivate the
CPU precision correction; new raw-copy assertions still have to run on Metal
before copy correctness can be established for that path.

Enable that upstream mode and its explicit unsigned argument in both production
and the original traversal reference. The reference compares traversal and
copying, using the same current decode mode. BC4/BC5 CPU fallback bytes can now
change by nearest rounding; the native compressed path and other decoder
formats retain their existing configuration. The upstream documents a potential
CPU speed cost for precise decoding; no measured device FPS gain is claimed.
This uses the existing pinned library, not a new decoding algorithm or an
increased test tolerance.

A production `PGDecodeBC` regression exercises all 65,536 endpoint pairs, both
palette modes, every selector, BC4 and both BC5 channels, plus the exact failure
block and clipped dimensions. Its known-block assertion failed before the mode
change and passed after it. Existing 1,372 BC1–BC7 traversal equivalence/bounds
cases also pass. Portable checks now fetch/verify the same pinned header as
Apple checks and execute both actual decoder suites. The header itself is
unchanged and remains SHA-256 verified.

The Metal suite adds a known BC4/BC5 decoded-to-native copy probe and checks the
exact compressed readback before randomized mixed-copy sample comparison. The
last GPU run compiled/executed the previous source; the new Metal probes and
complete corrected suite remain unverified on this Linux host. Do not report
the full GPU suite as passed until another Apple run completes it.

Additional primary references:

- https://developer.apple.com/documentation/metal/mtlpixelformat/bc4_runorm
- https://developer.apple.com/documentation/metal/mtlpixelformat/bc5_rgunorm
- https://github.com/iOrange/bcdec/blob/80859ed3b7afb1c527a2a99d70c61457bea72d0c/bcdec.h
