# Archive — the RA6M4 era (2025-10 → 2026-09)

**Nothing in this directory describes the active ports.** RA6M5 and RA8M2 are the live parts;
these documents predate them and were written against RA6M4, which is dormant — both EK-RA6M4
boards were bricked by the OFS coalescing defect ([DECISIONS](../../DECISIONS.md) D002).

Kept because the resolved-issue narratives are the valuable part and several are cited by
`DECISIONS.md`. Read them as history, not as instructions.

| File | What it is | Trust |
|---|---|---|
| `TFM_RA6M4_STATUS.md` | status + running TODO for RA6M4; cited by D-entries for the platform-owned-linker argument | historical; its TODOs are not the current plan |
| `TFM_EXECUTION_FLOW.md` | reset → secure-service boot-path walkthrough, with source line references | **structurally still accurate** — the boot path is shared. Line numbers have drifted |
| `TFM_FSP_NS_BUILD_GUIDE.md` | symmetric SPE/NSPE build guide | **do not follow.** Predates the split SPE/NSPE build (D005) |
| `TFM_NS_FREERTOS_TEST.md` | FreeRTOS NS app on RA6M4 | historical; no active part ships a FreeRTOS NS app |
| `TRUSTZONE_FREERTOS_REQUIREMENTS.md` | the `TZ_StoreContext_S` link failure and its fix | still the best write-up of that failure if FreeRTOS returns |
| `BUILD_TEST_RESULTS.md` | build results, 2025-11-17 | historical snapshot |
| `TFM_INTEGRATION_COMPLETE.md` | milestone write-up; its "Adding New FSP Modules" section is cited by `RA6E1_TEMPLATE_CHECKLIST.md` | that one section is still useful; the rest is a milestone note |
| `RASC_PROJECT_SETUP.md` | RASC settings to recreate the three RA6M4 FSP projects from scratch | the *procedure* generalises; the settings are RA6M4's |

For the live documentation set start at the [root README](../../README.md).
