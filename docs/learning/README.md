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

Audience, reading order, the four claim tags and the list of parts are on `index.html`.

## What it leaves out, deliberately

Crypto acceleration and the PSA Arch results, storage internals, the attestation token format,
the build and flash procedure, multi-core topology, Armv8.1-M features beyond PXN, and the parts other than RA6M5 and RA8M2.

