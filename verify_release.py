"""Reject mislabeled SDK packages and existing versioned release assets."""
import argparse
import json
from pathlib import Path
import re
import subprocess
import sys


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, required=True)
    parser.add_argument("--version", required=True)
    parser.add_argument("--platform", required=True, choices=("windows-x64", "macos-arm64"))
    parser.add_argument("--repository", required=True)
    args = parser.parse_args()
    source = (args.source / "CMakeLists.txt").read_text(encoding="utf-8")
    match = re.search(r'set\(RADRAY_DXC_PACKAGE_VERSION\s+"([^"]+)"\)', source)
    if match is None or match.group(1) != args.version:
        print("Requested package version differs from the DXC source package version.", file=sys.stderr)
        return 1
    result = subprocess.run(["gh", "release", "view", "latest", "--repo", args.repository,
                             "--json", "assets"], capture_output=True, text=True)
    if result.returncode:
        print(result.stderr, file=sys.stderr)
        return 1
    names = {asset["name"] for asset in json.loads(result.stdout)["assets"]}
    prefix = f"dxc-{args.platform}-{args.version}"
    if names.intersection((prefix + ".zip", prefix + ".manifest.json")):
        print(f"Release already contains {prefix}; choose a new source package version.", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
