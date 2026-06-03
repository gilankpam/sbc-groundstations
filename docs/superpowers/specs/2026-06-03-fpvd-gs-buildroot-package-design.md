# fpvd GS Buildroot package — design

**Date:** 2026-06-03
**Repos touched:** `sbc-groundstations` (new package + wiring), `fpvd` (one packaging fix)

## Context

The `fpvd` project (`git@github.com:gilankpam/fpvd.git`) has a GS-side Python
daemon, `fpvdgs`, that is becoming the single ground-station supervisor: it owns
the wfb data plane (in-process, built on the `wfb_ng` library), spawns and
supervises the `pixelpilot` display process, and hosts the GS HTTP API on `:8080`.
Today it reaches the GS only via `deploy/gs/deploy.sh` (scp + manual service
handoff). We want it baked into the Buildroot image so a fresh flash boots
straight into the fpvd-supervised stack.

This complements work already done in `pixelpilot.mk`, which stopped installing
the pixelpilot init/wrapper (`S99pixelpilot`, `pixelpilot.sh`,
`/etc/default/pixelpilot`) — fpvd now owns pixelpilot's lifecycle.

Goal: a `BR2_PACKAGE_FPVD` package that installs the `fpvdgs` module and makes
fpvd the sole GS supervisor on boot ("full GS-supervisor handoff").

## Scope

In scope: the GS Python module only (`fpvd` repo `gs/` subtree). Out of scope:
the `drone/` C++ side of the fpvd repo.

## Findings (why this shape)

- `fpvdgs` is **pure Python** — stdlib only except a single third-party import,
  `wfb_ng`. No HTTP framework (stdlib `http` + `asyncio`).
- `wfb_ng` is already packaged: **`wfb-server`** (Buildroot `python-package`,
  setuptools, `OMIT_DATA_FILES=True`) installs the `wfb_ng` module.
- The `wfb_rx`/`wfb_tx`/`wfb_tun`/`wfb_keygen` binaries fpvd spawns, the wfb
  keys, and `S98wifibroadcast` all come from **`wifibroadcast-ng`**
  (generic-package). `S98wifibroadcast` is the only competing init in this image.
- `radxa_zero3_defconfig` already has `BR2_PACKAGE_PYTHON3=y`,
  `WIFIBROADCAST_NG=y`, `WFB_SERVER=y`, `PIXELPILOT=y`, and
  `BR2_PACKAGE_ADAPTIVE_LINK=n` — so adaptive-link is **not** present and needs
  no handling; pixelpilot init is already suppressed.
- fpvd's `gs/` has **no `setup.py`** (pyproject-only) → Buildroot setup type must
  be `pep517`, not `setuptools`.
- pyproject defines console scripts `fpvd = fpvdgs.supervisor:main` and
  `fpvd-runner = fpvdgs.runner:main` → the build auto-generates
  `/usr/bin/fpvd` and `/usr/bin/fpvd-runner`. `S99fpvd` invokes `/usr/bin/fpvd`.
- The dynlink radio profile JSON is loaded at runtime relative to the installed
  module: `dynlink/config_build.py:28`
  `PROFILES_DIR = Path(__file__).resolve().parent / "profiles"` →
  `<site-packages>/fpvdgs/dynlink/profiles/m8812eu2.json`. `profiles/` has no
  `__init__.py` and pyproject declares no package-data, so a stock wheel would
  omit it (today `deploy.sh` scp's it separately). **Decision: fix in fpvd
  pyproject so it ships in the wheel.**

## Changes

### 1. fpvd repo — ship the dynlink profiles in the wheel

Edit `gs/pyproject.toml`, add:

```toml
[tool.setuptools.package-data]
"fpvdgs.dynlink" = ["profiles/*.json"]
```

Commit + push to `feat/pixelpilot-managed-service`; record the new HEAD as the
package pin. (Working tree is currently clean at `be945ff`; the pin becomes the
post-edit commit.)

### 2. sbc-groundstations — new `package/fpvd/`

**`package/fpvd/fpvd.mk`** — mirror `wfb-server`'s python-package shape:

- `FPVD_VERSION = <new fpvd HEAD after the pyproject commit>`
- `FPVD_SITE = https://github.com/gilankpam/fpvd.git`, `FPVD_SITE_METHOD = git`
- `FPVD_SUBDIR = gs` (build from the `gs/` subtree)
- `FPVD_SETUP_TYPE = pep517`
- `FPVD_LICENSE` per the fpvd repo
- `FPVD_DEPENDENCIES = wfb-server wifibroadcast-ng` — supplies the `wfb_ng`
  module + wfb binaries/keys, and (critically) forces fpvd to install **after**
  `wifibroadcast-ng`, which the S98 removal relies on.
- `$(eval $(python-package))`

Install steps beyond the wheel (sourced from the **fetched tree**, single source
of truth that always matches the pin — same approach used for the Geist font):

- `FPVD_INSTALL_INIT_SYSV`: install `$(@D)/gs/scripts/S99fpvd` →
  `/etc/init.d/S99fpvd`.
- `FPVD_POST_INSTALL_TARGET_HOOK`:
  - `mkdir -p $(TARGET_DIR)/etc/fpvd`
  - install `$(@D)/gs/etc/defaults.json` → `/etc/fpvd/defaults.json`
  - install `$(@D)/deploy/gs/config.json` → `/etc/fpvd/config.json`
  - **handoff:** `rm -f $(TARGET_DIR)/etc/init.d/S98wifibroadcast` so only
    `S99fpvd` brings up the wfb data plane. Keep the wifibroadcast-ng binaries,
    keys, and `/etc/wifibroadcast.cfg` (fpvd regenerates the cfg at runtime via
    its `--cfg-out`).

No manual profile copy is needed — change #1 makes setuptools bundle them.

**`package/fpvd/Config.in`**:

```
config BR2_PACKAGE_FPVD
	bool "fpvd"
	depends on BR2_PACKAGE_PYTHON3
	depends on BR2_PACKAGE_WFB_SERVER
	depends on BR2_PACKAGE_WIFIBROADCAST_NG
	help
	  fpvd ground-station supervisor (Python). Owns the wfb data plane,
	  spawns/supervises pixelpilot, and serves the GS HTTP API on :8080.
```

(Host build-backend selects for pep517 + setuptools backend —
`host-python-setuptools`/`wheel` etc. — to be confirmed against Buildroot
2025.08 at first build; add whatever the pep517 infra requires.)

### 3. sbc-groundstations — wiring

- Add `source ".../package/fpvd/Config.in"` to the root `Config.in`.
- Enable `BR2_PACKAGE_FPVD=y` in `configs/radxa_zero3_defconfig`.

## Why the chosen handoff (Fork #2 = A)

fpvd removing `S98wifibroadcast` in its own post-install keeps the entire "fpvd
is the GS supervisor" decision in one package, avoids a layering inversion
(`wifibroadcast-ng` stays fpvd-agnostic and standalone-usable), auto-reverts when
`BR2_PACKAGE_FPVD=n`, and matches `deploy.sh`. Build order is guaranteed because
fpvd depends on `wifibroadcast-ng`. Rejected: runtime-kill (racy at boot — S98
starts wfb before S99fpvd) and board `post-build.sh` (buries the handoff away
from the package).

## Boot model (resulting image)

`S99fpvd` → `start-stop-daemon … /usr/bin/fpvd --defaults /etc/fpvd/defaults.json
--config /etc/fpvd/config.json --cfg-out /etc/wifibroadcast.cfg --port 8080`.
fpvd renders `/etc/wifibroadcast.cfg`, brings up wfb_rx/wfb_tx via `wfb_ng`, and
spawns/supervises pixelpilot. No `S98wifibroadcast`, no pixelpilot init.

## Verification

1. **Build:** `PIXELPILOT_OVERRIDE_SRCDIR` unset; build the image (or at least
   `make fpvd` after a `fpvd-dirclean`). Confirm the wheel builds via pep517.
2. **Image contents** (inspect `$(TARGET_DIR)` / rootfs):
   - `fpvdgs/` in target site-packages, including
     `fpvdgs/dynlink/profiles/m8812eu2.json` (proves change #1).
   - `/usr/bin/fpvd` and `/usr/bin/fpvd-runner` exist and have a target-python
     shebang.
   - `/etc/init.d/S99fpvd`, `/etc/fpvd/defaults.json`, `/etc/fpvd/config.json`
     present.
   - `/etc/init.d/S98wifibroadcast` **absent**; `wfb_rx`/`wfb_tx`/`wfb_keygen`
     still present.
3. **On GS (flash or deploy):** boot, then
   - `ps w | grep fpvdgs.supervisor` → running
   - `curl -s http://127.0.0.1:8080/status` → JSON
   - `pidof pixelpilot` → running (spawned by fpvd)
   - `pidof wfb_rx wfb_tx` → running
   - no second wfb instance from a stray S98.
4. **Revert check:** `BR2_PACKAGE_FPVD=n` rebuild → `S98wifibroadcast` returns,
   no fpvd artifacts.
