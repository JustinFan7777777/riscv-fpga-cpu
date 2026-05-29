"""Write text to the EGO1 VGA text buffer through the UART debug protocol.

This script now loads a tiny CPU program into IMem, because UART debug writes
to DMem do not reach the VGA frame buffer. The CPU program performs the actual
`sw` instructions to 0xFFFF0100..0xFFFF13BF.

Usage examples:
  python test.py --port COM3 --text "Hello EGO1"
  python test.py --port COM3 --row 5 --col 20 --text "VGA"
  python test.py --port COM3 --clear --text "Hello" --fg A --bg 0
"""

from __future__ import annotations

import argparse
import importlib.util
import os
import struct
import tempfile
from pathlib import Path

import serial


HALT = b"\x03"
RESET = b"\x01"
RUN = b"\x02"
WRITE_INST = b"\x40"
RESP_ACK = 0x81

VGA_BASE = 0xFFFF_0100
VGA_COLS = 80
VGA_ROWS = 30


def pack_u32(value: int) -> bytes:
	return struct.pack(">I", value & 0xFFFF_FFFF)


def send_and_expect_ack(ser: serial.Serial, payload: bytes) -> None:
	ser.write(payload)
	resp = ser.read(1)
	if not resp or resp[0] != RESP_ACK:
		raise RuntimeError(f"expected ACK(0x81), got {resp!r}")


def split_u32_for_lui_addi(value: int) -> tuple[int, int]:
	value &= 0xFFFF_FFFF
	high = (value + 0x800) >> 12
	low = value - (high << 12)
	if low >= 2048:
		low -= 4096
	if low < -2048:
		low += 4096
	return high, low


def load_immediate(reg: str, value: int) -> list[str]:
	high, low = split_u32_for_lui_addi(value)
	return [f"lui {reg}, 0x{high:X}", f"addi {reg}, {reg}, {low}"]


def encode_cell(ch: str, fg: int, bg: int) -> int:
	ascii_code = ord(ch) & 0x7F
	return ((bg & 0xF) << 12) | ((fg & 0xF) << 8) | ascii_code


def build_program_asm(row: int, col: int, text: str, fg: int, bg: int, clear: bool) -> str:
	lines: list[str] = [".text", ".globl _start", "_start:"]

	if clear:
		lines.extend(load_immediate("t0", VGA_BASE))
		lines.extend(load_immediate("t1", 0x0020))
		lines.extend(load_immediate("t2", VGA_ROWS * VGA_COLS))
		lines.append("clear_loop:")
		lines.append("    sw t1, 0(t0)")
		lines.append("    addi t0, t0, 2")
		lines.append("    addi t2, t2, -1")
		lines.append("    bnez t2, clear_loop")

	start_addr = VGA_BASE + 2 * (row * VGA_COLS + col)
	lines.extend(load_immediate("t0", start_addr))

	for ch in text:
		cell = encode_cell(ch, fg, bg)
		lines.extend(load_immediate("t1", cell))
		lines.append("    sw t1, 0(t0)")
		lines.append("    addi t0, t0, 2")

	lines.append("done:")
	lines.append("    j done")
	return "\n".join(lines) + "\n"


def assemble_program(asm_source: str) -> dict[int, int]:
	root = Path(__file__).resolve().parents[2]
	assembler_path = root / "assemble.py"
	spec = importlib.util.spec_from_file_location("mini_riscv_assembler", assembler_path)
	if spec is None or spec.loader is None:
		raise RuntimeError(f"cannot load assembler from {assembler_path}")
	module = importlib.util.module_from_spec(spec)
	spec.loader.exec_module(module)

	with tempfile.NamedTemporaryFile("w", suffix=".asm", delete=False, encoding="utf-8") as tmp:
		tmp.write(asm_source)
		tmp_path = tmp.name

	try:
		resolved, _ = module.assemble(tmp_path)
	finally:
		try:
			os.unlink(tmp_path)
		except OSError:
			pass

	return resolved


def write_inst(ser: serial.Serial, addr: int, inst: int) -> None:
	send_and_expect_ack(ser, WRITE_INST + pack_u32(addr) + pack_u32(inst))


def load_program(ser: serial.Serial, resolved: dict[int, int]) -> None:
	for pc in sorted(resolved.keys()):
		write_inst(ser, 0x00004000 + pc, resolved[pc])


def main() -> None:
	parser = argparse.ArgumentParser(description="Write text to the EGO1 VGA text buffer")
	parser.add_argument("--port", default="COM3", help="Serial port, e.g. COM3 or /dev/ttyUSB0")
	parser.add_argument("--baud", type=int, default=115200, help="UART baud rate")
	parser.add_argument("--row", type=int, default=0, help="Target row [0..29]")
	parser.add_argument("--col", type=int, default=0, help="Target column [0..79]")
	parser.add_argument("--text", default="Hello EGO1", help="Text to display")
	parser.add_argument("--fg", default="F", help="Foreground color nibble (0-F)")
	parser.add_argument("--bg", default="0", help="Background color nibble (0-F)")
	parser.add_argument("--clear", action="store_true", help="Clear screen before writing text")
	parser.add_argument("--keep-running", action="store_true", help="Do not send RUN at the end")
	args = parser.parse_args()

	fg = int(args.fg, 16)
	bg = int(args.bg, 16)

	if not (0 <= args.row < VGA_ROWS):
		raise ValueError(f"row must be in [0, {VGA_ROWS - 1}]")
	if not (0 <= args.col < VGA_COLS):
		raise ValueError(f"col must be in [0, {VGA_COLS - 1}]")

	asm_source = build_program_asm(args.row, args.col, args.text, fg, bg, args.clear)
	resolved = assemble_program(asm_source)

	with serial.Serial(args.port, args.baud, timeout=0.5) as ser:
		send_and_expect_ack(ser, HALT)
		load_program(ser, resolved)
		send_and_expect_ack(ser, RESET)
		send_and_expect_ack(ser, RUN)

	print(f"Loaded {len(resolved)} instructions, text should appear at row={args.row}, col={args.col}")


if __name__ == "__main__":
	main()
