# Technical Roadmap & Call for Hardware Engineers

> **We are building a pure hardware-based co-processor for abstract AI logic.**
>
> **This is an open call for ASIC, FPGA, and RISC-V engineers to make history and break the cloud monopoly.**

---

## 🎯 The Engineering Challenge

How do we wire the core mathematics of neural networks — matrix multiplication, attention mechanisms, and feed-forward transformations — directly into silicon blocks using open-source tools (Verilog / VHDL / SystemVerilog)?

The OCCP chip is not a general-purpose GPU. It is a **domain-specific accelerator** (DSA) that hardwires the *abstract structure* of intelligence into silicon. We are not storing encyclopedias of data; we are etching the *rules of reasoning* themselves.

---

## 🗺️ Planned IP Blocks

The chip architecture is divided into modular IP blocks. Each block can be developed independently and later integrated into the full system. Pick the one that matches your expertise and passion.

### 1. Math Core Block (ALU / FPU / Matrix Engine)
**Status:** 🔴 Needs Lead Engineer  
**Priority:** Critical

- Hardware acceleration for fixed-point and quantized matrix operations (INT4 / INT8 / BF16).
- Systolic array or SIMD-style datapath for matrix-vector and matrix-matrix multiplication.
- Support for common activation functions (ReLU, GELU, SiLU) as hardwired lookup tables or piecewise linear approximators.
- Target: Match or exceed the throughput of a mid-range GPU core at 1/100th the power.

**Skills needed:** Digital design, arithmetic circuits, low-precision quantization, FPGA prototyping.

---

### 2. Logic & Topology Block (Transformer Architecture)
**Status:** 🔴 Needs Lead Engineer  
**Priority:** Critical

- Direct logic-gate implementation of transformer building blocks:
  - **Self-Attention mechanism:** Query-Key-Value (QKV) projection, softmax approximation in hardware, attention-score computation.
  - **Feed-Forward Network (FFN):** Two-layer MLP with hardwired weights or embedded weight banks.
  - **Positional Encoding:** Sinusoidal or learned position embeddings as fixed ROM tables.
- Design must be **parameterizable** (number of heads, head dimension, sequence length) to allow reuse across model families.

**Skills needed:** Deep understanding of transformer architectures, RTL design, memory hierarchy design.

---

### 3. Bus Interface Block (CPU Bridge)
**Status:** 🟡 Needs Reviewers  
**Priority:** High

- Open-source standard interface (e.g., **AMBA AXI4** or **TileLink**) to bridge this co-processor with the host system.
- Must support both **RISC-V** (as the primary open target) and **x86** (for market compatibility) host CPUs.
- DMA engine for zero-copy data transfer between host RAM and the co-processor's local scratchpad memory.
- Interrupt handling and power-management signaling (clock gating, sleep modes).

**Skills needed:** SoC integration, bus protocols (AXI / TileLink), low-level driver concepts.

---

### 4. Memory Subsystem (Scratchpad + Weight Banks)
**Status:** 🔴 Needs Lead Engineer  
**Priority:** High

- On-chip SRAM / eFlash banks to store the "hardwired knowledge weights" (the 80% fixed core).
- Small, ultra-fast scratchpad for intermediate activations during inference.
- Memory controller optimized for the sparse, structured access patterns of transformer inference.
- Optional: Explore **Compute-in-Memory (CIM)** or **analog memristor arrays** for the research frontier.

**Skills needed:** Memory design, SRAM compilers, low-power circuit techniques.

---

### 5. Personalization Interface (Adaptive Synapses)
**Status:** 🟡 Research Phase  
**Priority:** Medium

- Lightweight interface to load user-specific adaptation weights from host SSD into a small reconfigurable region (RRAM / eFPGA overlay).
- Secure enclave logic to encrypt/decrypt the user's personal weight file on-chip.
- Ensures the "hardwired core" remains immutable while the "personal layer" stays flexible.

**Skills needed:** Embedded security, cryptography hardware, reconfigurable computing.

---

## 🔧 Development Workflow

We follow a **simulation-first, FPGA-second, silicon-third** approach to keep the barrier to entry low.

| Stage | Tooling | Goal |
|---|---|---|
| **1. Algorithmic Modeling** | Python (NumPy / PyTorch) | Validate the math and dataflow before writing RTL. |
| **2. RTL Design** | Verilog / SystemVerilog / VHDL | Synthesize the algorithm into clocked digital logic. |
| **3. Simulation & Verification** | Verilator, Icarus Verilog, cocotb | Prove correctness with testbenches and formal methods. |
| **4. FPGA Prototyping** | Xilinx Vivado / AMD Vitis, Intel Quartus, Yosys + nextpnr | Run real inference on affordable dev boards (Arty A7, Alveo, etc.). |
| **5. Tapeout Preparation** | OpenLane / SkyWater PDK 130nm (or commercial foundry) | Generate GDSII for silicon fabrication. |

---

## 💎 Why Join Us?

### For Your Career & Portfolio
- **Ultimate Portfolio Piece:** Your RTL code will be public under CERN-OHL-W, permanently proving your skills in modern AI hardware acceleration to any future employer.
- **Academic & Industry Impact:** You will be cited as a founding contributor to an open ecosystem that no big-tech company can steal or close.
- **Skill Growth:** Work at the intersection of deep learning, computer architecture, and silicon design — the hottest skill stack of the decade.

### For the Mission
- **Break the Cloud Monopoly:** Help build the chip that makes local, private, subscription-free AI a reality for billions of people.
- **Pure Silicon Innovation:** Solve the power-consumption and memory-bottleneck crisis of local AI inference through hardware elegance, not brute force.
- **Democratize Intelligence:** Ensure that a student in a remote village has the same cognitive tools as an engineer in Silicon Valley.

---

## 🚀 How to Get Started (Right Now)

1. **Read the main README** to understand the full vision: [README.md](./README.md)
2. **Open an Issue** describing which IP block you want to lead or contribute to.
3. **Fork the repo**, create a branch, and start drafting:
   - A one-page architecture document (Markdown or Google Docs link).
   - A simple Python model of the algorithm you plan to hardwire.
   - Or a Verilog module with a basic testbench.
4. **Join the discussion** in GitHub Discussions or the community channels listed in the main README.

---

## 📋 Contribution Guidelines

- All RTL code must include a **cocotb or Verilator testbench** before merging.
- Document your design decisions in Markdown files inside the `/docs` folder.
- Use English for all code comments and technical documentation (Arabic welcome for community posts).
- Respect the CERN-OHL-W license: any contribution you make remains open forever.

---

## 🏆 Recognition

Every contributor who lands a merged PR will be:
- Listed in the `CONTRIBUTORS.md` file.
- Credited in the project's academic and technical publications.
- Invited to the founding contributors' channel for strategic decisions.

---

<div align="center">

**👉 Open an Issue or a Pull Request and let's start drafting the architecture!**

**The silicon revolution begins with a single gate.**

</div>
