# fpvd GS Buildroot Package Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Bake the fpvd GS Python supervisor (`fpvdgs`) into the Radxa Zero3 ground-station image as `BR2_PACKAGE_FPVD`, making fpvd the sole GS supervisor on boot.

**Architecture:** A Buildroot `python-package` mirroring `wfb-server` builds the `gs/` subtree of the fpvd repo (pep517). It installs the module + console scripts, the `S99fpvd` init script, and `/etc/fpvd/*.json`, then performs the GS handoff by removing `wifibroadcast-ng`'s `S98wifibroadcast` (fpvd runs the wfb data plane in-process via `wfb_ng`). A one-line fix to fpvd's `pyproject.toml` makes the dynlink profile JSON ship in the wheel.

**Tech Stack:** Buildroot 2025.08.1, Python 3 (`python-package`/pep517), git package source, SysV init.

**Spec:** `docs/superpowers/specs/2026-06-03-fpvd-gs-buildroot-package-design.md`

**Decisions locked:** Fork #1 = fix fpvd pyproject package-data. Fork #2 = fpvd removes `S98wifibroadcast` in its own post-install. Pin = `feat/pixelpilot-managed-service` HEAD (after the pyproject commit).

**Repo paths:**
- fpvd repo: `/home/gilankpam/Projects/drone/fpvd`
- sbc-groundstations: `/home/gilankpam/Projects/drone/sbc-groundstations-gilankpam`

---

### Task 1: Ship dynlink profiles in the fpvd wheel (fpvd repo)

The dynlink profile JSON is loaded relative to the installed module
(`gs/fpvdgs/dynlink/config_build.py:28`), but `profiles/` has no `__init__.py`
and `pyproject.toml` declares no package-data, so a stock wheel omits it. Add
package-data, verify the wheel bundles it, then commit + push to get the pin.

**Files:**
- Modify: `/home/gilankpam/Projects/drone/fpvd/gs/pyproject.toml`

- [ ] **Step 1: Confirm working tree is clean and on the right branch**

Run:
```bash
cd /home/gilankpam/Projects/drone/fpvd && git branch --show-current && git status --short
```
Expected: branch `feat/pixelpilot-managed-service`, no output from `git status` (clean). If dirty, stop and resolve before continuing.

- [ ] **Step 2: Add the package-data declaration**

Append this block to `/home/gilankpam/Projects/drone/fpvd/gs/pyproject.toml` (after the existing `[tool.setuptools.packages.find]` section):

```toml
[tool.setuptools.package-data]
"fpvdgs.dynlink" = ["profiles/*.json"]
```

- [ ] **Step 3: Build a wheel and verify the JSON is bundled (the "test")**

Run:
```bash
cd /home/gilankpam/Projects/drone/fpvd/gs && \
python3 -m build --wheel --no-isolation -o /tmp/fpvd-wheel 2>/tmp/fpvd-build.log || \
{ echo "--- build module missing? install into the gs venv and retry ---"; \
  ./.venv/bin/python -m pip install -q build setuptools wheel && \
  ./.venv/bin/python -m build --wheel --no-isolation -o /tmp/fpvd-wheel; }
unzip -l /tmp/fpvd-wheel/fpvdgs-0.1.0-py3-none-any.whl | grep 'dynlink/profiles/m8812eu2.json'
```
Expected: the final `unzip -l … | grep` prints a line containing `fpvdgs/dynlink/profiles/m8812eu2.json`. If it prints nothing, the package-data glob is wrong — fix Step 2 before committing.

- [ ] **Step 4: Commit and push the fpvd fix**

Run:
```bash
cd /home/gilankpam/Projects/drone/fpvd && git add gs/pyproject.toml && \
git commit -m "$(printf 'build(gs): ship dynlink profiles in the wheel\n\nDeclare profiles/*.json as package-data for fpvdgs.dynlink so the\nradio profile JSON (loaded relative to the installed module) is\nincluded by setuptools instead of being copied separately at deploy.\n\nCo-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>')" && \
git push origin feat/pixelpilot-managed-service
```
Expected: push succeeds.

- [ ] **Step 5: Capture the new HEAD as the package pin**

Run:
```bash
cd /home/gilankpam/Projects/drone/fpvd && git rev-parse HEAD
```
Record this 40-char hash. It is the value `FPVD_VERSION` in Task 4. Call it `<FPVD_PIN>` below.

---

### Task 2: Create `package/fpvd/Config.in` (sbc-groundstations)

**Files:**
- Create: `/home/gilankpam/Projects/drone/sbc-groundstations-gilankpam/package/fpvd/Config.in`

- [ ] **Step 1: Write the Config.in**

Create `/home/gilankpam/Projects/drone/sbc-groundstations-gilankpam/package/fpvd/Config.in`:

```
config BR2_PACKAGE_FPVD
	bool "fpvd"
	depends on BR2_PACKAGE_PYTHON3
	depends on BR2_PACKAGE_WFB_SERVER
	depends on BR2_PACKAGE_WIFIBROADCAST_NG
	help
	  fpvd ground-station supervisor (Python). Owns the wfb data plane
	  in-process via the wfb_ng library, spawns and supervises the
	  pixelpilot display process, and serves the GS HTTP API on :8080.

	  Enabling fpvd retires wifibroadcast-ng's stock S98wifibroadcast
	  launcher; fpvd brings up wfb_rx/wfb_tx itself.
```

- [ ] **Step 2: Verify the file is syntactically sane**

Run:
```bash
cd /home/gilankpam/Projects/drone/sbc-groundstations-gilankpam && grep -c 'BR2_PACKAGE_FPVD' package/fpvd/Config.in
```
Expected: `1`.

---

### Task 3: Register the package in the root `Config.in`

**Files:**
- Modify: `/home/gilankpam/Projects/drone/sbc-groundstations-gilankpam/Config.in`

- [ ] **Step 1: Add the source line after the wfb-server entry**

In `/home/gilankpam/Projects/drone/sbc-groundstations-gilankpam/Config.in`, find the line:

```
source "$BR2_EXTERNAL_OPENIPC_SBC_GS_PATH/package/wfb-server/Config.in"
```

and add immediately after it:

```
source "$BR2_EXTERNAL_OPENIPC_SBC_GS_PATH/package/fpvd/Config.in"
```

- [ ] **Step 2: Verify it's wired**

Run:
```bash
cd /home/gilankpam/Projects/drone/sbc-groundstations-gilankpam && grep -n 'package/fpvd/Config.in' Config.in
```
Expected: one match showing the new `source` line.

---

### Task 4: Create `package/fpvd/fpvd.mk`

**Files:**
- Create: `/home/gilankpam/Projects/drone/sbc-groundstations-gilankpam/package/fpvd/fpvd.mk`

- [ ] **Step 1: Write the .mk**

Create `/home/gilankpam/Projects/drone/sbc-groundstations-gilankpam/package/fpvd/fpvd.mk`. Replace `<FPVD_PIN>` with the hash captured in Task 1, Step 5:

```make
################################################################################
#
# fpvd
#
################################################################################

# feat/pixelpilot-managed-service HEAD (after the dynlink package-data fix).
# Bump this hash to advance the branch.
FPVD_VERSION = <FPVD_PIN>
FPVD_SITE = https://github.com/gilankpam/fpvd.git
FPVD_SITE_METHOD = git
FPVD_SUBDIR = gs
FPVD_SETUP_TYPE = pep517

# wfb-server provides the wfb_ng Python module fpvd imports; wifibroadcast-ng
# provides the wfb_rx/wfb_tx binaries + keys fpvd drives. Depending on them also
# forces fpvd to install AFTER wifibroadcast-ng, which the S98 removal relies on.
# host-python-setuptools/wheel supply the pep517 build backend (--no-isolation).
FPVD_DEPENDENCIES = \
	wfb-server \
	wifibroadcast-ng \
	host-python-setuptools \
	host-python-wheel

define FPVD_INSTALL_INIT_SYSV
	$(INSTALL) -D -m 0755 $(@D)/gs/scripts/S99fpvd \
		$(TARGET_DIR)/etc/init.d/S99fpvd
endef

define FPVD_POST_INSTALL_TARGET_HOOK
	mkdir -p $(TARGET_DIR)/etc/fpvd

	$(INSTALL) -D -m 0644 $(@D)/gs/etc/defaults.json \
		$(TARGET_DIR)/etc/fpvd/defaults.json

	$(INSTALL) -D -m 0644 $(@D)/deploy/gs/config.json \
		$(TARGET_DIR)/etc/fpvd/config.json

	# Full GS-supervisor handoff: fpvd runs the wfb data plane in-process
	# (wfb_ng), so retire wifibroadcast-ng's stock launcher. The wfb binaries,
	# keys, and /etc/wifibroadcast.cfg from wifibroadcast-ng stay -- fpvd
	# regenerates the cfg at runtime via its --cfg-out. Reverts automatically
	# when BR2_PACKAGE_FPVD is disabled.
	rm -f $(TARGET_DIR)/etc/init.d/S98wifibroadcast
endef

FPVD_POST_INSTALL_TARGET_HOOKS += FPVD_POST_INSTALL_TARGET_HOOK

$(eval $(python-package))
```

- [ ] **Step 2: Verify the pin was filled in (no placeholder left)**

Run:
```bash
cd /home/gilankpam/Projects/drone/sbc-groundstations-gilankpam && \
grep -E '^FPVD_VERSION = [0-9a-f]{40}$' package/fpvd/fpvd.mk && echo OK || echo "PIN NOT SET"
```
Expected: prints the `FPVD_VERSION` line and `OK`. If `PIN NOT SET`, replace `<FPVD_PIN>` with the real hash.

---

### Task 5: Enable the package in the defconfig

**Files:**
- Modify: `/home/gilankpam/Projects/drone/sbc-groundstations-gilankpam/configs/radxa_zero3_defconfig`

- [ ] **Step 1: Add the enable line next to the other wfb packages**

In `/home/gilankpam/Projects/drone/sbc-groundstations-gilankpam/configs/radxa_zero3_defconfig`, find:

```
BR2_PACKAGE_WFB_SERVER=y
```

and add immediately after it:

```
BR2_PACKAGE_FPVD=y
```

- [ ] **Step 2: Verify**

Run:
```bash
cd /home/gilankpam/Projects/drone/sbc-groundstations-gilankpam && grep -n 'BR2_PACKAGE_FPVD=y' configs/radxa_zero3_defconfig
```
Expected: one match.

- [ ] **Step 3: Commit the package + wiring (sbc-groundstations)**

Stage only the fpvd-package files (leave the repo's other pending edits alone):
```bash
cd /home/gilankpam/Projects/drone/sbc-groundstations-gilankpam && \
git add package/fpvd/Config.in package/fpvd/fpvd.mk Config.in configs/radxa_zero3_defconfig && \
git commit -m "$(printf 'package/fpvd: add fpvd GS supervisor (python-package)\n\nBuilds the fpvd repo gs/ subtree (pep517) into the Radxa Zero3 image:\nthe fpvdgs module + fpvd/fpvd-runner console scripts, S99fpvd init,\nand /etc/fpvd/{defaults,config}.json. Full GS-supervisor handoff --\nremoves wifibroadcast-ng S98wifibroadcast so fpvd owns the wfb data\nplane (in-process via wfb_ng) and spawns pixelpilot.\n\nCo-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>')"
```
Expected: commit succeeds with 4 files (note: `configs/radxa_zero3_defconfig` and `Config.in` may already carry unrelated working-tree edits — if `git status` shows defconfig had prior changes, review the staged diff with `git diff --cached configs/radxa_zero3_defconfig` to confirm only the `BR2_PACKAGE_FPVD=y` line is added).

---

### Task 6: Build the package and verify the image contents

This is the authoritative test. Builds run inside the nix FHS env (cross
toolchain); the env only runs commands fed on **stdin** (per the GS deploy
memory). Ensure `PIXELPILOT_OVERRIDE_SRCDIR` is NOT exported.

**Files:** none (verification only).

- [ ] **Step 1: Build fpvd (and its deps) against the radxa defconfig**

Run:
```bash
printf '%s\n' \
  'cd /home/gilankpam/Projects/drone/sbc-groundstations-gilankpam' \
  'unset PIXELPILOT_OVERRIDE_SRCDIR' \
  'export DEFCONFIG=radxa_zero3_defconfig' \
  './build.sh fpvd; echo "FPVD_BUILD rc=$?"' \
  | nix-shell /home/gilankpam/Projects/drone/sbc-groundstations-gilankpam/shell.nix
```
Expected: ends with `FPVD_BUILD rc=0`. If the pep517 build fails complaining about a missing build backend, add the missing `host-python-*` to `FPVD_DEPENDENCIES` in Task 4 and rebuild (`make fpvd-dirclean` first).

- [ ] **Step 2: Verify the module + bundled profile JSON landed in site-packages**

Run:
```bash
cd /home/gilankpam/Projects/drone/sbc-groundstations-gilankpam && \
T=output/radxa_zero3_defconfig/target && \
find $T/usr/lib/python*/site-packages/fpvdgs -name '*.json' -path '*dynlink/profiles*'; \
ls $T/usr/lib/python*/site-packages/fpvdgs/supervisor.py
```
Expected: prints a `fpvdgs/dynlink/profiles/m8812eu2.json` path (proves Task 1 worked) and the `supervisor.py` path.

- [ ] **Step 3: Verify console scripts, init script, and config files**

Run:
```bash
cd /home/gilankpam/Projects/drone/sbc-groundstations-gilankpam && \
T=output/radxa_zero3_defconfig/target && \
ls -l $T/usr/bin/fpvd $T/usr/bin/fpvd-runner \
      $T/etc/init.d/S99fpvd \
      $T/etc/fpvd/defaults.json $T/etc/fpvd/config.json && \
head -1 $T/usr/bin/fpvd
```
Expected: all five files exist; `head -1 .../fpvd` shows a `#!.../python3` shebang.

- [ ] **Step 4: Verify the handoff — S98 gone, wfb binaries kept**

Run:
```bash
cd /home/gilankpam/Projects/drone/sbc-groundstations-gilankpam && \
T=output/radxa_zero3_defconfig/target && \
( ls $T/etc/init.d/S98wifibroadcast >/dev/null 2>&1 && echo "FAIL: S98 still present" || echo "OK: S98 removed" ) && \
ls $T/usr/bin/wfb_rx $T/usr/bin/wfb_tx $T/usr/bin/wfb_keygen
```
Expected: `OK: S98 removed`, and the three `wfb_*` binaries still exist.

---

### Task 7: Full image build + on-GS smoke test (final verification)

Optional but recommended before relying on the image. Heavy (full rootfs build).

**Files:** none.

- [ ] **Step 1: Build the full image**

Run:
```bash
printf '%s\n' \
  'cd /home/gilankpam/Projects/drone/sbc-groundstations-gilankpam' \
  'unset PIXELPILOT_OVERRIDE_SRCDIR' \
  'export DEFCONFIG=radxa_zero3_defconfig' \
  './build.sh; echo "IMG_BUILD rc=$?"' \
  | nix-shell /home/gilankpam/Projects/drone/sbc-groundstations-gilankpam/shell.nix
```
Expected: `IMG_BUILD rc=0`; image artifacts under `output/radxa_zero3_defconfig/images/`.

- [ ] **Step 2: Flash/deploy and smoke-test on the GS**

After flashing (or deploying the rootfs), on the GS (`ssh root@10.18.0.1`) verify:
```bash
ps w | grep -q '[f]pvdgs.supervisor' && echo "fpvd: running" || echo "fpvd: DOWN"
curl -s http://127.0.0.1:8080/status | head -c 200; echo
pidof pixelpilot >/dev/null && echo "pixelpilot: running" || echo "pixelpilot: DOWN"
for p in wfb_rx wfb_tx; do printf '%s=%s ' "$p" "$(pidof $p | cut -d" " -f1)"; done; echo
ls /etc/init.d/S98wifibroadcast 2>/dev/null && echo "WARN: stray S98" || echo "no S98 (good)"
```
Expected: fpvd running, `/status` returns JSON, pixelpilot running, `wfb_rx`/`wfb_tx` have PIDs, no S98.

---

## Self-Review

**Spec coverage:**
- python-package mirroring wfb-server → Task 4. ✓
- Source/pin/SUBDIR/pep517 → Task 4. ✓
- Dependencies (wfb-server, wifibroadcast-ng, host backend) → Task 4. ✓
- Install module + console scripts → `$(eval $(python-package))` (Task 4), verified Task 6 Steps 2–3. ✓
- S99fpvd init + /etc/fpvd/{defaults,config}.json → Task 4, verified Task 6 Step 3. ✓
- dynlink profiles in wheel → Task 1, verified Task 6 Step 2. ✓
- Handoff (remove S98wifibroadcast) → Task 4, verified Task 6 Step 4. ✓
- Config.in + root wiring + defconfig enable → Tasks 2, 3, 5. ✓
- Verification (build, image contents, on-GS) → Tasks 6, 7. ✓

**Placeholder scan:** `<FPVD_PIN>` is a value deterministically produced by Task 1 Step 5 and consumed in Task 4, with a guard (Task 4 Step 2) that fails loudly if left unset — not an open TODO. No other placeholders.

**Type/name consistency:** `BR2_PACKAGE_FPVD`, `FPVD_VERSION`, `FPVD_SUBDIR=gs`, `FPVD_SETUP_TYPE=pep517`, `S99fpvd`, `/etc/fpvd/{defaults,config}.json`, and `m8812eu2.json` are used identically across Config.in, fpvd.mk, defconfig, and the verification steps.
