# 测试验证结果

> RARS: 2026-05-17, 测试人: 刘一骏 | Difftest: 2026-05-18, 测试人: 陈俊希

## 结果总览：33/33 PASS ✅ (Difftest) + 21/21 PASS ✅ (RARS)

| Case | 测试组数 | RARS | Difftest | 说明 |
|------|---------|------|---------|------|
| 0 | 2 | PASS | PASS | AND 运算 |
| 1 | 2 | — | PASS | SLL 逻辑左移 |
| 2 | 2 | — | PASS | SRA 算术右移 |
| 3 | 2 | — | PASS | LUI + ADD |
| 4 | 2 | PASS | PASS | JAL + AUIPC |
| 5 | 2 | — | PASS | JAL + JALR |
| 6 | 4 | PASS | PASS | Fibonacci, n=1~4 |
| 7 | 2 | — | PASS | Popcount |
| 8 | 9 | PASS | PASS | IEEE754 半精度分类 |
| 9 | 6 | PASS | PASS | 浮点→Q3.4 量化 |

## Difftest 完整输出 (2026-05-18, 12.5MHz)

```
Loading 130 instructions to 0x00000000...
  Progress: 130/130
Verifying...
Verify OK: all 130 instructions correct
Program loaded successfully

--- TestCase Batch Test (Data Base: 0x4000 - Hardwired to GP) ---
  [1/33] case=0 ops=[0x00000F0F, 0x00001234] => 0x00000204 PASS
  [2/33] case=0 ops=[0xFFFFFFFF, 0x00001234] => 0x00001234 PASS
  [3/33] case=1 ops=[0x12481248, 0x00000004] => 0x24812480 PASS
  [4/33] case=1 ops=[0x00000001, 0x0000002D] => 0x00002000 PASS
  [5/33] case=2 ops=[0x71240000, 0x00000018] => 0x00000071 PASS
  [6/33] case=2 ops=[0x81231234, 0x00000024] => 0xF8123123 PASS
  [7/33] case=3 ops=[0x10000000, 0x00000000] => 0x22345000 PASS
  [8/33] case=3 ops=[0x00000001, 0x00000000] => 0x12345001 PASS
  [9/33] case=4 ops=[0x00000000, 0x00000000] => 0x12345000 PASS
  [10/33] case=4 ops=[0x00000010, 0x00000000] => 0x12345010 PASS
  [11/33] case=5 ops=[0x00000005, 0x00000006] => 0x0000000B PASS
  [12/33] case=5 ops=[0x00000001, 0x00000002] => 0x00000003 PASS
  [13/33] case=6 ops=[0x00000001, 0x00000000] => 0x00000001 PASS
  [14/33] case=6 ops=[0x00000002, 0x00000000] => 0x00000001 PASS
  [15/33] case=6 ops=[0x00000003, 0x00000000] => 0x00000002 PASS
  [16/33] case=6 ops=[0x00000004, 0x00000000] => 0x00000003 PASS
  [17/33] case=7 ops=[0x000000C1, 0x00000000] => 0x00000003 PASS
  [18/33] case=7 ops=[0x000000F8, 0x00000000] => 0x00000005 PASS
  [19/33] case=8 ops=[0x00008000, 0x00000000] => 0x00000000 PASS
  [20/33] case=8 ops=[0x00000000, 0x00000000] => 0x00000000 PASS
  [21/33] case=8 ops=[0x00007C00, 0x00000000] => 0x00000001 PASS
  [22/33] case=8 ops=[0x0000FC00, 0x00000000] => 0x00000001 PASS
  [23/33] case=8 ops=[0x0000FC01, 0x00000000] => 0x00000002 PASS
  [24/33] case=8 ops=[0x00002026, 0x00000000] => 0x00000003 PASS
  [25/33] case=8 ops=[0x0000C202, 0x00000000] => 0x00000003 PASS
  [26/33] case=8 ops=[0x00000003, 0x00000000] => 0x00000004 PASS
  [27/33] case=8 ops=[0x000080E1, 0x00000000] => 0x00000004 PASS
  [28/33] case=9 ops=[0x00003C00, 0x00000000] => 0x00000010 PASS
  [29/33] case=9 ops=[0x00003E00, 0x00000000] => 0x00000018 PASS
  [30/33] case=9 ops=[0x00004200, 0x00000000] => 0x00000030 PASS
  [31/33] case=9 ops=[0x0000C400, 0x00000000] => 0x000000C0 PASS
  [32/33] case=9 ops=[0x00004240, 0x00000000] => 0x00000032 PASS
  [33/33] case=9 ops=[0x0000BF00, 0x00000000] => 0x000000E4 PASS

====== Result: 33/33 passed ======
```
