"""Check catalog keys against the Swift compiler's actual extracted keys (macOS CI)."""
import json
from pathlib import Path
import subprocess
import sys

app = Path(__file__).resolve().parents[1] / "App"
catalogs = {p.stem: json.loads(p.read_text())["strings"] for p in app.glob("*.xcstrings")}
directory = Path(sys.argv[1])
keys = set()
for path in directory.rglob("*.stringsdata"):
    data = json.loads(path.read_text())
    for table, entries in data.get("tables", {}).items():
        for entry in entries:
            if entry.get("key"):
                keys.add((table, entry["key"]))
for path in directory.rglob("*.strings"):
    data = json.loads(subprocess.check_output(["plutil", "-convert", "json", "-o", "-", str(path)]))
    keys.update((path.stem, key) for key in data)
if not keys:
    raise SystemExit("Swift did not emit any localized keys; cannot verify coverage.")
missing = [(table, key) for table, key in sorted(keys) if key not in catalogs.get(table, {})]
for table, key in missing:
    print(f"Missing compiler-extracted key in {table}.xcstrings: {key!r}")
if missing:
    raise SystemExit(1)
print(f"Verified {len(keys)} Swift compiler-extracted keys against bilingual catalogs.")
