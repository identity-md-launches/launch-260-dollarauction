#!/usr/bin/env python3
"""Export ABI arrays from local Foundry build artifacts; no third-party Python packages."""

import argparse
import json
from pathlib import Path


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true", help="Fail if committed exports differ from build artifacts")
    args = parser.parse_args()
    root = Path(__file__).resolve().parent.parent
    outdated = []
    for contract in ("LaunchToken", "DollarAuction"):
        artifact = root / "out" / f"{contract}.sol" / f"{contract}.json"
        if not artifact.is_file():
            raise SystemExit(f"Missing {artifact.relative_to(root)}; run forge build first.")
        abi = json.loads(artifact.read_text(encoding="utf-8"))["abi"]
        content = json.dumps(abi, indent=2) + "\n"
        output = root / "docs" / "abi" / f"{contract}.json"
        if args.check:
            if not output.is_file() or output.read_text(encoding="utf-8") != content:
                outdated.append(str(output.relative_to(root)))
        else:
            output.parent.mkdir(parents=True, exist_ok=True)
            output.write_text(content, encoding="utf-8")
            print(f"Exported {output.relative_to(root)}")
    if outdated:
        raise SystemExit("Stale or missing ABI exports: " + ", ".join(outdated))
    if args.check:
        print("ABI exports match local build artifacts.")


if __name__ == "__main__":
    main()
