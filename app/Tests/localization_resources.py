"""Validate the app's bilingual resources before Xcode compiles them."""
import json
from pathlib import Path
import plistlib
import re
import unittest

ROOT = Path(__file__).resolve().parents[2]
APP = ROOT / "app" / "App"
FORMAT = re.compile(r"%(?!%)(?:\d+\$)?[-+ #0]*(?:\d+|\*)?(?:\.(?:\d+|\*))?(?:hh|ll|h|l|z|t|j)?[@diuoxXfFeEgGaAcCsSp]")


def units(value):
    if isinstance(value, dict):
        if "stringUnit" in value:
            yield value["stringUnit"]
        for key, child in value.items():
            if key != "stringUnit":
                yield from units(child)


def formats(value):
    return [re.sub(r"^%\d+\$", "%", item) for item in FORMAT.findall(value.replace("%%", ""))]


class LocalizationResources(unittest.TestCase):
    def test_all_app_tables_are_fully_translated(self):
        for name in ("Main", "Settings", "Files", "Cheats", "InfoPlist"):
            path = APP / f"{name}.xcstrings"
            with self.subTest(table=name):
                self.assertTrue(path.is_file(), f"Missing bilingual catalog: {path.name}")
                if not path.is_file():
                    continue
                catalog = json.loads(path.read_text())
                self.assertEqual(catalog["sourceLanguage"], "en")
                self.assertTrue(catalog["strings"])
                for key, entry in catalog["strings"].items():
                    for language in ("en", "tr"):
                        localized = entry.get("localizations", {}).get(language)
                        self.assertIsNotNone(localized, f"{name}: {key!r} missing {language}")
                        translated = list(units(localized))
                        self.assertTrue(translated, f"{name}: {key!r} has no {language} value")
                        for unit in translated:
                            self.assertEqual(unit["state"], "translated", f"{name}: {key!r} incomplete {language}")
                            self.assertTrue(unit["value"].strip(), f"{name}: {key!r} empty {language}")
                            # Translators may reorder positional arguments, but may not change
                            # their types/precision or introduce additional arguments.
                            expected = formats(key)
                            actual = formats(unit["value"])
                            for token in actual:
                                self.assertIn(token, expected, f"{name}: {key!r} invalid format {token} in {language}")
                            self.assertLessEqual(len(actual), len(expected), f"{name}: {key!r} extra format arguments")

    def test_apple_bundle_advertises_both_languages_and_new_name(self):
        info = plistlib.loads((APP / "Info.plist").read_bytes())
        self.assertEqual(info["CFBundleDisplayName"], "GtaV Mobile")
        self.assertEqual(set(info["CFBundleLocalizations"]), {"en", "tr"})

    def test_ipa_packaging_uses_the_display_name(self):
        script = (ROOT / "build_ipa.sh").read_text()
        self.assertIn('"../../../GtaV Mobile.ipa"', script)
        self.assertIn('"$STAGE/Payload/GtaV Mobile.app"', script)
        self.assertNotIn("GTA5Port.ipa", script)


if __name__ == "__main__":
    unittest.main()
