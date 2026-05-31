#!/usr/bin/env python3
"""
加载 manual_test.txt 到 IMem, 用于镜头 4 手动上板验证。

用法:
    python3 other/load_manual_test.py --port COM3
    python3 other/load_manual_test.py --port /dev/ttyUSB0
"""
import argparse, serial, struct, time

HALT   = b'\x03'
RESET  = b'\x01'
RUN    = b'\x02'
WINST  = b'\x40'
ACK    = 0x81

def send_ack(ser, data):
    ser.write(data)
    r = ser.read(1)
    if not r or r[0] != ACK:
        raise RuntimeError(f"Expected ACK, got {r!r}")

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--port', default='COM3')
    ap.add_argument('--baud', type=int, default=115200)
    args = ap.parse_args()

    # 读 hex
    with open('other/manual_test.txt') as f:
        lines = [l.strip() for l in f if l.strip()]

    with serial.Serial(args.port, args.baud, timeout=0.5) as ser:
        # 暂停 CPU
        print("Halting CPU...")
        send_ack(ser, HALT)

        # 复位
        print("Resetting CPU...")
        send_ack(ser, RESET)

        # 逐条写入指令到 IMem 0x4000
        print(f"Loading {len(lines)} instructions to IMem 0x4000...")
        for i, line in enumerate(lines):
            instr = int(line, 16)
            addr = 0x4000 + i * 4
            ser.write(WINST + struct.pack('>I', addr) + struct.pack('>I', instr))
            r = ser.read(1)
            if not r or r[0] != ACK:
                raise RuntimeError(f"Write failed at line {i}: addr=0x{addr:08X} instr=0x{instr:08X}")

        # 复位 CPU 使 PC=0x4000
        print("Resetting CPU to start at 0x4000...")
        send_ack(ser, RESET)

        # 运行
        print("Running CPU...")
        send_ack(ser, RUN)

        print(f"\nDone! {len(lines)} instructions loaded.")
        print()
        print("========================================")
        print("  上板操作指引:")
        print("========================================")
        print()
        print("  SwitchIn[11:8] = 测试组: 0=Fib, 1=IEEE754, 2=AND")
        print("  SwitchIn[7:0]  = 操作数")
        print("  btn[0] = 执行")
        print("  btn[4] = 切换测试组")
        print("  LED[7:0] = 结果, LED[15:8]=0xFF=完成")
        print()
        print("  预期结果:")
        print("    组0: n=1→1, n=2→1, n=3→2, n=4→3")
        print("    组1: 0x7C00→1, 0xFC01→2, 0x2026→3, 0x0003→4, 0x0000→0")
        print("    组2: A&B")

if __name__ == '__main__':
    main()
