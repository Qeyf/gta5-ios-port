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
