#!/usr/bin/env python3
"""Convert a file to one 8-bit binary byte per line."""

from __future__ import annotations

import argparse
from pathlib import Path


def convert(input_path: Path, output_path: Path) -> None:
    data = input_path.read_bytes()
    output_path.write_text(
        "".join(f"{byte:08b}\n" for byte in data),
        encoding="ascii",
    )


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Convert a text/binary file to one 8-bit binary byte per line."
    )
    parser.add_argument("input", type=Path, help="Input file path")
    parser.add_argument("output", type=Path, help="Output file path")
    args = parser.parse_args()

    convert(args.input, args.output)


if __name__ == "__main__":
    main()
