"""Exercise the real offline WebGPU-to-Metal recipe importer."""
import copy
import importlib.util
import pathlib
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("pipeline_seed_tool", ROOT / "Scripts" / "import_pipeline_seed.py")
tool = importlib.util.module_from_spec(spec)
spec.loader.exec_module(tool)


class PipelineSeedTests(unittest.TestCase):
    def setUp(self):
        self.vs = "0123456789abcdef"
        self.ps = "fedcba9876543210"
        self.index = {self.vs: {"stage": "vs", "ok": True},
                      self.ps: {"stage": "ps", "ok": True}, "_packs": ["0.pack"]}
        self.recipe = dict(vs=self.vs, ps=self.ps, el=[[17, 0, 16, 0, 0, 0, 0]],
                           st=[8], tp=4, sf="", b=None, d=None, r=None,
                           rt=["bgra8unorm"], n=1, ds="depth32float-stencil8", ro=0)

    def catalog(self, *lists):
        return tool.build_catalog(self.index, lists)["recipes"]

    def test_normal_and_low_profiles_share_one_native_pipeline(self):
        low = copy.deepcopy(self.recipe)
        low.update(d=[1, 1, 4], r=[3, 1], tp=5, sf="uint16")
        self.assertEqual(len(self.catalog([self.recipe], [low])), 1)

    def test_retains_native_pipeline_dependencies(self):
        variants = [self.recipe]
        for field, value in (("st", [16]), ("el", [[17, 0, 16, 0, 4, 0, 0]]),
                             ("b", [0, 0] + [0, 2, 1, 1, 2, 1, 1, 15] * 8),
                             ("rt", ["rgba16float"]), ("n", 4), ("ro", 1),
                             ("ds", "depth16unorm"), ("tp", 2)):
            rc = copy.deepcopy(self.recipe)
            rc[field] = value
            variants.append(rc)
        self.assertEqual(len(self.catalog(variants)), len(variants))

    def test_canonicalizes_native_depth_format_and_preserves_color_holes(self):
        a = copy.deepcopy(self.recipe)
        a.update(ds="depth24plus-stencil8", rt=["bgra8unorm", None, None, "bgra8unorm"])
        b = copy.deepcopy(a)
        b["ds"] = "depth32float-stencil8"
        result = self.catalog([a, b])
        self.assertEqual(len(result), 1)
        self.assertEqual(result[0]["rt"], a["rt"])
        self.assertEqual(result[0]["ds"], b["ds"])

    def test_depth_only_pipeline_without_pixel_shader(self):
        self.recipe.update(ps="", rt=[], ds="depth16unorm")
        result = self.catalog([self.recipe])
        self.assertEqual(len(result), 1)
        self.assertEqual(result[0]["ps"], "")

    def test_rejects_unknown_or_wrong_stage_shader(self):
        for record in (None, {"stage": "cs", "ok": True}, {"stage": "ps", "ok": False}):
            with self.subTest(record=record):
                if record is None:
                    self.index.pop(self.ps, None)
                else:
                    self.index[self.ps] = record
                with self.assertRaisesRegex(ValueError, "shader"):
                    self.catalog([self.recipe])

    def test_rejects_unsafe_layouts_formats_and_resource_counts(self):
        for field, value in (("el", [[17, 0, 16, 16, 0, 0, 0]]), ("el", [[17] * 6]),
                             ("st", []), ("st", [-1]), ("b", [0]), ("rt", ["unknown"]),
                             ("rt", ["bgra8unorm"] * 9), ("n", 3), ("ro", 4),
                             ("tp", 33), ("vs", "../../shader"), ("ds", "unknown"),
                             ("rt", [{}]), ("ds", [])):
            with self.subTest(field=field, value=value):
                rc = copy.deepcopy(self.recipe)
                rc[field] = value
                with self.assertRaises(ValueError):
                    self.catalog([rc])

    def test_deterministic_first_seen_order_and_no_input_mutation(self):
        source = copy.deepcopy(self.recipe)
        first = tool.build_catalog(self.index, [[source]])
        second = tool.build_catalog(self.index, [[source], [copy.deepcopy(source)]])
        self.assertEqual(first, second)
        self.assertEqual(source, self.recipe)

    def test_rejects_attribute_extent_overflow_before_metal_descriptor_creation(self):
        self.recipe["el"][0][4] = 0xffffffff
        with self.assertRaisesRegex(ValueError, "offset"):
            self.catalog([self.recipe])


if __name__ == "__main__":
    unittest.main()
