// =============================================================================
// 核心信息：整个调试链如何打通（务必先读）
// =============================================================================
// CPU 不是独立芯片 —— 它是用 Verilog 写的"软核"，和本模块一起烧在同一颗
// FPGA 里。DebugController 通过信号线直接连到 CPU 内部（halt/step/reset、
// 寄存器地址/数据、内存地址/数据），相当于把 CPU 的血管全拉出来接到了一个
// 监控面板上。
//
// === 物理拓扑（三层递进） ====================================================
//
//   你的电脑 (Host)                 FPGA 芯片内部
//   ┌─────────────────┐          ┌──────────────────────────────┐
//   │ Python 脚本      │  USB转   │                              │
//   │ (发原始二进制字节) │──串口线──▶ GPIO引脚 ──▶  UartRx        │
//   │                  │          │                  │           │
//   │ 打印寄存器值      │◀─────────│── UartTx  ◀── DebugController│
//   │ "r3 = 0xDEAD"   │  串口线   │    │                         │
//   │                  │          │    │ 直接信号线(不走总线)      │
//   └─────────────────┘          │    ▼                         │
//                                 │  CPU (Verilog 软核)          │
//                                 │  - PC, 寄存器堆              │
//                                 │  - 指令内存 (uram)           │
//                                 │  - 数据内存 (uram)           │
//                                 └──────────────────────────────┘
//
//   三层递进：
//   第1层 物理 — USB转串口芯片把电平打通（通常 CH340/CP2102）
//   第2层 字节 — UartRx/UartTx 纯硬件把串行信号拼成字节（无驱动、无OS）
//   第3层 命令 — 本模块把字节翻译成 CPU 控制信号，再把结果打包发回
//
// === 开发板操作流程 (Python 示例) ============================================
//
//   串口参数：115200, 8N1 (8数据位, 无校验, 1停止位)，RAW 模式（非 ASCII 终端）
//
//   import serial
//   ser = serial.Serial('/dev/ttyUSB0', 115200, timeout=0.5)  # Linux/Mac
//   # ser = serial.Serial('COM3', 115200, timeout=0.5)        # Windows
//
//   # ---- 步骤1: 测试连通性 ----
//   ser.write(b'\x00')          # CMD_PING
//   assert ser.read(1)[0] == 0x80   # 期望 RESP_PONG (0x80)
//
//   # ---- 步骤2: 暂停 CPU ----
//   ser.write(b'\x03')          # CMD_HALT
//   assert ser.read(1)[0] == 0x81   # 期望 ACK (0x81)
//
//   # ---- 步骤3: 读寄存器 ----
//   ser.write(b'\x21\x03')      # CMD_READ_REG + 寄存器3
//   resp = ser.read(5)          # 读 5 字节: 0x82 + 4字节大端
//   assert resp[0] == 0x82      # 确认是 DATA32
//   val = int.from_bytes(resp[1:5], 'big')
//   print(f"x3 = 0x{val:08X}")
//
//   # ---- 步骤4: 单步一条指令 ----
//   ser.write(b'\x04')          # CMD_STEP
//   assert ser.read(1)[0] == 0x81
//   ser.write(b'\x22')          # CMD_READ_PC (看PC变了没)
//   pc_bytes = ser.read(5)
//   pc = int.from_bytes(pc_bytes[1:5], 'big')
//   print(f"PC = 0x{pc:08X}")
//
//   # ---- 步骤5: 恢复运行 ----
//   ser.write(b'\x02')          # CMD_RUN
//   assert ser.read(1)[0] == 0x81
//
//   # ---- 读/写数据内存 ----
//   import struct
//   addr = 0x00001000
//   ser.write(b'\x24' + struct.pack('>I', addr))  # CMD_READ_DMEM + 大端地址
//   data_resp = ser.read(5)
//   data = int.from_bytes(data_resp[1:5], 'big')
//
//   ser.write(b'\x41' + struct.pack('>I', addr) + struct.pack('>I', 0xDEADBEEF))
//   assert ser.read(1)[0] == 0x81
//
// === 每次命令的响应字节数速查 ==================================================
//   PING           → 1  (PONG)
//   RESET/RUN/HALT/STEP → 1  (ACK)
//   READ_REG       → 5  (DATA32 + 4B)
//   READ_PC        → 5
//   READ_INST      → 5
//   READ_DMEM      → 5
//   WRITE_INST     → 1  (ACK)
//   WRITE_DMEM     → 1  (ACK)
//   未知命令        → 2  (ERR + 0x01)
//
// === 注意事项 ================================================================
//   - 上电/复位后 CPU 默认进入 halt 状态，必须发 RUN(0x02) 才会开始跑
//   - 写内存时 CPU 必须处于 halt 状态，否则可能和 CPU 访问冲突
//   - 内存读写有 20 个 100MHz 周期延迟（~200ns），但 UART 一字节 ~87μs，
//     正常发命令完全不需要额外 delay，发完直接 read() 即可
//   - 串口通信是原始二进制字节，不是 ASCII，PyCharm/VSCode 的串口终端插件
//     可能显示乱码——用 Python 脚本调试，别用串口助手看
//   - 如果是 Windows，装 CH340/CP2102 驱动后去设备管理器看 COM 号
//   - read() 前设置 timeout，否则响应丢了会卡死
// =============================================================================

// -----------------------------------------------------------------------------
// Module      : DebugController.v
// Author      : Yuhui Bai
// Description : Debug UART command controller
// -----------------------------------------------------------------------------
//
// ================================ 技术参考 ====================================
// 【功能】CPU 硬件调试控制器 —— 通过 UART 接收 Host（上位机）命令，操控 CPU 的
//        暂停/运行/单步，以及读写 CPU 内部的寄存器、指令内存、数据内存。
//
// 【在项目中的定位】
//   这个模块是整个调试链的"大脑"：
//
//     Host（上位机）                  FPGA 内部
//   ┌──────────┐    UART     ┌─────────────────┐    信号线    ┌──────────┐
//   │ 调试工具  │──(串口)──▶  │ UartRx           │             │          │
//   │ (PuTTY/  │            │   │   DebugController│──halt/step/──▶  CPU    │
//   │  Python) │◀──(串口)──  │   │◀─────┼─────────▶│  reset     │  (被调试)  │
//   └──────────┘            │ UartTx           │ reg/inst/dmem│          │
//                            └─────────────────┘◀──────────▶└──────────┘
//
//   相当于硬件版的 GDB-Server。
//
// 【通信协议】
//   一条命令 = 1 字节命令码 + N 字节参数(payload)
//   一条响应 = 1 字节响应码 + M 字节数据(可选)
//
//   --- 命令表 ---
//   码    | 名称       | Payload | 功能
//   0x00  | PING       | 0 字节  | 心跳检测，返回 PONG
//   0x01  | RESET      | 0 字节  | 复位 CPU（同时进入 halt 状态）
//   0x02  | RUN        | 0 字节  | CPU 全速运行
//   0x03  | HALT       | 0 字节  | CPU 暂停
//   0x04  | STEP       | 0 字节  | 单步执行一条指令
//   0x21  | READ_REG   | 1 字节  | 读寄存器（参数：5-bit 寄存器编号）
//   0x22  | READ_PC    | 0 字节  | 读程序计数器 PC
//   0x23  | READ_INST  | 4 字节  | 读指令内存（参数：32-bit 字节地址）
//   0x24  | READ_DMEM  | 4 字节  | 读数据内存（参数：32-bit 字节地址）
//   0x40  | WRITE_INST | 8 字节  | 写指令内存（4B地址 + 4B数据）
//   0x41  | WRITE_DMEM | 8 字节  | 写数据内存（4B地址 + 4B数据）
//
//   --- 响应码 ---
//   码    | 名称       | 后面跟的数据
//   0x80  | PONG       | 无
//   0x81  | ACK        | 无
//   0x82  | DATA32     | 4 字节大端 32-bit 数据
//   0xFF  | ERR        | 1 字节错误码 (0x01=未知命令)
//
// 【状态机流程】
//   S_IDLE ──收到命令码──▶ S_RECV_PAYLOAD ──收齐参数──▶ S_EXECUTE
//       ▲                                                  │
//       │                      ┌───────────────────────────┤
//       │                      │ (无等待)                  │ (需要跨时钟域等待)
//       │                      ▼                           ▼
//       │                S_SEND_RESP ──▶ S_SEND_WAIT    S_MEM_WAIT(等20周期)
//       │                      │             │              │
//       └──全部字节发完────────┘             └──单字节发完──┘(循环下一字节)
//
//   S_MEM_WAIT 的设计原因：系统时钟 100MHz，但 CPU 内部 uram 跑在 25MHz。
//   跨时钟域访问需要等待 20 个 100MHz 周期来保证数据稳定。虽然寄存器应该是
//   组合逻辑读（无需等待），但为了稳健也统一加了 MEM_WAIT_CYCLES。
//
// 【CPU 控制逻辑 (cpu_step 信号)】
//   - 非 halt 状态(cpu_halt=0)：cpu_step 恒为 1，CPU 全速运行
//   - halt 状态(cpu_halt=1)：
//       * 收到 STEP 命令 → 内部计数器 step_countdown 从 4 倒数到 0，
//         这期间 cpu_step=1，刚好覆盖一个 25MHz 时钟周期，完成一条指令
//       * counter 到 0 后 cpu_step=0，CPU 再次暂停
//    这种设计避免了"一个 100MHz 脉冲太窄，CPU 来不及反应"的问题。
//
// 【接口信号组】
//   UART 侧：rx_data, rx_valid (来自 UartRx) ｜ tx_data, tx_start, tx_busy (去 UartTx)
//   CPU 控制：cpu_halt, cpu_step, cpu_reset
//   寄存器调试：dbg_reg_addr(5bit) / dbg_reg_data(32bit)
//   指令内存调试：inst_dbg_en, inst_wr_en, inst_dbg_addr, inst_wr_data / inst_rd_data
//   数据内存调试：dmem_dbg_en, dmem_wr_en, dmem_dbg_addr, dmem_wr_data / dmem_rd_data
//   PC 读取：dbg_pc(32bit)
// ========================================================================
`timescale 1ns / 1ps

module DebugController (
    input        clk,       // 100MHz system clock
    input        rst_n,      // Active-low reset

    // UART interface
    input [7:0]  rx_data,
    input        rx_valid,
    output reg  [7:0]  tx_data,
    output reg         tx_start,
    input        tx_busy,

    // CPU control
    output reg         cpu_halt,
    output reg         cpu_step,      // Single-step pulse signal
    output reg         cpu_reset,

    // Debug: register read
    output reg  [4:0]  dbg_reg_addr,
    input [31:0] dbg_reg_data,

    // Debug: instruction memory
    output reg         inst_dbg_en,    // 1=debug access
    output reg         inst_wr_en,     // 1=write enable
    output reg  [31:0] inst_dbg_addr,  // byte address
    output reg  [31:0] inst_wr_data,   // write data
    input [31:0] inst_rd_data,   // read data (instruction)

    // Debug: data memory
    output reg         dmem_dbg_en,    // 1=debug access
    output reg         dmem_wr_en,     // 1=write enable
    output reg  [31:0] dmem_dbg_addr,  // byte address
    output reg  [31:0] dmem_wr_data,   // write data
    input [31:0] dmem_rd_data,   // read data

    // Debug: PC
    input [31:0] dbg_pc
);

    // ================================
    // Command code definitions
    // ================================
    localparam CMD_PING       = 8'h00;
    localparam CMD_RESET      = 8'h01;
    localparam CMD_RUN        = 8'h02;
    localparam CMD_HALT       = 8'h03;
    localparam CMD_STEP       = 8'h04;    // Single-step
    localparam CMD_READ_REG   = 8'h21;
    localparam CMD_READ_PC    = 8'h22;
    localparam CMD_READ_INST  = 8'h23;
    localparam CMD_READ_DMEM  = 8'h24;
    localparam CMD_WRITE_INST = 8'h40;
    localparam CMD_WRITE_DMEM = 8'h41;

    // Response code definitions
    localparam RESP_PONG   = 8'h80;
    localparam RESP_ACK    = 8'h81;
    localparam RESP_DATA32 = 8'h82;
    localparam RESP_ERR    = 8'hFF;

    // ================================
    // State machine
    // ================================
    localparam S_IDLE         = 4'd0;
    localparam S_RECV_PAYLOAD = 4'd1;
    localparam S_EXECUTE      = 4'd2;
    localparam S_SEND_RESP    = 4'd3;
    localparam S_SEND_WAIT    = 4'd4;
    localparam S_MEM_WAIT     = 4'd5;

    reg [3:0]  state;
    reg [7:0]  cmd_reg;
    reg [3:0]  payload_cnt;      // received payload bytes
    reg [3:0]  payload_need;     // needed payload bytes
    reg [7:0]  payload [0:7];    // payload buffer (max 8 bytes: WRITE_INST addr[4]+data[4])
    reg [3:0]  step_countdown;   // Step counter: multiple cycles to cover one 25MHz period

    reg [31:0] resp_data;        // 32-bit data to send
    reg [2:0]  resp_len;         // response total length (incl. code)
    reg [2:0]  resp_idx;         // current send byte index
    reg [7:0]  resp_buf [0:4];   // response buffer

    // Memory read wait counter (cross clock domain: 100MHz → 25MHz uram)
    // uram at 25MHz needs 1 cycle to output data = 4 cycles at 100MHz
    // Write needs signal stable for at least one full 25MHz rising edge, use 20 cycles for margin
    localparam MEM_WAIT_CYCLES = 5'd20;
    localparam STEP_COUNTDOWN_INIT = 4'd4;  // Step pulse width (100MHz cycles), adjust to cover one 25MHz period
    reg [4:0]  mem_wait_cnt;

    // Get payload length for each command
    function [3:0] cmd_payload_len;
        input [7:0] cmd;
        begin
            case (cmd)
                CMD_PING:       cmd_payload_len = 0;
                CMD_RESET:      cmd_payload_len = 0;
                CMD_RUN:        cmd_payload_len = 0;
                CMD_HALT:       cmd_payload_len = 0;
                CMD_STEP:       cmd_payload_len = 0;  // Single-step
                CMD_READ_REG:   cmd_payload_len = 1;  // regnum[1B]
                CMD_READ_PC:    cmd_payload_len = 0;
                CMD_READ_INST:  cmd_payload_len = 4;  // addr[4B]
                CMD_READ_DMEM:  cmd_payload_len = 4;  // addr[4B]
                CMD_WRITE_INST: cmd_payload_len = 8;  // addr[4B] + data[4B]
                CMD_WRITE_DMEM: cmd_payload_len = 8;  // addr[4B] + data[4B]
                default:        cmd_payload_len = 0;
            endcase
        end
    endfunction

    // Main state machine
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state        <= S_IDLE;
            cmd_reg      <= 0;
            payload_cnt  <= 0;
            payload_need <= 0;
            cpu_halt     <= 1'b0;
            cpu_step     <= 1'b0;
            step_countdown <= 4'b0000;
            cpu_reset    <= 1'b0;
            dbg_reg_addr <= 0;
            inst_dbg_en  <= 0;
            inst_wr_en   <= 0;
            inst_dbg_addr <= 0;
            inst_wr_data <= 0;
            dmem_dbg_en  <= 0;
            dmem_wr_en   <= 0;
            dmem_dbg_addr <= 0;
            dmem_wr_data <= 0;
            mem_wait_cnt <= 0;
            tx_data      <= 0;
            tx_start     <= 0;
            resp_len     <= 0;
            resp_idx     <= 0;
        end else begin
            tx_start    <= 1'b0;
            cpu_reset   <= 1'b0;
            inst_dbg_en  <= 1'b0;
            inst_wr_en   <= 1'b0;
            dmem_dbg_en  <= 1'b0;
            dmem_wr_en   <= 1'b0;
            
            // cpu_step logic:
            // If not halt mode, allow CPU to run normally (cpu_step=1)
            // If halt and step_countdown > 0, allow single-step (cpu_step=1)
            // Otherwise pause CPU (cpu_step=0)
            if (!cpu_halt) begin
                cpu_step <= 1'b1;  // Normal run mode
            end else if (step_countdown > 0) begin
                cpu_step <= 1'b1;  // Single-step pulse
                step_countdown <= step_countdown - 1;  // Countdown
            end else begin
                cpu_step <= 1'b0;  // Pause mode
            end

            case (state)
                // =============================================================
                S_IDLE: begin
                    if (rx_valid) begin
                        cmd_reg      <= rx_data;
                        payload_need <= cmd_payload_len(rx_data);
                        payload_cnt  <= 0;
                        if (cmd_payload_len(rx_data) == 0) begin
                            state <= S_EXECUTE;
                        end else begin
                            state <= S_RECV_PAYLOAD;
                        end
                    end
                end

                // =============================================================
                S_RECV_PAYLOAD: begin
                    if (rx_valid) begin
                        payload[payload_cnt] <= rx_data;
                        if (payload_cnt + 1 == payload_need) begin
                            state <= S_EXECUTE;
                        end
                        payload_cnt <= payload_cnt + 1;
                    end
                end

                // =============================================================
                S_EXECUTE: begin
                    case (cmd_reg)
                        CMD_PING: begin
                            resp_buf[0] <= RESP_PONG;
                            resp_len    <= 1;
                            resp_idx    <= 0;
                            state       <= S_SEND_RESP;
                        end

                        CMD_RESET: begin
                            cpu_halt    <= 1'b1;
                            cpu_reset   <= 1'b1;
                            step_countdown <= 4'b0000;    // Clear step
                            resp_buf[0] <= RESP_ACK;
                            resp_len    <= 1;
                            resp_idx    <= 0;
                            state       <= S_SEND_RESP;
                        end

                        CMD_RUN: begin
                            cpu_halt    <= 1'b0;
                            step_countdown <= 4'b0000;    // Clear step
                            resp_buf[0] <= RESP_ACK;
                            resp_len    <= 1;
                            resp_idx    <= 0;
                            state       <= S_SEND_RESP;
                        end

                        CMD_HALT: begin
                            cpu_halt    <= 1'b1;
                            step_countdown <= 4'b0000;    // Clear step
                            resp_buf[0] <= RESP_ACK;
                            resp_len    <= 1;
                            resp_idx    <= 0;
                            state       <= S_SEND_RESP;
                        end

                        CMD_STEP: begin
                            cpu_halt    <= 1'b1;    // Keep paused
                            step_countdown <= STEP_COUNTDOWN_INIT;    // Use parameterized step pulse width
                            resp_buf[0] <= RESP_ACK;
                            resp_len    <= 1;
                            resp_idx    <= 0;
                            state       <= S_SEND_RESP;
                        end

                        CMD_READ_REG: begin
                            dbg_reg_addr <= payload[0][4:0];
                            // Register is combinational read, but still need to wait for cross-clock domain stability
                            mem_wait_cnt <= MEM_WAIT_CYCLES;
                            state        <= S_MEM_WAIT;
                        end

                        CMD_READ_PC: begin
                            resp_buf[0] <= RESP_DATA32;
                            resp_buf[1] <= dbg_pc[31:24];
                            resp_buf[2] <= dbg_pc[23:16];
                            resp_buf[3] <= dbg_pc[15:8];
                            resp_buf[4] <= dbg_pc[7:0];
                            resp_len    <= 5;
                            resp_idx    <= 0;
                            state       <= S_SEND_RESP;
                        end

                        CMD_READ_INST: begin
                            inst_dbg_addr <= {payload[0], payload[1], payload[2], payload[3]};
                            inst_dbg_en   <= 1'b1;
                            inst_wr_en    <= 1'b0;
                            mem_wait_cnt  <= MEM_WAIT_CYCLES;
                            state         <= S_MEM_WAIT;
                        end

                        CMD_WRITE_INST: begin
                            inst_dbg_addr <= {payload[0], payload[1], payload[2], payload[3]};
                            inst_wr_data  <= {payload[4], payload[5], payload[6], payload[7]};
                            inst_dbg_en   <= 1'b1;
                            inst_wr_en    <= 1'b1;
                            mem_wait_cnt  <= MEM_WAIT_CYCLES;
                            state         <= S_MEM_WAIT;
                        end

                        CMD_READ_DMEM: begin
                            dmem_dbg_addr <= {payload[0], payload[1], payload[2], payload[3]};
                            dmem_dbg_en   <= 1'b1;
                            dmem_wr_en    <= 1'b0;
                            mem_wait_cnt  <= MEM_WAIT_CYCLES;
                            state         <= S_MEM_WAIT;
                        end

                        CMD_WRITE_DMEM: begin
                            dmem_dbg_addr <= {payload[0], payload[1], payload[2], payload[3]};
                            dmem_wr_data  <= {payload[4], payload[5], payload[6], payload[7]};
                            dmem_dbg_en   <= 1'b1;
                            dmem_wr_en    <= 1'b1;
                            mem_wait_cnt  <= MEM_WAIT_CYCLES;
                            state         <= S_MEM_WAIT;
                        end

                        default: begin
                            resp_buf[0] <= RESP_ERR;
                            resp_buf[1] <= 8'h01; // unknown command
                            resp_len    <= 2;
                            resp_idx    <= 0;
                            state       <= S_SEND_RESP;
                        end
                    endcase
                end

                // =============================================================
                // Wait for memory/register read result (multi-cycle delay, cross clock domain)
                S_MEM_WAIT: begin
                    // Keep signal high, override default clear
                    if (cmd_reg == CMD_READ_INST || cmd_reg == CMD_WRITE_INST) begin
                        inst_dbg_en <= 1'b1;
                        if (cmd_reg == CMD_WRITE_INST)
                            inst_wr_en <= 1'b1;
                    end
                    if (cmd_reg == CMD_READ_DMEM || cmd_reg == CMD_WRITE_DMEM) begin
                        dmem_dbg_en <= 1'b1;
                        if (cmd_reg == CMD_WRITE_DMEM)
                            dmem_wr_en <= 1'b1;
                    end

                    if (mem_wait_cnt > 0) begin
                        mem_wait_cnt <= mem_wait_cnt - 1;
                    end else begin
                        // Wait done, sample data or finish write
                        if (cmd_reg == CMD_READ_REG) begin
                            resp_buf[0] <= RESP_DATA32;
                            resp_buf[1] <= dbg_reg_data[31:24];
                            resp_buf[2] <= dbg_reg_data[23:16];
                            resp_buf[3] <= dbg_reg_data[15:8];
                            resp_buf[4] <= dbg_reg_data[7:0];
                            resp_len    <= 5;
                            resp_idx    <= 0;
                        end else if (cmd_reg == CMD_READ_INST) begin
                            resp_buf[0] <= RESP_DATA32;
                            resp_buf[1] <= inst_rd_data[31:24];
                            resp_buf[2] <= inst_rd_data[23:16];
                            resp_buf[3] <= inst_rd_data[15:8];
                            resp_buf[4] <= inst_rd_data[7:0];
                            resp_len    <= 5;
                            resp_idx    <= 0;
                        end else if (cmd_reg == CMD_WRITE_INST) begin
                            inst_wr_en  <= 1'b0;
                            resp_buf[0] <= RESP_ACK;
                            resp_len    <= 1;
                            resp_idx    <= 0;
                        end else if (cmd_reg == CMD_READ_DMEM) begin
                            resp_buf[0] <= RESP_DATA32;
                            resp_buf[1] <= dmem_rd_data[31:24];
                            resp_buf[2] <= dmem_rd_data[23:16];
                            resp_buf[3] <= dmem_rd_data[15:8];
                            resp_buf[4] <= dmem_rd_data[7:0];
                            resp_len    <= 5;
                            resp_idx    <= 0;
                        end else if (cmd_reg == CMD_WRITE_DMEM) begin
                            dmem_wr_en  <= 1'b0;
                            resp_buf[0] <= RESP_ACK;
                            resp_len    <= 1;
                            resp_idx    <= 0;
                        end
                        state <= S_SEND_RESP;
                    end
                end

                // =============================================================
                S_SEND_RESP: begin
                    if (!tx_busy) begin
                        tx_data  <= resp_buf[resp_idx];
                        tx_start <= 1'b1;
                        state    <= S_SEND_WAIT;
                    end
                end

                // =============================================================
                S_SEND_WAIT: begin
                    // Wait for current byte to finish sending
                    if (!tx_busy && !tx_start) begin
                        if (resp_idx + 1 == resp_len) begin
                            state <= S_IDLE;
                        end else begin
                            resp_idx <= resp_idx + 1;
                            state    <= S_SEND_RESP;
                        end
                    end
                end

                default: state <= S_IDLE;
            endcase
        end
    end

endmodule
