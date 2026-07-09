"""Load a tiny program that mirrors ButtonIn[4:0] to LEDOut[4:0]."""

from __future__ import annotations

import argparse
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))
sys.path.insert(0, str(ROOT / "other" / "debug"))

import assemble
from gui_debugger import UartDebugClient, fmt_u32, parse_u32


ASM = """
.text
.globl _start
_start:
    lui  t0, 0xFFFF0
loop:
    lw   t1, 4(t0)
    sw   t1, 8(t0)
    j    loop
"""


def build_words() -> list[int]:
    with tempfile.NamedTemporaryFile("w", suffix=".asm", delete=False, encoding="utf-8") as tmp:
        tmp.write(ASM)
        tmp_path = tmp.name
    try:
        resolved, _ = assemble.assemble(tmp_path)
    finally:
        Path(tmp_path).unlink(missing_ok=True)
    return [resolved[pc] for pc in sorted(resolved)]


def main() -> None:
    parser = argparse.ArgumentParser(description="Mirror FPGA buttons to LEDs")
    parser.add_argument("--port", default="COM3")
    parser.add_argument("--baud", type=int, default=115200)
    parser.add_argument("--base", default="0x4000")
    args = parser.parse_args()

    words = build_words()
    base = parse_u32(args.base)
    client = UartDebugClient(args.port, args.baud)
    try:
        client.halt()
        for i, word in enumerate(words):
            client.write_inst(base + i * 4, word)
        client.reset()
        client.run()
    finally:
        client.close()
    print(f"Loaded button LED test at {fmt_u32(base)}. Press buttons and watch LED[4:0].")


if __name__ == "__main__":
    main()
