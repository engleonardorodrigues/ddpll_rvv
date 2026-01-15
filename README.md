# DDPLL RISC-V Vector (RVV) Implementation

This repository contains a high-performance implementation of a **Decision-Directed Phase-Locked Loop (DDPLL)** for phase recovery in communication systems (**QPSK**), written entirely in **RISC-V Assembly** using the **RVV 1.0 vector extension**.

The project demonstrates the use of **parallel (SIMD) processing** for DSP algorithms, integrating **C code (testbench)** with highly optimized **Assembly routines**.

---

## 📋 Features

- **Architecture:** RISC-V 64-bit (RV64GCV)
- **Modulation:** QPSK (Quadrature Phase Shift Keying)
- **Algorithm:** Decision-Directed PLL (DDPLL) with pilot symbol support

### Optimizations
- Extensive use of vector instructions (`vle32`, `vfmul`, `vfadd`, etc.)
- Trigonometric function approximation (sine/cosine) using **Taylor Series**, avoiding slow library calls
- Dynamic stack-based memory allocation for the loop filter
- Strict compliance with the **RISC-V ABI** (callee-saved register preservation)

---

## 📂 Project Structure

- **`ddpll_rvv.s`**  
  Core DDPLL algorithm implemented in RISC-V Assembly. Includes rotation, symbol decision, phase error computation, and loop filter logic.

- **`main.c`**  
  C-based testbench. Generates test signals with synthetic phase error, calls the assembly routine, and validates the results.

---

## 🛠️ Prerequisites

To build and run this project, you will need:

- **RISC-V GCC toolchain** with vector extension support  
  (e.g., `riscv64-unknown-elf-gcc`)
- **QEMU (User Mode)** to execute RISC-V binaries on x86/x64 systems  
  (e.g., `qemu-riscv64`)

---

## 🚀 Build and Run

Use the commands below to compile the code.  
Make sure the vector extension (`v`) is enabled in the architecture flags.
