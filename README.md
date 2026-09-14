# uart

UART RX/TX IP (`rtl/uart_rx.sv`, `rtl/uart_tx.sv`) plus an AXI4-Lite MMIO top (`rtl/uart_axil.sv`) for ASIC/SoC integration.

The FPGA demo (`dv/module/uart2seg.sv`) is a board test harness (7-seg, `$readmemb`). Use `uart_axil` as the synthesizable SoC top.

## AXI4-Lite top (`uart_axil`)

Single clock domain: `i_clk` / `i_rst_n` (active-low async reset) shared by AXI and UART.

| Port group | Widths | Notes |
| --- | --- | --- |
| Clock / reset | — | `i_clk`, `i_rst_n` |
| AXI4-Lite slave | addr `ADDR_WIDTH` (default **8**), data **32**, strobe **4**, resp **2**, prot **3** (ignored) | Byte offset into this block |
| UART pins | 1 | `o_tx`, `i_rx` (idle-high) |

Default baud parameters match the existing cores: `CLK_FREQ_MHZ=50`, `BAUD_RATE=115200`, 8N1.

### Register map

Word-aligned offsets. Address bits `[1:0]` are ignored. Mapped accesses return **OKAY**. Offsets other than the four registers return **DECERR**.

| Offset | Name | Access | Description |
| --- | --- | --- | --- |
| `0x00` | STATUS | RO | `[0]` RX_VALID — RX FIFO has a byte. `[1]` TX_READY — TX FIFO not full. |
| `0x04` | RXDATA | RO | `[7:0]` received byte. A read **pops** one RX FIFO entry when RX_VALID was 1 (consumed on the AR handshake; RDATA is snapshotted so a late RREADY cannot drop or skip a byte). Read while RX_VALID=0 returns `0` and does not pop. |
| `0x08` | TXDATA | WO | `[7:0]` push into TX when TX_READY=1 and `wstrb[0]=1`. If not ready (or `wstrb[0]=0`) the write is **ignored**; BRESP is still OKAY. Reads return `0`. |
| `0x0C` | CONTROL | RW | `[0]` ENABLE (reset `1`). Write `0` to hold `uart_rx` / `uart_tx` in reset. Only `wstrb[0]` updates the bit. |

Writes to STATUS/RXDATA are ignored (OKAY).

### Files

- `rtl/axil_slave.sv` — AXI4-Lite handshake (one outstanding read, one outstanding write)
- `rtl/uart_axil.sv` — register file + `uart_rx` / `uart_tx`
- `rtl/uart_rx.sv`, `rtl/uart_tx.sv` — existing cores (interfaces unchanged)

Dependencies (`Bender.yml`): `rtl_primitive` at `deps/` (`fifo`, `DFFR` / `DFFR_VAL` via `pkg/macro_pkg.sv`).

## LibreLane (sky130A)

Checkout Bender deps, then run LibreLane with the design directory `librelane/` (`DESIGN_NAME: uart_axil`, `CLOCK_PERIOD: 20`, **`USE_SLANG: false`**). The classic Yosys frontend is required: slang does not expand `DFF` / `DFFR` / `DFFR_VAL` from `macro_pkg.sv` (unknown macro).

`rtl_primitive` `pkg/macro_pkg.sv` must define those preprocessor macros **outside** any `package` (an empty `package macro_pkg; endpackage` may remain). After `bender checkout`, confirm `deps/rtl_primitive/pkg/macro_pkg.sv` looks like:

```systemverilog
`define DFF(...)
`define DFFR(...)
`define DFFR_VAL(...)

package macro_pkg;
endpackage
```

If `main` still nests the `` `define ``s inside the package, bump/checkout a `rtl_primitive` revision that moved them to file scope before synthesizing.

```bash
bender checkout
librelane librelane/config.yaml
```

Sources listed in `librelane/config.yaml` match the Quartus dependency set (`macro_pkg`, `dff`, `fifo`, `uart_tx`, `uart_rx`) plus `axil_slave` and `uart_axil`. Constraints: `librelane/constr/uart_axil.sdc` (`create_clock` on `i_clk`, false paths on `i_rst_n` / `i_rx` / `o_tx`).

## Simulation

```bash
verilator --binary --timing -j 0 \
  -Wno-UNUSEDSIGNAL -Wno-UNUSEDPARAM -Wno-WIDTHTRUNC -Wno-WIDTHEXPAND -Wno-INITIALDLY \
  deps/rtl_primitive/pkg/macro_pkg.sv \
  deps/rtl_primitive/rtl/fifo.sv \
  rtl/uart_tx.sv rtl/uart_rx.sv rtl/axil_slave.sv rtl/uart_axil.sv \
  dv/tb/tb_uart_axil.sv \
  --top-module tb_uart_axil
./obj_dir/Vtb_uart_axil
```
