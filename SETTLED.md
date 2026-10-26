# Settled positions

**Generated from `DECISIONS.md` by `scripts/build_settled.py`. Do not edit — edits are overwritten and the pre-commit hook fails on drift.**

`DECISIONS.md` is append-only, so the position on any question is stated by the newest entry in its thread and the earlier ones remain as the reasoning. This file says which entry that is. For the handful of questions that need a paragraph rather than a title, read the hand-written **Settled questions** table at the top of `DECISIONS.md`.

| | |
|---|---|
| Entries | **137** |
| Standing | **124** |
| Superseded | **13** |
| Standing but corrected on some point | **35** |
| Standing, but the question they left open is closed | **3** |
| Supersede lineages | **10** |

---

## Threads — read the entry in bold

A later entry **supersedes** an earlier one: same question, newer answer. Citing anything but the bold entry means citing an answer that has been replaced. *Corrections* are a different thing and do not appear here — they fix a claim without replacing the entry, and are listed against each entry below.

| Thread | Stands | What moved |
|---|---|---|
| D001 → **D002** | `D002` | D002 supersedes D001 |
| D031 → **D033** | `D033` | D033 supersedes D031 |
| D035 → **D130** | `D130` | D130 supersedes D035 |
| D052 → **D053** | `D053` | D053 supersedes D052 |
| D075 → **D076** | `D076` | D076 supersedes D075 |
| D079 → D082 → D085 → D090 → **D091** | `D091` | D085 supersedes D082; D090 supersedes D085; D091 supersedes D079, D082; D091 corrects D090 |
| D098 → **D111** | `D111` | D098 corrects D097; D111 corrects D098, D099, D104 |
| D102 → **D103** | `D103` | D103 supersedes D102 |
| D107 → **D108** | `D108` | D108 supersedes D107 |
| D132 → **D133** | `D133` | D132 corrects D094, D065, D120; D133 supersedes D132; D133 corrects D132 |

---

## Standing (124)

Nothing supersedes these. The title is the position. Where a later entry corrects one, the correction is named - the entry stands apart from that. **Where the Closed by column is filled, read the status as historical:** the entry describes a problem that a later entry shut, so its own "Open" or "Provisional" is no longer true.

| # | Date | Position | Status | Corrected by | Closed by |
|---|---|---|---|---|---|
| `D002` | 2026-08-10 | Each OFS group gets its own linker `MEMORY` region | Accepted | `D094` | — |
| `D003` | 2026-08-25 | RA6E1 replaces RA6M4 as the RA6 development vehicle | Accepted | `D016` | — |
| `D004` | 2026-08-25 | Drive the flash layout from a RASC *solution*, not standalone projects | Accepted | — | — |
| `D005` | 2026-08-30 | Build the NS image in its own CMake project against the installed `api_ns/` | Accepted | — | — |
| `D006` | 2026-08-26 | Use TF-M's shared isolation HAL and generated secure linker, not port-owned copies | Accepted | — | — |
| `D007` | 2026-09-07 | Run the PSA Arch tests at `profile_large` with the port's defaults overridden | Accepted | — | — |
| `D008` | 2026-09-08 | Declare `PLATFORM_HAS_ISOLATION_L3_SUPPORT` for RA6E1 | ~~**Provisional — builds, not yet run on hardware**~~ | — | `D015` |
| `D009` | 2026-09-07 | RA6M4 keeps its in-SPE NS app by default, behind a switch | Accepted | `D016` | — |
| `D010` | 2026-09-07 | Pass the `g_main_stack` alias through a linker response file | Accepted | — | — |
| `D011` | 2026-09-07 | Guard the secure-only half of `tfm_hal_platform.c` on a port-private macro | Accepted | — | — |
| `D012` | 2026-08-30 | When the generated linker lacks a hook, add a generic one upstream rather than fork | Accepted | — | — |
| `D013` | 2026-09-08 | Keep TF-M's `flash_map[]` and area IDs; do not adopt the solution's | Accepted | — | — |
| `D014` | 2026-09-08 | The PSA Arch test tree is a local clone with tf-m-tests' patches applied by hand | ~~**Provisional — works, but the manual step is a known hazard**~~ | — | `D017` |
| `D015` | 2026-09-08 | Isolation 3 + IPC confirmed on hardware; D008 is no longer provisional | Accepted | — | — |
| `D016` | 2026-09-09 | RA6M5 is the upstream target; RA6M4 is skipped | Accepted | — | — |
| `D017` | 2026-09-09 | The PSA Arch target stays a local patch for RA6E1; the RA6M5 one goes upstream | Accepted | — | — |
| `D018` | 2026-09-09 | One RA-family PSA Arch target, named `tgt_dev_apis_tfm_renesas_ra` | Accepted | — | — |
| `D019` | 2026-09-14 | The IAR secure image reaches FSP's sections through an included ICF fragment, not a section-name macro | Accepted | — | — |
| `D020` | 2026-09-14 | `g_main_stack` is redirected, not defined, under IAR; one response file serves both images | Accepted | — | — |
| `D021` | 2026-09-14 | FSP 6.6 `.icf` files need `with alignment preservation` removed to build under IAR 9.50.2 | Accepted | — | — |
| `D022` | 2026-09-14 | The non-secure image under IAR: four toolchain branches, not a fork | Accepted | — | — |
| `D023` | 2026-09-14 | The IAR stack-seal block must name a section, not merely reserve space | Accepted | — | — |
| `D024` | 2026-09-14 | CMSE veneers are pinned at the NSC window under IAR too | Accepted | — | — |
| `D025` | 2026-09-14 | RTT under IAR needs `--keep __write`, and each image has its own control block | Accepted | — | — |
| `D026` | 2026-09-14 | Run the PSA Arch suites under IAR with `TOOLCHAIN=INHERIT`, not an IAR port of psa-arch-tests | Accepted | — | — |
| `D027` | 2026-09-14 | The NSPE test build must set `CMAKE_BUILD_TYPE` explicitly | Accepted | — | — |
| `D028` | 2026-09-14 | Two host-environment constraints on the PSA Arch test builds | Accepted | — | — |
| `D029` | 2026-09-14 | OPEN DEFECT: `.ram_from_flash` is excluded from copy-init at `profile_large` / L3 | ~~**Open - diagnosed, not fixed**~~ | — | `D048` |
| `D030` | 2026-09-21 | RA6M5 uses the whole 2 MB, with a reserved secure scratch block | Accepted | — | — |
| `D032` | 2026-09-21 | CORRECTION to the SCE9 size figures quoted on 2026-09-21 | Accepted | — | — |
| `D033` | 2026-09-21 | RA6M5 builds against the real e2 projects | Accepted | — | — |
| `D034` | 2026-09-21 | `BSP_CFG_EARLY_INIT` is asserted at build time, in both secure and BL2 | Accepted | — | — |
| `D036` | 2026-09-21 | SCE9 acceleration via FSP `*_ALT`: AES, AES-GCM, SHA-256 first; ECC held back | **Provisional - builds; not yet run on silicon** | `D037` | — |
| `D037` | 2026-09-21 | SCE9 ECC enabled; P-521, Curve25519 and deterministic ECDSA removed from RA6M5 | **Provisional - builds; not yet run on silicon** | — | — |
| `D038` | 2026-09-21 | CORRECTION to D037: deterministic ECDSA is unsupported in FSP by design | Accepted | — | — |
| `D039` | 2026-09-21 | BL2 SHA-256 on the SCE9; P-256 verify stays on p256-m | **Provisional - builds; not yet run on silicon** | — | — |
| `D040` | 2026-09-21 | PSA Arch crypto on RA6M5 SCE9: generic Renesas target, deterministic ECDSA gated | **Provisional - built, not yet run** | — | — |
| `D041` | 2026-09-22 | Two FSP `aes_alt.c` fixes carried in the RA6M5 secure project; PSA Arch crypto 61/64 | Accepted for the TF-M port; the fixes belong in rm_psa_crypto | `D044` | — |
| `D042` | 2026-09-22 | TF-M's crypto is built from FSP's Mbed TLS, not upstream | Accepted for RA6M5 (`RA6M5_FSP_MBEDTLS`, default ON) | — | — |
| `D043` | 2026-09-22 | SCE9 CCM stays in software; a third rm_psa_crypto session leak; crypto suite 63/64 | Accepted | — | — |
| `D044` | 2026-09-22 | The CTR fix is dropped; `mbedtls_aes_crypt_ctr()` is not an FSP API | Accepted | — | — |
| `D045` | 2026-09-22 | Confirmed on FSP 6.7.0-beta0: 63/64 with no port-local rm_psa_crypto patches | Accepted | — | — |
| `D046` | 2026-09-23 | RA6M5 PSA Arch on GCC and IAR: crypto, attestation, storage; RTT made lossless | Accepted | — | — |
| `D047` | 2026-09-23 | FSP 6.7 is the baseline | Accepted | `D131` | — |
| `D048` | 2026-09-23 | `.ram_from_flash` is copied by the platform, not by ILINK — closes [D029] | Accepted | — | — |
| `D049` | 2026-09-23 | The IAR NS toolchain emits `.srec` — closes the second open defect | Accepted | — | — |
| `D050` | 2026-09-24 | RSIP-E50D gets its own accelerator directory, consolidated with SCE9 at P7 | Accepted | — | — |
| `D051` | 2026-09-24 | E50D ALT selection: SCE9's module set, CCM still out, P-521 and Curve25519 kept in | Accepted | — | — |
| `D053` | 2026-09-24 | The E50D pack ships both session-leak fixes — supersedes [D052] | Accepted | — | — |
| `D054` | 2026-09-24 | DF_EMULATION is 64 KB because FSP's MRAM sector size forces it | Accepted | — | — |
| `D055` | 2026-09-24 | RA8M2 full chain builds and links on IAR; four defects found by building it | Accepted | — | — |
| `D056` | 2026-09-24 | OFS addresses are generated, and a guard that reports PASS on the wrong window is worse than none | Accepted | — | — |
| `D057` | 2026-09-25 | The GCC leg is the reference; the IAR solution's RAM split is stale | Accepted | — | — |
| `D058` | 2026-09-25 | The flat `.bin` is a second route to the brick, and the ELF guard never saw it | Accepted | — | — |
| `D059` | 2026-09-25 | P-521 and Curve25519 come out of the E50D config until after TF-M 2.3 | Accepted | — | — |
| `D060` | 2026-09-25 | RA6M5 execution-path audit: what the boot trace turned up | Accepted | — | — |
| `D061` | 2026-09-26 | Secure interrupts on RA: delete the dead HAL, and write down why the upstream recipe does not apply | Accepted | — | — |
| `D062` | 2026-09-27 | RA declares test capabilities; ra6m4 could not build TEST_S at all | Accepted | — | — |
| `D063` | 2026-09-28 | Pinned CMSE veneers get their own MEMORY region; the regression suite now links | Accepted | — | — |
| `D064` | 2026-09-29 | BL2 masking interrupts is sound and complete; the SPMON hazard does not exist on these parts | Accepted | — | — |
| `D065` | 2026-09-29 | the flat-binary brick guard is now on all four ports, and a stale `.bin` is as lethal as a fresh one | Accepted | `D120`, `D132` (superseded by `D133`) | — |
| `D066` | 2026-09-29 | RA8M2's partition comments described RA6M5, including the values that get provisioned | Accepted | — | — |
| `D067` | 2026-09-29 | first full tf-m-tests regression pass on hardware, and two suites that report PASSED without testing | Accepted | — | — |
| `D068` | 2026-09-30 | the FLIH/SLIH fixture, and two silent defects the IAR build found in D065 | Accepted | — | — |
| `D069` | 2026-09-30 | a weak symbol in a static library silently unrouted every secure interrupt | Accepted | — | — |
| `D070` | 2026-09-30 | FLIH verified on both toolchains; the fixture is portable, and RTT addresses are per-build | Accepted | — | — |
| `D071` | 2026-09-30 | SLIH passes too; both FF-M handling models work, with one fixture | Accepted | — | — |
| `D072` | 2026-10-01 | RA6M5 interrupt matrix complete; and an RTT capture can truncate silently | Accepted | — | — |
| `D073` | 2026-10-01 | one MRAM alias is not enough: the RA8M2 flash driver must pick it per offset | Accepted | — | — |
| `D074` | 2026-10-01 | where MRAM_ADDR's two constants come from; refines [D073] | Accepted | — | — |
| `D076` | 2026-10-01 | [D075] describes code that was reverted; BL2 still has no SAU | Accepted | — | — |
| `D077` | 2026-10-01 | FSP replication audit: one live defect, three fixes that never reached the RA6 ports | Accepted | — | — |
| `D078` | 2026-10-02 | the RA8M2 secure primary slot generated as 0x200; cause was partition ORDER, not geometry | Accepted | — | — |
| `D080` | 2026-10-02 | every recorded attestation pass was on a token with no measurements | Accepted | — | — |
| `D081` | 2026-10-02 | measured boot confirmed on RA6M5 hardware, by reading the boot record | Accepted | — | — |
| `D083` | 2026-10-02 | the PSA-arch builds needed two unrelated fixes, neither of them the MSVC install | Accepted | `D084` | — |
| `D084` | 2026-10-02 | the shared PSA-arch SPE is NOT a defect; the debug settings in it were cache residue | Accepted | `D087` | — |
| `D086` | 2026-10-04 | documentation reorganised around the live parts; DESIGN.md had drifted furthest | Accepted | — | — |
| `D087` | 2026-10-04 | the secure-slot headroom figures were overstated; CONFIGURATION.md written | Accepted | — | — |
| `D088` | 2026-10-04 | TROUBLESHOOTING.md written; three of its own cross-references were wrong first | Accepted | — | — |
| `D089` | 2026-10-04 | BRIDGING_FILES.md written; [D083]'s IAR path fix had only covered RA6M5 | Accepted | — | — |
| `D091` | 2026-10-05 | Option 3 adopted: both parts take TF-M's MCUboot backend, FSP's HAL behind fa_driver | Accepted | `D092` | — |
| `D092` | 2026-10-05 | RA8M2's first boot: BL2 works; the secure image needs Clocks set Secure in e2 | Accepted | — | — |
| `D093` | 2026-10-06 | `BSP_TZ_CFG_MSAR=0` on RA8M2: a workaround for an e2 generator defect, to be removed | Accepted, **temporary** | `D094` | — |
| `D094` | 2026-10-06 | the RA6M4 brick: coalescing is proven, the killed field is not; [D093]'s attribution corrected | Accepted | `D132` (superseded by `D133`) | — |
| `D095` | 2026-10-06 | RA8M2 passes the full regression on hardware; both live parts now proven under [D091] | Accepted | `D096` | — |
| `D096` | 2026-10-06 | measured boot confirmed on RA8M2 by decoding the boot record; [D095] had assumed it | Accepted | — | — |
| `D097` | 2026-10-08 | RA8M2 PSA Arch: storage clean, crypto has one real failure — RSIP-E50D cannot generate RSA-2048 keys | Accepted | `D098` (superseded by `D111`) | — |
| `D099` | 2026-10-08 | closes [D097]'s gap: RA8M2 crypto is 62/1/1, and the sole delta from RA6M5 is test 216 | Accepted | `D111` | — |
| `D100` | 2026-10-08 | the MCUboot upgrade path runs on RA8M2: both images installed, secondary erased | Accepted | — | — |
| `D101` | 2026-10-08 | the three RA8M2 IAR project gaps are closed; IAR and GCC are now configuration-identical | Accepted | — | — |
| `D103` | 2026-10-08 | supersedes [D102] on the IAR launch host project: it is the IAR project, and auto-config is false | Accepted | — | — |
| `D104` | 2026-10-08 | first RA8M2 IAR run on silicon: PSA Arch crypto is identical to GCC, test for test | Accepted | `D111` | — |
| `D105` | 2026-10-09 | RA8M2 IAR matches GCC on every suite, and measured boot is verified from the boot record | Accepted | — | — |
| `D106` | 2026-10-09 | the MCUboot upgrade installs under IAR too; M5 is met on both toolchains | Accepted | — | — |
| `D108` | 2026-10-09 | supersedes [D107]'s fix: the real hook is `__dwrite`, because TF-M redirects `__write` | Accepted | `D110` | — |
| `D109` | 2026-10-09 | the IAR BL2 log works; it closes [D106]'s open item and refines [D099]'s `%zx` finding | Accepted | — | — |
| `D110` | 2026-10-09 | corrects the framing of [D107]/[D108]: the root cause is the call route, not the buffering | Accepted | `D126` | — |
| `D111` | 2026-10-09 | supersedes [D098]: there is no config switch for the RSA-2048 keygen gap; the guard is on the engine | Accepted | — | — |
| `D112` | 2026-10-12 | [D101]'s parity method cannot read the azone; one regenerate produced different TrustZone assignments per toolchain | Accepted | `D126` | — |
| `D113` | 2026-10-21 | isolation 2 on silicon: `TFM_ISOLATION_LEVEL` never reached the isolation HAL, and was hiding four port defects | Accepted | `D117`, `D120`, `D126` | — |
| `D114` | 2026-10-21 | isolation 3 green too; the missing macro was not one macro, it is that `platform_s` never links `psa_interface` | Accepted | `D115`, `D126` | — |
| `D115` | 2026-10-21 | RA8M2's MPU measured at 8 regions; corrects [D114] on PXN; the diagnostic hook itself broke L1+IPC | Accepted | `D117`, `D126` | — |
| `D116` | 2026-10-21 | the L1+IPC HardFault was the same undefined macro; closes [D113]/[D114]/[D115]'s carried items | Accepted | `D117`, `D126` | — |
| `D117` | 2026-10-21 | six corrections from an external review: [D113] overstated FLIH, [D116] closed a question that was answerable, and three ports deny the IDAU exists | Accepted | `D120`, `D126` | — |
| `D118` | 2026-10-21 | first IAR run above isolation 1: RA8M2 L2 green, and the MMIO region is the only toolchain-invariant in the table | Accepted | — | — |
| `D119` | 2026-10-21 | [D114]'s second macro confirmed under IAR; RA8M2 is complete at every level on both toolchains | Accepted | `D126` | — |
| `D120` | 2026-10-22 | the isolation-macro gap is this port's, not upstream's; [D113]'s root cause was wrong and upstream item 15 is withdrawn | Accepted | `D125`, `D128`, `D132` (superseded by `D133`) | — |
| `D121` | 2026-10-22 | the shared isolation HAL moves to `tfm_spm`; [D113]'s workaround is deleted, not documented | Accepted | `D125` | — |
| `D122` | 2026-10-22 | the `tfm_spm` move is MPU-neutral on silicon, and RA6M5 L1+IPC is green for the first time — cause unexplained | Accepted | `D125` | — |
| `D123` | 2026-10-22 | RA6M5 isolation 3 confirms [D121]'s predicted boundary shift to the byte; RA6M5 IAR runs above isolation 1 for the first time | Accepted | `D125` | — |
| `D124` | 2026-10-22 | the matrix is complete: every part, toolchain and isolation level has now run | Accepted | `D126` | — |
| `D125` | 2026-10-22 | six corrections to [D120]–[D123] from the second documentation review; the HAL never left the PSA-RoT code region | Accepted | `D128` | — |
| `D126` | 2026-10-22 | eighteen corrections to [D110]–[D125] from the second review; two carried items closed, and [D115]'s "three of four corners" was wrong | Accepted | `D128` | — |
| `D127` | 2026-10-22 | the CMake target graph gets its own document, drawn in ASCII rather than mermaid | Accepted | — | — |
| `D128` | 2026-10-22 | the metadata line is an index and may be repaired in place (new rule 7); ten relation fields corrected, and [D120]/[D125]/[D126] each got one attribution wrong | Accepted | `D129`, `D131` | — |
| `D129` | 2026-10-22 | the v4 review of `BUILD_ARCHITECTURE.md`: eight findings, the FSPR attribution withdrawn in eleven more places, and line citations are now checked | Accepted | `D131` | — |
| `D130` | 2026-10-22 | TF-M 2.3 is deferred, not cancelled: the gate is FSP's Mbed TLS 4.1 migration, expected ~2026-11-12 | Accepted | `D131` | — |
| `D131` | 2026-10-22 | the v5 review: two generators were passing against their own faulty output; the RA6M5 PXN correction gets the entry it never had | Accepted | — | — |
| `D133` | 2026-10-22 | the coalesced fill zeroes eight DEFINED option registers, not only reserved bytes; [D132] overstated the reserved-area reading | Accepted | — | — |
| `D134` | 2026-10-23 | the 2026-10-23 technical review: the five high findings hold against source | Accepted | — | — |
| `D135` | 2026-10-23 | eight defects from the 2026-10-23 review are fixed now; P01-P05 and the brick-path restructure are the owner's | Accepted | — | — |
| `D136` | 2026-10-26 | the review's no-hardware tier: eleven fixes, verified by build and by the guard's own failure cases | Accepted | — | — |
| `D137` | 2026-10-26 | what ships to a customer: RA6M4 and the working material leave the branch, RA6E1 and the brick evidence stay | Accepted | — | — |

---

## Superseded (13)

Kept for the reasoning. **Do not cite one of these without reading what replaced it** — in several cases the later entry reverses the earlier claim outright.

| # | Date | Position as stated then | Superseded by |
|---|---|---|---|
| `D001` | 2026-07-21 | Option-setting (OFS) memory must never be linked into an image | `D002` |
| `D031` | 2026-09-21 | The RA6M5 port was verified against a staged project set, not the e2 projects | `D033` |
| `D035` | 2026-09-21 | Stay on TF-M 2.2; the TF-M 2.3 rebase is cancelled | `D130` |
| `D052` | 2026-09-24 | The E50D pack is missing both session-leak fixes; RA8M2 bring-up proceeds anyway | `D053` |
| `D075` | 2026-10-01 | BL2 must enable the SAU on RA8M2; the right alias is not enough | `D076` |
| `D079` | 2026-10-02 | BL2 takes its MCUboot flash backend from FSP; closes [D076] | `D091` |
| `D082` | 2026-10-02 | RA6M5 follows [D079]: BL2 takes its MCUboot flash backend from FSP | `D085`, `D091` |
| `D085` | 2026-10-04 | RA6M5 reverts to TF-M's MCUboot flash backend; [D082] is withdrawn | `D090` |
| `D090` | 2026-10-05 | the RA6M5 FSP-backend failure was a struct flash_area mismatch; [D085] is superseded | `D091` |
| `D098` | 2026-10-08 | refines [D097]: the RSA-2048 keygen failure is the PLAINTEXT path, and the config selects it | `D111` |
| `D102` | 2026-10-08 | RA8M2 IAR: all six trees build, five launches generated; the ewarm staleness was already gone | `D103` |
| `D107` | 2026-10-09 | BL2 is silent under IAR because DLIB buffers stdout; `rtt_stdout.c` now makes it unbuffered | `D108` (also corrected by `D110`) |
| `D132` | 2026-10-22 | the RA6M4 brick is a write to a reserved area; no field needs naming | `D133` |

