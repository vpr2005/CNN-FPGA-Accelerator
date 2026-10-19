# CNN FPGA Accelerator: Performance & Synthesis Benchmark Report

## 1. Executive Benchmark Summary

The CNN FPGA Accelerator was synthesized using **AMD/Xilinx Vivado 2025.2** targeting the **Xilinx Artix-7 100T FPGA (`xc7a100tcsg324-1`)**. The architecture achieves an inference latency of **974 clock cycles** ($6.88\ \mu\text{s}$ at $F_{max} = 141.58\text{ MHz}$), delivering a real-time throughput of **145,359 Inferences per Second (FPS)** while consuming only **166 mW** total on-chip power.

---

## 2. Hardware Resource Utilization

| Resource | Used | Available | Utilization (%) | Function / Architectural Role |
|---|:---:|:---:|:---:|---|
| **DSP48E1 Slices** | **76** | 240 | **31.67%** | 36x Conv MACs (9 per filter) + 40x FC MACs (4 ch x 10 classes) |
| **Block RAM (RAMB18E1)** | **11** | 270 | **4.07%** | 1x Intermediate Feature RAM + 10x FC Weight ROMs |
| **Shift Register LUTs (SRLC32E)** | **16** | 19,000 | **0.08%** | 2-Line 2D Sliding Window Line Buffers |
| **Slice LUTs (Logic)** | **2,643** | 63,400 | **4.17%** | Control FSM, Pipelined Adder Trees, Pooling Logic |
| **Slice Registers (FF)** | **2,847** | 126,800 | **2.25%** | Pipeline registers for high-frequency timing closure |
| **CARRY4 Chains** | **500** | 15,850 | **3.15%** | Fast accumulators and comparator trees |

> [!NOTE]
> The design utilizes only ~32% of available DSP slices and ~4% of FPGA logic, leaving over 68% of the Artix-7 device available for system peripherals (MicroBlaze/Zynq PS, DMA controllers, Ethernet/PCIe cores).

---

## 3. Timing Closure & Maximum Frequency ($F_{max}$)

All timing constraints were strictly validated under worst-case industrial operating conditions.

- **Target Clock Period**: $10.000\text{ ns}$ ($100.000\text{ MHz}$)
- **Worst Negative Slack (WNS)**: **$+2.937\text{ ns}$** (Met with zero violations)
- **Total Negative Slack (TNS)**: **$0.000\text{ ns}$**
- **Worst Hold Slack (WHS)**: **$+0.223\text{ ns}$**
- **Minimum Resolvable Period**:
  $$T_{min} = T_{target} - \text{WNS} = 10.000\text{ ns} - 2.937\text{ ns} = \mathbf{7.063\text{ ns}}$$
- **Maximum Clock Frequency ($F_{max}$)**:
  $$F_{max} = \frac{1}{7.063\text{ ns}} = \mathbf{141.58\text{ MHz}}$$

---

## 4. Latency & Throughput Benchmark

| Metric | @ 100.0 MHz Target | @ 141.58 MHz ($F_{max}$) | Unit |
|---|:---:|:---:|:---:|
| **Clock Cycles per Inference** | **974** | **974** | Cycles |
| **Inference Latency** | **9.74** | **6.88** | $\mu\text{s}$ |
| **Throughput (Inferences / Sec)** | **102,669** | **145,359** | FPS |
| **Compute Workload per Frame** | **42,588** | **42,588** | Operations |
| **Effective Throughput (GOP/s)** | **4.37** | **6.19** | GOP/s |

---

## 5. Power Dissipation & Energy Efficiency

Reported via Vivado Vector-less Activity Propagation:

- **Total On-Chip Power**: **$0.166\text{ W}$ ($166\text{ mW}$)**
- **Dynamic Power**: **$0.081\text{ W}$ ($81\text{ mW}$)**
  - Clocks: $12\text{ mW}$
  - Logic & Signals: $16\text{ mW}$
  - DSP Slices: $42\text{ mW}$
  - BRAM: $11\text{ mW}$
- **Static Device Power**: **$0.084\text{ W}$ ($84\text{ mW}$)**
- **Energy Efficiency**:
  $$\text{Power Efficiency} = \frac{6.19\text{ GOP/s}}{0.166\text{ W}} = \mathbf{37.29\text{ GOP/s per Watt}}$$

---

## 6. Co-Verification Results

The hardware design underwent cycle-accurate co-simulation against a golden Python reference model (`python/cnn_model.py`):

```
=======================================================================
      CNN FPGA ACCELERATOR: HARDWARE / SOFTWARE CO-VERIFICATION       
=======================================================================
--- Checking MNIST_Digit_0 ---
  Hardware Predicted Class: 0  |  Golden Software Class: 0
  Hardware Max Logit Score: 16098 | Golden Max Logit Score: 16098
  Maximum Logit Error Delta: 0 (Exact 0-delta match across all 10 logits)
  Status: 100% BIT-ACCURATE PASS

--- Checking MNIST_Digit_1 ---
  Hardware Predicted Class: 1  |  Golden Software Class: 1
  Hardware Max Logit Score: 18834 | Golden Max Logit Score: 18834
  Maximum Logit Error Delta: 0 (Exact 0-delta match across all 10 logits)
  Status: 100% BIT-ACCURATE PASS
```
