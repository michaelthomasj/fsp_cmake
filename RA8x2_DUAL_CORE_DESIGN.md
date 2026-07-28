# RA8x2 Dual-Core TF-M — Inter-Core Communication Design & Implementation Tracker

**Purpose.** Track what it takes to run Trusted Firmware-M across the two cores of
a dual-core RA8 (RA8D2 / RA8x2): SPE on one core, NSPE on the other, with PSA
client calls marshaled over a mailbox. The mailbox transport is backed by the
**RA8D2 IPC peripheral** through the **FSP IPC driver**.

Three layers, top consumes bottom:

```
TF-M multi-core mailbox HAL   (what we implement — platform/ext/target/renesas/ra8x2)
        │
FSP IPC driver  (r_ipc)       (R_IPC_Open / MessageSend / EventGenerate / CallbackSet; sem+NMI via BSP)
        │
RA8D2 IPC peripheral          (manual §3: 2×4-deep 32-bit FIFOs, 16 HW semaphores, maskable IRQ + NMI)
```

Sources: RA8D2 User's Manual `r01uh1065ej0083` §3 (Inter-Processor Communication);
FSP IPC API <https://renesas.github.io/fsp/group___i_p_c.html>; TF-M dual-cpu design
docs (`trusted-firmware-m/docs/design_docs/dual-cpu/`) and mailbox HAL headers.

---

## Layer 1 — RA8D2 IPC peripheral (manual §3)

- **Base address:** `0x4002_0000` (Secure) / `0x5002_0000` (Non-secure). Security /
  privilege attribution via `IPCSAR` / `IPCPAR` (in CPSCU, base `0x4000_8000` S /
  `0x5000_8000` NS). *The IPC is TZ-attributable — decide which core/world owns it.*
- **Two processors × two FIFO channels.** `IPC0*` registers carry **CPU1 → CPU0**
  traffic; `IPC1*` carry **CPU0 → CPU1**. Each processor has two message FIFOs
  (channel 0 and 1): `IPCxTXDy` (send), `IPCxRXDy` (receive), `IPCxSTAy` (status),
  `IPCxISETy` (IRQ set), `IPCxCLRy` (clear).
- **Message FIFO:** **4 entries deep, 32-bit only.** "Only writing with a 32-bit
  data size is valid; halfword/byte access is ignored." Storing a 5th entry
  **raises a busfault**; when full, `IPCxSTAy.FULL = 1`. Writing any TXD sets
  `IPCxSTAy.RDY = 1` and generates an interrupt. `RST` bit resets a FIFO.
- **Maskable interrupt (IRQ):** 8 events (`IRQ0..7`) but **one shared interrupt
  line per channel** — the handler must read `IPCxSTAy` to see the cause. Status
  bits: `[7:0]` IRQ7–0, `[16]` RDY (FIFO not empty), `[24]` RERR (read-while-empty),
  `[25]` FERR (write-while-full). Set an event via `IPCxISETy.SETn`; clear via
  `IPCxCLRy.CLRn` (all bits 0 ⇒ IRQ de-asserts).
- **Non-maskable interrupt (NMI):** `IPCxNMISTA/SET/CLR` — write SET issues an NMI
  to the peer core; write CLR cancels. Independent of the FIFOs.
- **16 hardware semaphores:** `IPCSEM0..15`, each a `LOCK` bit for exclusive control
  between CPU0/CPU1. "Application can choose to use a semaphore separately or in
  common between the two cores." *Reserve one for the mailbox critical section.*

**Consequence for the mailbox:** the FIFO is a **doorbell**, not a data channel —
a 32-bit token per notify is enough. The **actual PSA-call payload lives in shared
SRAM** (the NS mailbox queue); a **hardware semaphore** guards it; the **maskable
IRQ** signals "message ready". Keep ≤4 outstanding tokens or drain in the handler
to avoid the busfault.

---

## Layer 2 — FSP IPC driver API (`r_ipc`)

| FSP call | Purpose |
|---|---|
| `R_IPC_Open(ctrl, cfg)` | Configure a channel: `ipc_cfg_t{ name, channel, direction (IPC_DIRECTION_SEND/RECEIVE), callback }` |
| `R_IPC_MessageSend(ctrl, msg)` | Push one **32-bit** word into the channel's TX FIFO |
| `R_IPC_EventGenerate(ctrl, event)` | Set IRQ event bit(s) + raise the maskable interrupt on the peer (`IPC_GENERATE_EVENT_IRQ0..n`) |
| `R_IPC_CallbackSet(ctrl, cb, ctx)` | Register the RX/event callback |
| `R_IPC_Close(ctrl)` | Release the channel |
| callback `ipc_callback_args_t{ event, message }` | `event = IPC_EVENT_MESSAGE_RECEIVED` (FIFO data) or `IPC_EVENT_IRQ0..n`; `message` = received word. Runs in ISR context |

**Not in the IPC driver — use BSP APIs:** the **hardware semaphores** (`IPCSEMn`) and
the **NMI** are handled through `R_BSP_*` APIs, not `r_ipc`. Confirm the exact BSP
semaphore lock/unlock symbols in FSP 6.6.

---

## Layer 3 — TF-M multi-core mailbox HAL (what we implement)

SPE-side contract (`trusted-firmware-m/platform/include/`):

- `tfm_hal_mailbox.h` — `tfm_mailbox_hal_init()`, `tfm_mailbox_hal_notify_peer()`,
  `tfm_mailbox_hal_enter_critical()` / `exit_critical()`.
- `tfm_hal_multi_core.h` — `tfm_hal_boot_ns_cpu()`, `tfm_hal_wait_for_ns_cpu_ready()`,
  `tfm_hal_get_secure_access_attr()` / `tfm_hal_get_ns_access_attr()`.
- SPE agent partition: `secure_fw/partitions/ns_agent_mailbox/`.
- NS side: `interface/{include,src}/multi_core/` (generic) + platform `platform_ns_mailbox.c`.

Closest reference: **`platform/ext/target/rpi/rp2350/`** (dual Cortex-M33 + TrustZone,
*hybrid* topology). Also `cypress/psoc64` (SPE-core / NSPE-core split).

---

## The mapping (this is the port)

| TF-M mailbox HAL | FSP IPC / BSP | RA8D2 IPC | Notes |
|---|---|---|---|
| `tfm_mailbox_hal_init(s_queue)` | `R_IPC_Open`(RECEIVE + callback); handshake via `R_IPC_MessageSend`/RX | RXD/TXD FIFO | NSPE sends its NS-queue base **address (32-bit)** over the FIFO; SPE stores `ns_status`/`ns_slots`/`ns_slot_count` into `s_queue`. **Validate the address is in NS SRAM** (the rp2350 `FIXME`) |
| `tfm_mailbox_hal_notify_peer()` | `R_IPC_MessageSend(token)` or `R_IPC_EventGenerate` | TXD FIFO → peer `RDY`/IRQ | doorbell only; payload already in shared SRAM |
| `tfm_mailbox_hal_enter_critical()` | BSP semaphore **lock** | `IPCSEMn.LOCK` | reserve one `IPCSEMn` for the mailbox |
| `tfm_mailbox_hal_exit_critical()` | BSP semaphore **unlock** | `IPCSEMn` release | |
| IPC IRQ handler → `spm_handle_interrupt()` | `R_IPC` callback (`IPC_EVENT_MESSAGE_RECEIVED`) | `IPCxSTAy` (RDY/IRQn) → `IPCxCLRy` | one IRQ line/channel — read STA, clear, then signal `MAILBOX_SIGNAL` to `ns_agent_mailbox` |
| `tfm_hal_boot_ns_cpu(start)` | FSP secondary-core start (**confirm API**) | CPU1 release (SYSC/reset) | separate from IPC; the second core then does its TZ/NS setup |
| `tfm_hal_wait_for_ns_cpu_ready()` | `R_IPC` RX of a ready token | RXD FIFO | |
| `tfm_hal_get_{secure,ns}_access_attr()` | — | — | from RA8x2 `region_defs.h` + shared-SRAM attribution; see `tfm_multi_core_access_check.rst` |

**Data path:** NSPE writes a PSA call into its mailbox queue (shared SRAM) → takes
`IPCSEMn` → `notify_peer` (FIFO doorbell) → SPE IPC IRQ → `ns_agent_mailbox` reads
the queue (access-checked) → dispatches the PSA call → writes the reply → `notify_peer`
back → NSPE IPC IRQ wakes the NS mailbox client.

---

## Files to write (`trusted-firmware-m/platform/ext/target/renesas/ra8x2/`)

```
tfm_hal_mailbox.c       # 4 HAL fns + IPC callback/IRQ → spm_handle_interrupt + mailbox_irq_init
tfm_hal_multi_core.c    # boot_ns_cpu, wait_for_ns_cpu_ready, get_{secure,ns}_access_attr
platform_multicore.h    # handshake tokens; IPC channel/direction; IPCSEM index; IRQ number
ns/platform_ns_mailbox.c# NS-side transport (mirror, NSPE core)
```
Plus: enable `TFM_MULTI_CORE_TOPOLOGY`, pull in `ns_agent_mailbox`, set
`NUM_MAILBOX_QUEUE_SLOT`, place the mailbox queues in a both-core shared SRAM region.

---

## Open decisions (settle at P4 start — several feed the topology spike)

1. **Core topology.** Which core is SPE, which is NSPE; is the NSPE core plain, or
   does it run its own TrustZone (hybrid, like rp2350)? Drives everything. *(Open —
   never examined; see PROJECT_PLAN P4.)*
2. **IPC channel/direction assignment.** `IPC0` = CPU1→CPU0, `IPC1` = CPU0→CPU1 —
   map S→NS and N→S notifies onto these; pick FIFO channel 0 vs 1.
3. **Semaphore allocation.** Which `IPCSEMn` is the mailbox mutex (avoid clashing
   with any application semaphore use).
4. **Shared SRAM region.** Where the mailbox queues live so both cores reach them;
   its S/NS attribution; how the SPE reads NS-owned params (access check).
5. **Secondary-core boot.** The RA8D2 CPU1 release mechanism + the FSP API for it,
   and CPU1's entry (TZ setup, `sau_and_idau_cfg`, jump to NS).
6. **IPC peripheral ownership.** `IPCSAR`/`IPCPAR` attribution — which world programs
   the IPC; both cores need their end.
7. **NMI use.** Reserve NMI for a flash-write "halt peer" doorbell (rp2350 pattern),
   or leave unused for MVP.
8. **FSP BSP semaphore API.** Confirm the `R_BSP_*` symbols for `IPCSEMn` lock/unlock
   in FSP 6.6.

---

## Implementation tracker

| # | Item | Layer | Status |
|---|---|---|---|
| 1 | Topology decision (SPE/NSPE core, hybrid vs split) | design | ☐ open |
| 2 | RA8x2 base port: BL2 + SPE boot on primary core (reuse RA6 patterns + DDSC bridge) | port | ☐ |
| 3 | Secondary-core boot (`tfm_hal_boot_ns_cpu`, CPU1 release + entry) | HAL | ☐ |
| 4 | Shared-SRAM mailbox-queue region + `region_defs.h` | layout | ☐ |
| 5 | `R_IPC_Open` channels (S↔NS), callback wiring | FSP | ☐ |
| 6 | `tfm_mailbox_hal_init` handshake (exchange NS queue addr) | HAL | ☐ |
| 7 | `tfm_mailbox_hal_notify_peer` (FIFO doorbell / EventGenerate) | HAL | ☐ |
| 8 | `enter/exit_critical` on `IPCSEMn` (BSP semaphore) | HAL | ☐ |
| 9 | IPC IRQ handler → `spm_handle_interrupt`; `mailbox_irq_init` + client-id range | HAL | ☐ |
| 10 | `ns_agent_mailbox` partition enabled; `TFM_MULTI_CORE_TOPOLOGY` build | build | ☐ |
| 11 | NS-side `platform_ns_mailbox.c` on NSPE core | NS | ☐ |
| 12 | `get_{secure,ns}_access_attr` + cross-core pointer checks | security | ☐ |
| 13 | End-to-end: PSA call marshaled NSPE-core → SPE-core (M5) | integ | ☐ |
| 14 | IAR `.icf` for both cores (P6) | toolchain | ☐ |

---

*Related: PROJECT_PLAN.md (P4–P6), DESIGN.md (§13 TZ/startup ownership, §13.4 DDSC),
and `trusted-firmware-m/docs/design_docs/dual-cpu/`.*
