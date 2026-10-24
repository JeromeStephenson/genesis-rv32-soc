# Genesis-RV32-SoC

![SystemVerilog](https://img.shields.io/badge/Language-SystemVerilog-blue.svg)
![License](https://img.shields.io/badge/License-Apache%202.0-blue.svg)
![FreeRTOS](https://img.shields.io/badge/OS-FreeRTOS%20Compatible-orange.svg)

**Genesis-RV32-SoC** is a custom, from-scratch 32-bit RISC-V (RV32I) System-on-Chip designed to successfully boot and run **FreeRTOS**. Built entirely in SystemVerilog, it features a fully pipelined 5-stage CPU, comprehensive Machine-mode CSR support, and a standard SiFive-compatible peripheral ecosystem (CLINT, PLIC, UART, GPIO).

> **Repository Description:** A custom, from-scratch 32-bit RISC-V (RV32I) System-on-Chip in SystemVerilog. It features a 5-stage pipelined CPU, FreeRTOS boot support, and SiFive-compatible peripherals (CLINT, PLIC, UART, GPIO).

---

## 🌟 Key Features
- **ISA**: RV32I Base Integer Instruction Set (FENCE/FENCE.I treated as NOPs).
- **Microarchitecture**: 5-Stage In-Order Pipeline (IF, ID, EX, MEM, WB).
- **Advanced Hazard Resolution**: 
  - Full data forwarding (EX/MEM → ID, MEM/WB → ID, MEM Load → ID).
  - Load-Use stalling (1-cycle pipeline bubble).
  - **Conservative Store-to-Load hazard handling** (1-cycle stall to guarantee memory consistency).
  - **CSR RAW bypassing** to prevent pipeline stalls on consecutive CSR read/write operations.
- **Trap & Interrupt Handling**: Full Machine-mode exception and interrupt support with precise `mepc`, `mcause`, and `mtval` tracking.
- **FreeRTOS Ready**: Verified with FreeRTOS context switching, task scheduling, tick timer interrupts, and UART terminal output.

---

## 🧠 CPU Microarchitecture
- **Pipeline Stages**: IF → ID → EX → MEM → WB
- **Branch Resolution**: Resolved in the EX stage. Branch/Jump/Trap triggers an immediate IF/ID flush and PC redirection.
- **Bypass Network**: Multi-stage forwarding muxes select the most recent valid data for ALU operands, preventing unnecessary stalls.
- **CSR File**: Asynchronous reads with synchronous writes. Features a dedicated bypass network so that a CSR write in EX/MEM or MEM/WB can be immediately read by a subsequent instruction in the ID stage without stalling.

---

## ⚙️ Machine-Mode CSR Registers
The SoC implements a robust `csr_file` module supporting all essential Machine-mode (M-mode) registers required for OS-level context switching and trap handling:

| CSR Address | Name | Description |
|-------------|------|-------------|
| `0x300` | `mstatus` | Controls global interrupts (`MIE`) and saves previous state (`MPIE`) during traps. |
| `0x301` | `misa` | Reports ISA support (`0x4000_0100` for RV32I). |
| `0x304` | `mie` | Machine Interrupt Enable. Gates `MSIE`, `MTIE`, `MEIE`, and fast interrupts. |
| `0x305` | `mtvec` | Trap Vector Base Address. Supports both Direct (mode 0) and Vectored (mode 1) interrupt routing. |
| `0x340` | `mscratch` | Scratch register for trap handler software to temporarily store context. |
| `0x341` | `mepc` | Machine Exception Program Counter. Holds the address of the trapped or interrupted instruction. |
| `0x342` | `mcause` | Trap Cause. Encodes exceptions (e.g., `2`=Illegal Instr, `3`=EBREAK, `11`=Ecall) and interrupts (e.g., `3`=Software, `7`=Timer, `11`=External). |
| `0x343` | `mtval` | Trap Value. Holds the faulting instruction opcode or bad memory address. |
| `0x344` | `mip` | Machine Interrupt Pending. Reflects the current state of `MSIP`, `MTIP`, and `MEIP`. |
| `0xB00/0xB80`| `mcycle`/`mcycleh` | 64-bit cycle counter. |
| `0xB02/0xB82`| `minstret`/`minstreth`| 64-bit instruction retire counter. |
| `0xC01/0xC81`| `time`/`timeh` | Read-only shadow of the CLINT `MTIME` register. |

---

## ⏱️ CLINT (Core-Local Interruptor)
Located at `0x0200_0000`, the CLINT is the heartbeat of the FreeRTOS port, providing precise timing and inter-processor communication capabilities:

- **`MSIP` (`0x0000`)**: Machine Software Interrupt Pending. Writing `1` to bit 0 asserts `irq_software`, triggering a Machine Software Interrupt (Cause `3`). Used for yielding tasks.
- **`MTIMECMP` (`0x4000` / `0x4004`)**: A 64-bit Machine Timer Compare register. When `MTIME >= MTIMECMP`, the CLINT asserts the `irq_timer` signal to the core, triggering a Machine Timer Interrupt (Cause `7`). *Crucial for the FreeRTOS tick scheduler.*
- **`MTIME` (`0xBFF8` / `0xBFFC`)**: A free-running 64-bit real-time clock counter. It increments every clock cycle. Reads are combinationally mapped to the `time` CSR.

---

## 🔌 Peripheral Ecosystem
All peripherals follow the **SiFive Standard Address Map**, ensuring drop-in compatibility with standard RISC-V GCC toolchains and linker scripts.

1. **PLIC (Platform-Level Interrupt Controller)** @ `0x0C00_0000`
   - Supports 32 external interrupt sources.
   - Features per-source priority configuration, global threshold masking, and a Claim/Complete register for safe interrupt acknowledgment and nesting.
2. **UART** @ `0x1000_0000`
   - 8-N-1 TX/RX with a configurable baud rate generator (default 115200 @ 50MHz).
   - Status register indicates `tx_empty`, `rx_ready`, `tx_busy`, and `rx_busy`.
   - Generates interrupts on TX buffer empty or RX data ready.
3. **GPIO** @ `0x1000_1000`
   - 32-bit bidirectional pins with `DIR`, `OUT`, and `IN` registers.
   - Edge-detect interrupt controller with `IRQ_MASK` and **Write-1-to-Clear (W1C)** `IRQ_STAT` register.

---

## 🗺️ Memory Map
| Base Address | Size | Peripheral / Memory | Description |
|--------------|------|---------------------|-------------|
| `0x0000_0000`| 128KB| **IMEM** | Instruction Memory (Includes XIP read port for `.rodata` / `.srodata`) |
| `0x0200_0000`| 16MB | **CLINT** | Timer & Software Interrupts |
| `0x0C00_0000`| 2MB  | **PLIC** | External Interrupt Controller |
| `0x1000_0000`| 4KB  | **UART** | Serial Communication |
| `0x1000_1000`| 4KB  | **GPIO** | General Purpose I/O |
| `0x8000_0000`| 128KB| **DMEM** | Data Memory (SRAM) |

---

## 📂 Directory Structure

```text
genesis-rv32-soc/
├── rtl/
│   ├── core/             # 5-stage pipeline, hazard unit, CSR file, trap controller
│   ├── peripherals/      # CLINT, PLIC, UART, GPIO
│   ├── memory/           # IMEM and byte-masked DMEM
│   └── soc/              # Top-level SoC integration and address decoding
├── tb/                   # Testbenches (UART terminal monitor and PC trace logger)
├── sim/                  # Simulation scripts and Makefiles
├── docs/                 # Architecture diagrams and waveform captures
└── sw/                   # FreeRTOS port, linker scripts, and bare-metal examples
```

---

## 🛠️ Simulation & Running

The testbench (`tb/tb_soc.sv`) includes a behavioral UART receiver and instruction trace loggers, allowing you to debug FreeRTOS execution without requiring a physical FPGA.

### Prerequisites

- **SystemVerilog Simulator:** Verilator (recommended for open-source simulation), Siemens Questa, Synopsys VCS, or Cadence Xcelium.
- **RISC-V GNU Toolchain:** Required to compile C applications and FreeRTOS source code.

### 1. Compile the Software

Compile your FreeRTOS application or bare-metal C program using the RISC-V GNU toolchain.

For an RV32I target:

```bash
riscv64-unknown-elf-gcc \
    -march=rv32i \
    -mabi=ilp32 \
    -O2 \
    -o app.elf \
    startup.S main.c
```

Convert the ELF file into a binary if required by your memory initialization flow:

```bash
riscv64-unknown-elf-objcopy -O binary app.elf app.bin
```

Generate `imem.hex` and `dmem.hex` in the format expected by your SoC testbench. Place these files in the `sim/` directory or the project root, depending on your Makefile configuration.

> **Note:** The exact conversion procedure depends on your memory layout and the format expected by `$readmemh` or your memory initialization logic.

### 2. Run the Simulation

Navigate to the simulation directory and execute the appropriate Makefile target:

```bash
cd sim
make
```

Alternatively, if your Makefile defines a dedicated simulation target:

```bash
make sim
```

### 3. Analyze the Outputs

The testbench generates the following log files in the simulation directory:

| Log File | Description |
|---|---|
| `uart_output.log` | Captures ASCII characters transmitted through the UART TX pin, including FreeRTOS startup messages and task output. |
| `pc_trace.log` | Records the program counter (PC) of retired instructions for debugging execution flow and trap handling. |
| `stores.log` | Records memory write transactions, including addresses, data, and byte masks, to help investigate memory and stack corruption. |

### Simulation Timeout

The testbench includes a simulation timeout of **500 ms** to prevent infinite hangs:

```systemverilog
#500000000;
```

If your application requires more simulation time, adjust the timeout in `tb/tb_soc.sv`.

---

## 📜 FreeRTOS Porting Notes

To port FreeRTOS to Genesis-RV32-SoC, ensure the following components are correctly implemented:

- **Context Save/Restore:** Save and restore the required general-purpose registers and relevant CSRs, including `mstatus` and `mepc`, in `portASM.S`.
- **Trap Vector Setup:** Initialize `mtvec` to point to the appropriate trap handler during startup.
- **Tick Configuration:** Configure the CLINT-compatible timer registers to generate periodic machine timer interrupts for the FreeRTOS tick.
- **Interrupt Handling:** Preserve task context and return correctly from traps using `mret`.
- **Scheduler Startup:** Verify initial task stack initialization and context restoration.

---

## 📄 License

This project is licensed under the **Apache License 2.0**.

You are free to use, modify, and distribute this SoC design in accordance with the license terms, including for commercial and non-commercial purposes.

See the [`LICENSE`](LICENSE) file for full details.

---

**Built from scratch with precision.** If you find this project useful, consider starring ⭐ the repository!
> **Note:** The commands above are illustrative. FreeRTOS applications require the appropriate kernel source files, RISC-V port files, linker script, and startup code. The memory image generation process must match the SoC's instruction and data memory organization.

### 2. Run the Simulation

Navigate to the simulation directory and execute the appropriate Makefile target.

```bash
cd sim
make
```

If your Makefile provides a dedicated simulation target, use the corresponding command:

```bash
make sim
```

> **Note:** Replace these commands with the exact targets supported by your project's Makefile and simulator configuration.

### 3. Analyze the Outputs

The testbench generates three important log files in the simulation directory:

| Log File | Description |
|---|---|
| `uart_output.log` | Captures ASCII characters transmitted through the UART TX pin, including FreeRTOS `printf` output, startup messages, and task scheduler logs. |
| `pc_trace.log` | Records the program counter (PC) of successfully retired instructions, helping trace execution flow and investigate trap-vector or control-flow issues. |
| `stores.log` | Records memory write transactions, including address, data, and byte mask, making it useful for investigating stack corruption and data-memory issues. |

These logs help identify common problems such as unexpected jumps, incorrect trap handling, stack corruption, and failures during FreeRTOS scheduler startup.

### Simulation Timeout

The testbench includes a built-in **500 ms simulation timeout** using the delay:

```systemverilog
#500000000;
```

This prevents simulations from hanging indefinitely. If your FreeRTOS application needs more time to initialize or execute, adjust the timeout in `tb/tb_soc.sv` as needed.

---

## 📜 FreeRTOS Porting Notes

Porting FreeRTOS to **Genesis-RV32-SoC** requires a compatible RISC-V port and correct configuration of the processor's privileged architecture features and interrupt system.

### Key Porting Requirements

- **Context Save and Restore:** Implement context-switch routines in `portASM.S` to save and restore the required general-purpose registers (`x1`–`x31`), along with the relevant machine status and exception-return state. Use the appropriate CSR instructions, such as `csrrw`, `csrrs`, `csrrc`, `csrw`, and `csrr`, as required by the implementation.

- **Trap Vector Setup:** Initialize the `mtvec` CSR during startup so that exceptions and interrupts are directed to the appropriate trap handler.

- **Machine Timer Interrupts:** Configure the CLINT-compatible timer registers, including `mtime` and `mtimecmp` where implemented, to generate periodic machine timer interrupts for the FreeRTOS tick.

- **Interrupt Handling:** Ensure that the trap handler correctly distinguishes interrupts from exceptions, preserves the interrupted task's context, and returns using the appropriate mechanism, such as `mret`.

- **Scheduler Startup:** Verify that the initial task stack is correctly initialized and that the first context restore transfers control to the selected FreeRTOS task.

- **Memory and Linker Configuration:** Ensure that the linker script, stack layout, heap configuration, and memory regions match the SoC's implemented address map.

> **Debugging Tip:** If the processor repeatedly jumps to address `0x00000000` or restarts when the scheduler starts, inspect `pc_trace.log`, `stores.log`, the `mtvec` and `mepc` CSR values, and the initial task stack. These can help identify incorrect exception returns, invalid context restoration, or memory-mapping problems.

---

## 📄 License

This project is licensed under the **Apache License 2.0**.

You are free to use, modify, and distribute this SoC design for commercial and non-commercial purposes, subject to the terms and conditions of the license. Apache 2.0 also includes an express patent license.

See the [`LICENSE`](LICENSE) file for the complete license terms.

---

**Built from scratch with precision.** If you find this project useful, consider giving the repository a ⭐ star!
