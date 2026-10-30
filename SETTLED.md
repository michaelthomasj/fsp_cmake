# Settled positions

**Generated from `DECISIONS.md` by `scripts/build_settled.py`. Do not edit — edits are overwritten and the pre-commit hook fails on drift.**

`DECISIONS.md` is append-only, so the position on any question is stated by the newest entry in its thread and the earlier ones remain as the reasoning. This file says which entry that is. For the handful of questions that need a paragraph rather than a title, read the hand-written **Settled questions** table at the top of `DECISIONS.md`.

| | |
|---|---|
| Entries | **156** |
| Standing | **142** |
| Superseded | **14** |
| Standing but corrected on some point | **41** |
| Standing, but the question they left open is closed | **3** |
| Supersede lineages | **11** |

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
| D143 → **D155** | `D155` | D155 supersedes D143 |

---

## Standing (142)

Nothing supersedes these. The title is the position. Where a later entry corrects one, the correction is named - the entry stands apart from that. **Where the Closed by column is filled, read the status as historical:** the entry describes a problem that a later entry shut, so its own "Open" or "Provisional" is no longer true.

Accepted as written, with nothing later correcting or closing them - read the entry in [DECISIONS.md](DECISIONS.md) for the position:

`D004` `D005` `D006` `D007` `D010` `D011` `D012` `D013` `D015` `D016` `D017` `D018` `D019` `D020` `D021` `D022` `D023` `D024` `D025` `D026` `D027` `D028` `D030` `D032` `D033` `D034` `D038` `D043` `D044` `D045` `D046` `D048` `D049` `D050` `D051` `D053` `D054` `D055` `D056` `D057` `D058` `D059` `D060` `D061` `D062` `D063` `D064` `D066` `D067` `D068` `D069` `D070` `D071` `D072` `D073` `D074` `D076` `D077` `D078` `D080` `D081` `D086` `D088` `D089` `D092` `D096` `D100` `D101` `D103` `D105` `D106` `D109` `D111` `D118` `D127` `D131` `D133` `D134` `D135` `D137` `D138` `D139` `D141` `D142` `D145` `D146` `D147` `D148` `D149` `D150` `D151` `D152` `D155` `D156`

The rest carry a status, a correction or a closure:

| # | Date | Position | Status | Corrected by | Closed by |
|---|---|---|---|---|---|
| `D002` | 2026-08-10 | Each OFS group gets its own linker `MEMORY` region | Accepted | `D094` | — |
| `D003` | 2026-08-25 | RA6E1 replaces RA6M4 as the RA6 development vehicle | Accepted | `D016` | — |
| `D008` | 2026-09-08 | Declare `PLATFORM_HAS_ISOLATION_L3_SUPPORT` for RA6E1 | ~~**Provisional — builds, not yet run on hardware**~~ | — | `D015` |
| `D009` | 2026-09-07 | RA6M4 keeps its in-SPE NS app by default, behind a switch | Accepted | `D016` | — |
| `D014` | 2026-09-08 | The PSA Arch test tree is a local clone with tf-m-tests' patches applied by hand | ~~**Provisional — works, but the manual step is a known hazard**~~ | — | `D017`, `D142` |
| `D029` | 2026-09-14 | OPEN DEFECT: `.ram_from_flash` is excluded from copy-init at `profile_large` / L3 | ~~**Open - diagnosed, not fixed**~~ | — | `D048` |
| `D036` | 2026-09-21 | SCE9 acceleration via FSP `*_ALT`: AES, AES-GCM, SHA-256 first; ECC held back | **Provisional - builds; not yet run on silicon** | `D037` | — |
| `D037` | 2026-09-21 | SCE9 ECC enabled; P-521, Curve25519 and deterministic ECDSA removed from RA6M5 | **Provisional - builds; not yet run on silicon** | — | — |
| `D039` | 2026-09-21 | BL2 SHA-256 on the SCE9; P-256 verify stays on p256-m | **Provisional - builds; not yet run on silicon** | — | — |
| `D040` | 2026-09-21 | PSA Arch crypto on RA6M5 SCE9: generic Renesas target, deterministic ECDSA gated | **Provisional - built, not yet run** | — | — |
| `D041` | 2026-09-22 | Two FSP `aes_alt.c` fixes carried in the RA6M5 secure project; PSA Arch crypto 61/64 | Accepted for the TF-M port; the fixes belong in rm_psa_crypto | `D044` | — |
| `D042` | 2026-09-22 | TF-M's crypto is built from FSP's Mbed TLS, not upstream | Accepted for RA6M5 (`RA6M5_FSP_MBEDTLS`, default ON) | — | — |
| `D047` | 2026-09-23 | FSP 6.7 is the baseline | Accepted | `D131` | — |
| `D065` | 2026-09-29 | the flat-binary brick guard is now on all four ports, and a stale `.bin` is as lethal as a fresh one | Accepted | `D120`, `D132` (superseded by `D133`) | — |
| `D083` | 2026-10-02 | the PSA-arch builds needed two unrelated fixes, neither of them the MSVC install | Accepted | `D084` | — |
| `D084` | 2026-10-02 | the shared PSA-arch SPE is NOT a defect; the debug settings in it were cache residue | Accepted | `D087` | — |
| `D087` | 2026-10-04 | the secure-slot headroom figures were overstated; CONFIGURATION.md written | Accepted | `D154` | — |
| `D091` | 2026-10-05 | Option 3 adopted: both parts take TF-M's MCUboot backend, FSP's HAL behind fa_driver | Accepted | `D092` | — |
| `D093` | 2026-10-06 | `BSP_TZ_CFG_MSAR=0` on RA8M2: a workaround for an e2 generator defect, to be removed | Accepted, **temporary** | `D094` | — |
| `D094` | 2026-10-06 | the RA6M4 brick: coalescing is proven, the killed field is not; [D093]'s attribution corrected | Accepted | `D132` (superseded by `D133`) | — |
| `D095` | 2026-10-06 | RA8M2 passes the full regression on hardware; both live parts now proven under [D091] | Accepted | `D096` | — |
| `D097` | 2026-10-08 | RA8M2 PSA Arch: storage clean, crypto has one real failure — RSIP-E50D cannot generate RSA-2048 keys | Accepted | `D098` (superseded by `D111`) | — |
| `D099` | 2026-10-08 | closes [D097]'s gap: RA8M2 crypto is 62/1/1, and the sole delta from RA6M5 is test 216 | Accepted | `D111` | — |
| `D104` | 2026-10-08 | first RA8M2 IAR run on silicon: PSA Arch crypto is identical to GCC, test for test | Accepted | `D111` | — |
| `D108` | 2026-10-09 | supersedes [D107]'s fix: the real hook is `__dwrite`, because TF-M redirects `__write` | Accepted | `D110` | — |
| `D110` | 2026-10-09 | corrects the framing of [D107]/[D108]: the root cause is the call route, not the buffering | Accepted | `D126` | — |
| `D112` | 2026-10-12 | [D101]'s parity method cannot read the azone; one regenerate produced different TrustZone assignments per toolchain | Accepted | `D126` | — |
| `D113` | 2026-10-21 | isolation 2 on silicon: `TFM_ISOLATION_LEVEL` never reached the isolation HAL, and was hiding four port defects | Accepted | `D117`, `D120`, `D126` | — |
| `D114` | 2026-10-21 | isolation 3 green too; the missing macro was not one macro, it is that `platform_s` never links `psa_interface` | Accepted | `D115`, `D126` | — |
| `D115` | 2026-10-21 | RA8M2's MPU measured at 8 regions; corrects [D114] on PXN; the diagnostic hook itself broke L1+IPC | Accepted | `D117`, `D126` | — |
| `D116` | 2026-10-21 | the L1+IPC HardFault was the same undefined macro; closes [D113]/[D114]/[D115]'s carried items | Accepted | `D117`, `D126` | — |
| `D117` | 2026-10-21 | six corrections from an external review: [D113] overstated FLIH, [D116] closed a question that was answerable, and three ports deny the IDAU exists | Accepted | `D120`, `D126` | — |
| `D119` | 2026-10-21 | [D114]'s second macro confirmed under IAR; RA8M2 is complete at every level on both toolchains | Accepted | `D126` | — |
| `D120` | 2026-10-22 | the isolation-macro gap is this port's, not upstream's; [D113]'s root cause was wrong and upstream item 15 is withdrawn | Accepted | `D125`, `D128`, `D132` (superseded by `D133`) | — |
| `D121` | 2026-10-22 | the shared isolation HAL moves to `tfm_spm`; [D113]'s workaround is deleted, not documented | Accepted | `D125` | — |
| `D122` | 2026-10-22 | the `tfm_spm` move is MPU-neutral on silicon, and RA6M5 L1+IPC is green for the first time — cause unexplained | Accepted | `D125` | — |
| `D123` | 2026-10-22 | RA6M5 isolation 3 confirms [D121]'s predicted boundary shift to the byte; RA6M5 IAR runs above isolation 1 for the first time | Accepted | `D125` | — |
| `D124` | 2026-10-22 | the matrix is complete: every part, toolchain and isolation level has now run | Accepted | `D126` | — |
| `D125` | 2026-10-22 | six corrections to [D120]–[D123] from the second documentation review; the HAL never left the PSA-RoT code region | Accepted | `D128` | — |
| `D126` | 2026-10-22 | eighteen corrections to [D110]–[D125] from the second review; two carried items closed, and [D115]'s "three of four corners" was wrong | Accepted | `D128` | — |
| `D128` | 2026-10-22 | the metadata line is an index and may be repaired in place (new rule 7); ten relation fields corrected, and [D120]/[D125]/[D126] each got one attribution wrong | Accepted | `D129`, `D131` | — |
| `D129` | 2026-10-22 | the v4 review of `BUILD_ARCHITECTURE.md`: eight findings, the FSPR attribution withdrawn in eleven more places, and line citations are now checked | Accepted | `D131` | — |
| `D130` | 2026-10-22 | TF-M 2.3 is deferred, not cancelled: the gate is FSP's Mbed TLS 4.1 migration, expected ~2026-11-12 | Accepted | `D131` | — |
| `D136` | 2026-10-26 | the review's no-hardware tier: eleven fixes, verified by build and by the guard's own failure cases | Accepted | `D139` | — |
| `D140` | 2026-10-26 | the e2 baseline ships inside the deliverable, not as a branch beside it | Accepted | `D145` | — |
| `D144` | 2026-10-29 | the application chain gets its fourth script and its first RA8M2 launches; the pre-flash check becomes per part and works under IAR | Accepted | `D152` | — |
| `D153` | 2026-10-29 | the second review pass: nine wrong statements, a renderer that would have shipped withheld documents, and the limits of the checks | Accepted | `D154` | — |
| `D154` | 2026-10-29 | the release recipe did not build, and the space budget measured the wrong thing | Accepted | `D156` | — |

---

## Superseded (14)

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
| `D143` | 2026-10-29 | the deliverable repository moves into the Renesas organisation; the scripts stop depending on its directory name; the rename waits on admin | `D155` |

