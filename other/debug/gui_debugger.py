"""Tiny UART GUI debugger for the FPGA CPU.

Usage:
  python other/debug/gui_debugger.py
  python other/debug/gui_debugger.py --self-test
"""

from __future__ import annotations

import struct
import sys
import time
import tkinter as tk
from tkinter import filedialog, messagebox, ttk
from typing import Callable


CMD_PING = b"\x00"
CMD_RESET = b"\x01"
CMD_RUN = b"\x02"
CMD_HALT = b"\x03"
CMD_STEP = b"\x04"
CMD_READ_REG = b"\x21"
CMD_READ_PC = b"\x22"
CMD_READ_INST = b"\x23"
CMD_READ_DMEM = b"\x24"
CMD_WRITE_INST = b"\x40"
CMD_WRITE_DMEM = b"\x41"

RESP_PONG = 0x80
RESP_ACK = 0x81
RESP_DATA32 = 0x82

ABI_NAMES = (
    "zero", "ra", "sp", "gp", "tp", "t0", "t1", "t2",
    "s0/fp", "s1", "a0", "a1", "a2", "a3", "a4", "a5",
    "a6", "a7", "s2", "s3", "s4", "s5", "s6", "s7",
    "s8", "s9", "s10", "s11", "t3", "t4", "t5", "t6",
)


def pack_u32(value: int) -> bytes:
    return struct.pack(">I", value & 0xFFFF_FFFF)


def parse_u32(text: str) -> int:
    value = text.strip().replace("_", "")
    base = 0 if value.lower().startswith("0x") else 16
    return int(value, base) & 0xFFFF_FFFF


def data32_from_response(resp: bytes) -> int:
    if len(resp) != 5 or resp[0] != RESP_DATA32:
        raise RuntimeError(f"expected DATA32(0x82)+4B, got {resp!r}")
    return struct.unpack(">I", resp[1:])[0]


def fmt_u32(value: int) -> str:
    return f"0x{value & 0xFFFF_FFFF:08X}"


def read_hex_words(path: str) -> list[int]:
    words: list[int] = []
    with open(path, "r", encoding="utf-8") as f:
        for raw in f:
            line = raw.split("#", 1)[0].split("//", 1)[0].strip()
            if line:
                words.append(int(line, 16) & 0xFFFF_FFFF)
    return words


class UartDebugClient:
    def __init__(self, port: str, baud: int, timeout: float = 0.8) -> None:
        try:
            import serial
        except ImportError as exc:
            raise RuntimeError("pyserial is required: pip install pyserial") from exc
        self.ser = serial.Serial(port, baud, timeout=timeout)

    def close(self) -> None:
        self.ser.close()

    def _read(self, size: int) -> bytes:
        resp = self.ser.read(size)
        if len(resp) != size:
            raise RuntimeError(f"timeout: expected {size} bytes, got {resp!r}")
        return resp

    def _ack(self, payload: bytes) -> bytes:
        self.ser.write(payload)
        resp = self._read(1)
        if resp[0] != RESP_ACK:
            raise RuntimeError(f"expected ACK(0x81), got {resp!r}")
        return resp

    def _data32(self, payload: bytes) -> int:
        self.ser.write(payload)
        return data32_from_response(self._read(5))

    def ping(self) -> bytes:
        self.ser.write(CMD_PING)
        resp = self._read(1)
        if resp[0] != RESP_PONG:
            raise RuntimeError(f"expected PONG(0x80), got {resp!r}")
        return resp

    def halt(self) -> None:
        self._ack(CMD_HALT)

    def reset(self) -> None:
        self._ack(CMD_RESET)

    def run(self) -> None:
        self._ack(CMD_RUN)

    def step(self) -> None:
        self._ack(CMD_STEP)

    def read_pc(self) -> int:
        return self._data32(CMD_READ_PC)

    def read_inst(self, addr: int) -> int:
        return self._data32(CMD_READ_INST + pack_u32(addr))

    def read_reg(self, reg: int) -> int:
        return self._data32(CMD_READ_REG + bytes([reg & 0x1F]))

    def read_dmem(self, addr: int) -> int:
        return self._data32(CMD_READ_DMEM + pack_u32(addr))

    def write_inst(self, addr: int, value: int) -> None:
        self._ack(CMD_WRITE_INST + pack_u32(addr) + pack_u32(value))

    def write_dmem(self, addr: int, value: int) -> None:
        self._ack(CMD_WRITE_DMEM + pack_u32(addr) + pack_u32(value))


class DebuggerApp(tk.Tk):
    def __init__(self) -> None:
        super().__init__()
        self.title("RISC-V FPGA UART Debugger")
        self.geometry("760x620")
        self.client: UartDebugClient | None = None

        self.port_var = tk.StringVar(value="COM3")
        self.baud_var = tk.StringVar(value="115200")
        self.pc_var = tk.StringVar(value="PC：--")
        self.inst_var = tk.StringVar(value="当前指令：--")
        self.mem_addr_var = tk.StringVar(value="0x0000400C")
        self.mem_value_var = tk.StringVar(value="0x00000000")
        self.hex_path_var = tk.StringVar(value=r"cpu_project\cpu_project.srcs\sources_1\new\batch_test.txt")
        self.imem_base_var = tk.StringVar(value="0x00004000")
        self.mem_status_var = tk.StringVar(value="内存操作：--")
        self.changed_var = tk.StringVar(value="本步寄存器变化：--")
        self.status_var = tk.StringVar(value="未连接")

        self._build_ui()
        self.protocol("WM_DELETE_WINDOW", self._on_close)

    def _build_ui(self) -> None:
        root = ttk.Frame(self, padding=10)
        root.pack(fill=tk.BOTH, expand=True)

        conn = ttk.Frame(root)
        conn.pack(fill=tk.X)
        ttk.Label(conn, text="串口").pack(side=tk.LEFT)
        ttk.Entry(conn, textvariable=self.port_var, width=10).pack(side=tk.LEFT, padx=(4, 10))
        ttk.Label(conn, text="波特率").pack(side=tk.LEFT)
        ttk.Entry(conn, textvariable=self.baud_var, width=8).pack(side=tk.LEFT, padx=(4, 10))
        ttk.Button(conn, text="连接", command=self.connect).pack(side=tk.LEFT)
        ttk.Button(conn, text="断开", command=self.disconnect).pack(side=tk.LEFT, padx=4)
        ttk.Button(conn, text="PING 测试", command=self.ping).pack(side=tk.LEFT, padx=4)

        ctrl = ttk.Frame(root)
        ctrl.pack(fill=tk.X, pady=8)
        for text, cmd in (
            ("暂停", self.halt),
            ("复位", self.reset),
            ("单步并暂停", self.step),
            ("连续运行", self.run),
            ("刷新状态", self.refresh),
        ):
            ttk.Button(ctrl, text=text, command=cmd).pack(side=tk.LEFT, padx=(0, 6))

        state = ttk.Frame(root)
        state.pack(fill=tk.X, pady=(0, 8))
        ttk.Label(state, textvariable=self.pc_var, width=24).pack(side=tk.LEFT)
        ttk.Label(state, textvariable=self.inst_var, width=28).pack(side=tk.LEFT)

        program = ttk.LabelFrame(root, text="程序文件", padding=8)
        program.pack(fill=tk.X, pady=(0, 8))
        ttk.Entry(program, textvariable=self.hex_path_var, width=48).pack(side=tk.LEFT, padx=(0, 4), fill=tk.X, expand=True)
        ttk.Button(program, text="选择文件", command=self.browse_hex).pack(side=tk.LEFT, padx=(0, 4))
        ttk.Label(program, text="装载地址").pack(side=tk.LEFT)
        ttk.Entry(program, textvariable=self.imem_base_var, width=12).pack(side=tk.LEFT, padx=4)
        ttk.Button(program, text="加载 HEX", command=self.load_hex).pack(side=tk.LEFT, padx=(0, 4))
        ttk.Button(program, text="执行一条并刷新", command=self.step_and_read).pack(side=tk.LEFT)

        mem = ttk.LabelFrame(root, text="数据内存观察", padding=8)
        mem.pack(fill=tk.X, pady=(0, 8))
        ttk.Label(mem, text="地址").pack(side=tk.LEFT)
        ttk.Entry(mem, textvariable=self.mem_addr_var, width=14).pack(side=tk.LEFT, padx=4)
        ttk.Button(mem, text="读取", command=self.read_memory).pack(side=tk.LEFT)
        ttk.Label(mem, text="值").pack(side=tk.LEFT, padx=(12, 4))
        ttk.Entry(mem, textvariable=self.mem_value_var, width=14).pack(side=tk.LEFT)
        ttk.Button(mem, text="写入", command=self.write_memory).pack(side=tk.LEFT, padx=4)
        ttk.Label(mem, textvariable=self.mem_status_var).pack(side=tk.LEFT, padx=(12, 0))

        regs_frame = ttk.LabelFrame(root, text="寄存器", padding=8)
        regs_frame.pack(fill=tk.BOTH, expand=True)
        self.regs = ttk.Treeview(regs_frame, columns=("abi", "value"), show="tree headings", height=16)
        self.regs.heading("#0", text="寄存器")
        self.regs.heading("abi", text="别名")
        self.regs.heading("value", text="值")
        self.regs.column("#0", width=70, anchor=tk.W)
        self.regs.column("abi", width=90, anchor=tk.W)
        self.regs.column("value", width=150, anchor=tk.W)
        self.regs.pack(side=tk.LEFT, fill=tk.BOTH, expand=True)
        scroll = ttk.Scrollbar(regs_frame, orient=tk.VERTICAL, command=self.regs.yview)
        scroll.pack(side=tk.RIGHT, fill=tk.Y)
        self.regs.configure(yscrollcommand=scroll.set)
        for i, abi in enumerate(ABI_NAMES):
            self.regs.insert("", tk.END, iid=str(i), text=f"x{i}", values=(abi, "--"))
        self.regs.tag_configure("changed", background="#fff3bf")

        ttk.Label(root, textvariable=self.changed_var, wraplength=720, justify=tk.LEFT).pack(fill=tk.X, pady=(8, 0))

        ttk.Label(root, textvariable=self.status_var).pack(fill=tk.X, pady=(8, 0))

    def require_client(self) -> UartDebugClient:
        if self.client is None:
            raise RuntimeError("未连接串口")
        return self.client

    def run_action(self, action: str, fn: Callable[[], str | None]) -> None:
        try:
            self.status_var.set(f"{action}中...")
            self.update_idletasks()
            message = fn()
            self.status_var.set(message or action)
        except Exception as exc:  # noqa: BLE001 - show hardware/protocol failures to the user
            self.status_var.set(f"{action}失败：{exc}")
            messagebox.showerror("UART 调试器", str(exc))

    def connect(self) -> None:
        def do() -> None:
            self.disconnect(show_status=False)
            self.client = UartDebugClient(self.port_var.get(), int(self.baud_var.get()))
            self.client.ping()
            self.refresh(show_status=False)

        self.run_action("已连接", do)

    def disconnect(self, show_status: bool = True) -> None:
        if self.client is not None:
            self.client.close()
            self.client = None
        if show_status:
            self.status_var.set("已断开")

    def ping(self) -> None:
        def do() -> str:
            resp = self.require_client().ping()
            return f"PING 返回：0x{resp[0]:02X} (PONG)"

        self.run_action("PING", do)

    def browse_hex(self) -> None:
        path = filedialog.askopenfilename(
            title="选择 HEX 文件",
            filetypes=(("文本/HEX 文件", "*.txt *.hex *.mem"), ("所有文件", "*.*")),
        )
        if path:
            self.hex_path_var.set(path)

    def halt(self) -> None:
        self.run_action("已暂停", lambda: self.require_client().halt())

    def reset(self) -> None:
        def do() -> None:
            self.require_client().reset()
            self.refresh(show_status=False)

        self.run_action("已复位", do)

    def run(self) -> None:
        self.run_action("正在连续运行", lambda: self.require_client().run())

    def step(self) -> None:
        self.step_and_read()

    def refresh(self, show_status: bool = True) -> None:
        def do() -> None:
            client = self.require_client()
            pc = client.read_pc()
            inst = client.read_inst(pc)
            self.pc_var.set(f"PC：{fmt_u32(pc)}")
            self.inst_var.set(f"当前指令：{fmt_u32(inst)}")
            self.read_registers(client)
            self.read_memory(show_status=False)

        if show_status:
            self.run_action("已刷新", do)
        else:
            do()

    def read_registers(self, client: UartDebugClient) -> list[int]:
        values = [client.read_reg(reg) for reg in range(32)]
        for reg, value in enumerate(values):
            self.regs.set(str(reg), "value", fmt_u32(value))
            self.regs.item(str(reg), tags=())
        return values

    def read_memory(self, show_status: bool = True) -> None:
        def do() -> str:
            addr = parse_u32(self.mem_addr_var.get())
            value = self.require_client().read_dmem(addr)
            self.mem_value_var.set(fmt_u32(value))
            msg = f"DMem[{fmt_u32(addr)}]={fmt_u32(value)}"
            self.mem_status_var.set(f"读取：{msg}")
            return f"读取数据内存：{msg}"

        if show_status:
            self.run_action("已读取数据内存", do)
        else:
            do()

    def write_memory(self) -> None:
        def do() -> str:
            addr = parse_u32(self.mem_addr_var.get())
            value = parse_u32(self.mem_value_var.get())
            self.require_client().write_dmem(
                addr,
                value,
            )
            self.read_memory(show_status=False)
            msg = f"DMem[{fmt_u32(addr)}]={fmt_u32(value)}"
            self.mem_status_var.set(f"写入：{msg}")
            return f"写入数据内存：{msg}"

        self.run_action("已写入数据内存", do)

    def load_hex(self) -> None:
        def do() -> None:
            client = self.require_client()
            words = read_hex_words(self.hex_path_var.get())
            base = parse_u32(self.imem_base_var.get())
            client.halt()
            for i, word in enumerate(words):
                client.write_inst(base + i * 4, word)
            client.reset()
            self.refresh(show_status=False)
            return f"已加载 {len(words)} 条指令，PC 已复位到 0x4000，未开始运行"

        self.run_action("已加载 HEX", do)

    def step_and_read(self) -> None:
        def do() -> None:
            client = self.require_client()
            client.halt()
            pc_before = client.read_pc()
            inst_before = client.read_inst(pc_before)
            regs_before = [client.read_reg(reg) for reg in range(32)]
            client.step()
            time.sleep(0.10)
            pc_after = client.read_pc()
            inst_after = client.read_inst(pc_after)
            self.pc_var.set(f"PC：{fmt_u32(pc_after)}")
            self.inst_var.set(f"当前指令：{fmt_u32(inst_after)}")
            regs_after = self.read_registers(client)
            self.read_memory(show_status=False)
            changed = [
                (reg, before, after)
                for reg, (before, after) in enumerate(zip(regs_before, regs_after))
                if before != after
            ]
            for reg, _, _ in changed:
                self.regs.item(str(reg), tags=("changed",))
                self.regs.see(str(reg))

            changed_parts = [
                f"x{reg}({ABI_NAMES[reg]}) {fmt_u32(before)} -> {fmt_u32(after)}"
                for reg, before, after in changed
            ]
            changed_text = "；".join(changed_parts) if changed_parts else "无寄存器变化"
            self.changed_var.set(f"本步寄存器变化：{changed_text}")
            return (
                f"单步诊断：PC {fmt_u32(pc_before)} -> {fmt_u32(pc_after)}，"
                f"执行指令 {fmt_u32(inst_before)}；"
                f"DMem[{self.mem_addr_var.get()}]={self.mem_value_var.get()}"
            )

        self.run_action("单步执行", do)

    def _on_close(self) -> None:
        self.disconnect(show_status=False)
        self.destroy()


def self_test() -> None:
    assert pack_u32(0x12345678) == b"\x12\x34\x56\x78"
    assert pack_u32(-1) == b"\xff\xff\xff\xff"
    assert parse_u32("0x400c") == 0x400C
    assert parse_u32("0000_400C") == 0x400C
    assert data32_from_response(b"\x82\xde\xad\xbe\xef") == 0xDEADBEEF


def main() -> None:
    if "--self-test" in sys.argv:
        self_test()
        print("self-test OK")
        return
    DebuggerApp().mainloop()


if __name__ == "__main__":
    main()
