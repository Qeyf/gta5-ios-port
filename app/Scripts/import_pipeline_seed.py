#!/usr/bin/env python3
"""Build a validated native Metal pipeline warmup catalog from web recipes.

Only immutable render-pipeline inputs survive. D3D depth/raster state and strip
index format are dynamic in this Metal renderer. Vertex signatures MUST still
come from the running engine; a web recipe does not contain that mapping.
"""
import argparse
import hashlib
import json
import pathlib
import re

COLOR_FORMATS = {"bgra8unorm", "bgra8unorm-srgb", "rgba8unorm", "rgba8unorm-srgb",
                 "rgba16float", "rgba32float", "rg11b10ufloat", "r32float",
                 "rg16float", "rg32float", "r8unorm"}
DEPTH_FORMATS = {"", "depth16unorm", "depth32float", "depth32float-stencil8",
                 "depth24plus-stencil8"}
VERTEX_FORMATS = {2, 6, 16, 41, 3, 7, 17, 42, 4, 8, 18, 43, 10, 34, 54,
                  11, 35, 12, 36, 13, 37, 14, 38, 28, 30, 31, 32, 49, 50,
                  51, 52, 87, 24}


def words(value, count=None):
    if not isinstance(value, list) or (count is not None and len(value) != count):
        raise ValueError("invalid word-array length")
    if any(type(x) is not int or not 0 <= x <= 0xffffffff for x in value):
        raise ValueError("invalid uint32 word")
    return list(value)


def canonical_recipe(index, rc):
    def shader(stage, optional=False):
        h = rc.get(stage)
        if optional and h == "":
            return h
        info = index.get(h) if isinstance(h, str) else None
        if (not isinstance(h, str) or not re.fullmatch(r"[0-9a-f]{16}", h)
                or not isinstance(info, dict) or not info.get("ok") or info.get("stage") != stage):
            raise ValueError(f"missing, failed or wrong-stage {stage} shader: {h!r}")
        return h

    if not isinstance(rc, dict):
        raise ValueError("recipe must be an object")
    vs, ps = shader("vs"), shader("ps", optional=True)
    els = rc.get("el")
    if not isinstance(els, list) or len(els) > 32:
        raise ValueError("invalid layout element count")
    els = [words(e, 7) for e in els]
    for e in els:
        if e[2] not in VERTEX_FORMATS or e[3] >= 16 or e[5] not in (0, 1):
            raise ValueError("unsupported vertex layout")
        # The native builder stores the attribute end plus 4-byte rounding in
        # uint32. Reserve the largest supported attribute (16 bytes), not an
        # invented Metal stride limit; current recorded offsets are <=128.
        if e[4] > 0xffffffff - 16 - 3:
            raise ValueError("vertex offset extent overflows native descriptor bookkeeping")
    strides = words(rc.get("st"), len(dict.fromkeys(e[3] for e in els)))
    blend = rc.get("b")
    if blend is not None:
        blend = words(blend, 66)
    rt = rc.get("rt")
    if (not isinstance(rt, list) or len(rt) > 8
            or any(f is not None and (not isinstance(f, str) or f not in COLOR_FORMATS) for f in rt)):
        raise ValueError("unsupported color attachment format/count")
    depth, samples, ro, topo = (rc.get(k) for k in ("ds", "n", "ro", "tp"))
    if (not isinstance(depth, str) or depth not in DEPTH_FORMATS or type(samples) is not int or samples not in (1, 2, 4, 8)
            or type(ro) is not int or not 0 <= ro <= 3 or type(topo) is not int or not 1 <= topo <= 5):
        raise ValueError("unsupported pass format, sample count, flags or topology")
    if not any(rt) and not depth:
        raise ValueError("pipeline has no attachment")
    return dict(vs=vs, ps=ps, el=els, st=strides, b=blend, rt=list(rt),
                ds="depth32float-stencil8" if depth == "depth24plus-stencil8" else depth,
                n=samples, ro=ro, tp=1 if topo == 1 else 2 if topo in (2, 3) else 4)


def build_catalog(index, profiles):
    recipes, seen = [], set()
    for profile in profiles:
        if not isinstance(profile, list):
            raise ValueError("pipeline profile must be an array")
        for raw in profile:
            rc = canonical_recipe(index, raw)
            key = json.dumps(rc, separators=(",", ":"), sort_keys=True)
            if key not in seen:
                seen.add(key)
                recipes.append(rc)
    return {"version": 1, "recipes": recipes}


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--index", required=True, type=pathlib.Path)
    ap.add_argument("--recipes", required=True, action="append", type=pathlib.Path)
    ap.add_argument("--output", required=True, type=pathlib.Path)
    args = ap.parse_args()
    catalog = build_catalog(json.loads(args.index.read_text()),
                            [json.loads(p.read_text()) for p in args.recipes])
    catalog["sources"] = [{"name": p.name, "sha256": hashlib.sha256(p.read_bytes()).hexdigest()}
                           for p in [args.index] + args.recipes]
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(catalog, separators=(",", ":")) + "\n")
    print(f"Wrote {len(catalog['recipes'])} native pipeline recipes: {args.output}")


if __name__ == "__main__":
    main()
