"""Load a hex/text program into IMem over the UART debug protocol.

Example:
  python other/debug/load_hex.py other/snake/snake.txt --port COM3 --run
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

from gui_debugger import UartDebugClient, fmt_u32, parse_u32, read_hex_words


def load_hex(path: str, port: str, baud: int, base: int, run: bool) -> int:
    words = read_hex_words(path)
    if not words:
        raise ValueError(f"no hex words found in {path}")

    client = UartDebugClient(port, baud)
    try:
        client.halt()
        for i, word in enumerate(words):
            client.write_inst(base + i * 4, word)
        client.reset()
        if run:
            client.run()
    finally:
        client.close()

    return len(words)


def self_test() -> None:
    assert parse_u32("0x4000") == 0x4000
    assert fmt_u32(0x4000) == "0x00004000"


def main() -> None:
    if "--self-test" in sys.argv:
        self_test()
        print("self-test OK")
        return

    parser = argparse.ArgumentParser(description="Load HEX/TXT instructions into FPGA IMem")
    parser.add_argument("hex", nargs="?", default=str(Path("other") / "snake" / "snake.txt"))
    parser.add_argument("--port", default="COM3")
    parser.add_argument("--baud", type=int, default=115200)
    parser.add_argument("--base", default="0x4000", help="Debug byte address for first instruction")
    parser.add_argument("--run", action="store_true", help="Run CPU after reset")
    args = parser.parse_args()

    base = parse_u32(args.base)
    count = load_hex(args.hex, args.port, args.baud, base, args.run)
    action = "and started CPU" if args.run else "and reset CPU"
    print(f"Loaded {count} instructions from {args.hex} at {fmt_u32(base)} {action}.")


if __name__ == "__main__":
    main()
