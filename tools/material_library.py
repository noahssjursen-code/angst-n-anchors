"""Import original ambientCG maps and audit the shared material library.

Python standard library only. Run --verify before committing material changes.
--fetch ID [ID ...] adds original 1K PNG colour/GL-normal/roughness/metalness
files, their source/license URLs and SHA256. It never generates texture images.
"""
from __future__ import annotations
import argparse
import hashlib
import io
import json
from pathlib import Path
import re
import struct
import urllib.request
import zipfile

ROOT = Path(__file__).resolve().parents[1]
LIBRARY = ROOT / "resources/textures/marine"
CHANNELS = ("Color", "NormalGL", "Roughness", "Metalness")


def read(name):
    return json.loads((LIBRARY / name).read_text(encoding="utf-8"))


def fetch(ids):
    manifest = read("sources.json")
    records = {item["id"]: item for item in manifest["assets"]}
    for asset in ids:
        if not re.fullmatch(r"[A-Za-z]+[0-9]+[A-Za-z]*", asset):
            raise ValueError("Use an ambientCG asset ID, such as MetalPlates001")
        url = f"https://ambientcg.com/get?file={asset}_1K-PNG.zip"
        request = urllib.request.Request(url, headers={"User-Agent": "AngstAnchors-MaterialImport/1.0"})
        with urllib.request.urlopen(request, timeout=120) as response:
            archive = zipfile.ZipFile(io.BytesIO(response.read()))
        files = []
        for channel in CHANNELS:
            filename = f"{asset}_1K-PNG_{channel}.png"
            if filename not in archive.namelist():
                if channel == "Metalness": continue
                raise ValueError(f"Missing required source map {filename}")
            content = archive.read(filename)
            if not content.startswith(b"\x89PNG\r\n\x1a\n"):
                raise ValueError(f"Invalid PNG: {filename}")
            destination = LIBRARY / asset / filename
            destination.parent.mkdir(exist_ok=True)
            if destination.exists() and destination.read_bytes() != content:
                raise ValueError(f"Source changed; review before replacing {destination}")
            destination.write_bytes(content)
            files.append({"file": filename, "sha256": hashlib.sha256(content).hexdigest()})
        records[asset] = {"id": asset, "source": f"https://ambientcg.com/view?id={asset}",
                          "download": url, "license": "CC0-1.0", "files": files}
        print(f"Downloaded original ambientCG {asset}: {len(files)} maps")
    manifest["assets"] = [records[key] for key in sorted(records)]
    (LIBRARY / "sources.json").write_text(json.dumps(manifest, indent=2)+"\n", encoding="utf-8")


def verify():
    records = read("sources.json")["assets"]
    ids = {row["id"] for row in records}
    count = total = 0
    for row in records:
        assert row["license"] == "CC0-1.0"
        for file in row["files"]:
            path = LIBRARY / row["id"] / file["file"]
            content = path.read_bytes()
            assert hashlib.sha256(content).hexdigest() == file["sha256"], path
            settings = path.with_suffix(".png.import").read_text(encoding="utf-8")
            assert "compress/mode=2" in settings and "mipmaps/generate=true" in settings, path
            if "NormalGL" in path.name: assert "compress/normal_map=1" in settings, path
            count += 1; total += len(content)
    profiles = read("profiles.json")
    for name, spec in profiles.items():
        assert spec["asset"] in ids, (name, spec)
        assert min(spec["metres"]) > 0, name
        assert 0 <= spec["roughness_low"] <= spec["roughness_high"] <= 1, name
    data = read("assignments.json")
    for group in ("exact", "prefix"):
        for name, profile in data[group].items(): assert profile in profiles, (name, profile)
    for overrides in data.get("asset_overrides", {}).values():
        for name, profile in overrides.items(): assert profile in profiles, (name, profile)
    for name, spec in data["character_uv"].items(): assert spec["asset"] in ids, name
    print(f"MATERIAL SOURCE PASS: {len(ids)} original sets, {count} hashed maps, {len(profiles)} profiles; {total/1048576:.1f} MiB source PNGs")


def configure_imports():
    count = 0
    for row in read("sources.json")["assets"]:
        for file in row["files"]:
            path = LIBRARY / row["id"] / (file["file"] + ".import")
            if not path.exists():
                raise ValueError(f"Import in Godot first: {path}")
            settings = path.read_text(encoding="utf-8")
            values = {"compress/mode": "2", "compress/high_quality": "true",
                      "mipmaps/generate": "true", "compress/normal_map": "1" if "NormalGL" in path.name else "0"}
            for key, value in values.items():
                settings, replacements = re.subn(r"(?m)^"+re.escape(key)+r"=.*$", key+"="+value, settings)
                assert replacements == 1, (path, key)
            path.write_text(settings, encoding="utf-8")
            count += 1
    print(f"Configured {count} original maps: VRAM compression, mipmaps, GL normal channels. Reimport in Godot.")


def audit():
    data = read("assignments.json")
    counts = {"shared_finish": 0, "authored_texture": 0, "character": 0, "optical": 0, "unassigned": 0}
    missing = {}
    models = ROOT / "resources/models"
    for folder in ("parts", "vessels", "cargo", "characters"):
        for path in (models / folder).rglob("*.glb"):
            binary = path.read_bytes()
            length = struct.unpack_from("<I", binary, 12)[0]
            doc = json.loads(binary[20:20+length])
            for mat in doc.get("materials", []):
                name = mat.get("name", "").split(".")[0]
                if folder == "characters": kind = "character"
                elif name in data.get("asset_overrides", {}).get(path.stem, {}) or name in data["exact"] or name.startswith("Paint_Surface") or any(name.startswith(p) for p in data["prefix"]): kind = "shared_finish"
                elif "baseColorTexture" in mat.get("pbrMetallicRoughness", {}): kind = "authored_texture"
                elif re.search(r"glass|glazing|lens|light|diffuser|screen|display|gauge|dial|readout|emission",name,re.I): kind = "optical"
                else:
                    kind = "unassigned"
                    missing.setdefault(name,set()).add(str(path.relative_to(models).parent))
                counts[kind] += 1
    print("ASSET AUDIT (source surfaces, not runtime instance counts):", json.dumps(counts))
    for name, families in sorted(missing.items()): print("REVIEW", name, ", ".join(sorted(families)))
    print("Authored textures and optical/character entries still require their own art review; these counts are not visual acceptance.")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--fetch", nargs="+")
    parser.add_argument("--verify", action="store_true")
    parser.add_argument("--audit", action="store_true")
    parser.add_argument("--configure-imports", action="store_true")
    args = parser.parse_args()
    if args.fetch: fetch(args.fetch)
    if args.configure_imports: configure_imports()
    if args.verify: verify()
    if args.audit: audit()
