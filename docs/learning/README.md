# Cortex-M, TrustZone and TF-M on Renesas RA — a course

Open `index.html` in a browser: plain HTML, no server and no network. **One build step
first**, because the course links the repository documents through HTML renderings in `ref/`
that are generated rather than committed:

```
python scripts/build_doc_html.py
```

Without it the pages read fine and every link into `ref/` is dead. A release archive should
carry `ref/` already built, from a clean checkout so that only the tracked documents are in it.

Optional background, outside the main documentation path. It explains why the port is built the
way it is; [GETTING_STARTED.md](../../GETTING_STARTED.md) is how to build it.

## Who it is for

An engineer who knows C and can read a datasheet but has not met privilege levels, an MPU,
TrustZone or a secure partition manager, and who wants to work on or port this TF-M port. It
assumes C, pointers, linker sections at a basic level, and reading hex.

## The pages

| Page | Content |
|---|---|
| `index.html` | audience, how to read, the four claim tags, hardware summary |
| `part0-primer.html` | Cortex-M from scratch, with RA addresses |
| `part1-privilege-mpu-faults.html` | privilege, MSP and PSP, MPU encoding, stacking, `EXC_RETURN`, SVC and PendSV, fault decoding from real dumps |
| `part2-trustzone.html` | security states, SAU and IDAU, non-secure-callable and `SG`, banking, NVIC target state, and the RA security attribution registers |
| `part3-tfm.html` | PSA-FF-M, `psa_call`, isolation levels, the SPM, SFN against IPC, FLIH, and the isolation HAL |
| `part4-porting.html` | the platform contract, the RASC and FSP inputs, the MCUboot layout, the hazards, and the verification gates |
| `glossary.html` | terms, and the files and decisions the course cites |

Every claim is tagged **Armv8-M** for the architecture, **TF-M** for an implementation choice,
**RA** for Renesas silicon or FSP, and **This port** for a local decision.

## What it leaves out, deliberately

Crypto acceleration and the PSA Arch results, storage internals, the attestation token format,
the build and flash procedure, multi-core topology, Armv8.1-M features beyond PXN, and the
parts that are reference-only except where their history is the worked example.

## The `ref/` renderings

The course links the repository's documents through HTML renderings in `ref/`, never the raw
Markdown. **That directory is generated and is not committed.** Produce it with

```
python scripts/build_doc_html.py
```

and the links resolve. Do not edit `ref/*.html`: edit the Markdown and render again. Deep links
take the form `ref/DECISIONS.html#d113` for an entry and `ref/DESIGN.html#s8-4` for a numbered
section.
