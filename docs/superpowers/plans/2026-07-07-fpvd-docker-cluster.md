# fpvd Docker Image (Cluster Mode, x86-64 PC) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Package `fpvd` as a Docker image that runs the wfb ground-station cluster aggregator/distributor on an x86-64 PC, drives the OpenWRT node's radios over SSH, and exposes decoded RTP video on host UDP `5600` plus the HTTP API on `8080`.

**Architecture:** Multi-stage Docker build. The builder (`debian:bookworm`) compiles the `wfb_rx`/`wfb_tx`/`wfb_tun`/`wfb_tx_cmd`/`wfb_keygen` binaries from the pinned `gilankpam/wfb-ng` fork and builds a wheel of the pure-stdlib `fpvdgs` Python package from the pinned `gilankpam/fpvd` fork. The slim runtime (`debian:bookworm-slim`) carries only those binaries, the wfb runtime shared libs, an SSH client, and the fpvd wheel installed into a venv. The container runs with `--network host` (required: `derive_server_address` must resolve the PC's real LAN IP for the node's return frames, and the video leg emits RTP to `127.0.0.1:5600` which only host networking exposes) plus `--cap-add NET_ADMIN --device /dev/net/tun` for the tunnel leg. Config and secrets are mounted at runtime, never baked in.

**Tech Stack:** Docker (multi-stage), Debian bookworm, Python 3.11, C/C++ toolchain (`make all_bin`), docker-compose.

## Global Constraints

- **Base images:** builder `debian:bookworm`, runtime `debian:bookworm-slim` (Debian 12 ships Python 3.11, satisfying fpvd's `requires-python >=3.11`).
- **Pinned refs (overridable via build args):**
  - wfb-ng: `https://github.com/gilankpam/wfb-ng.git` @ `2631e0d26fe070341cc945c3d12c85d24ed2e007`
  - fpvd: `https://github.com/gilankpam/fpvd.git` @ `98c73b7dc0bd73bdc1f2d067a9569746bbd6beae`
- **wfb binary dir is hard-coded** to `/usr/bin` in `fpvdgs/wfb/graph.py` (`WFB_BIN_DIR`). The binaries MUST land in `/usr/bin`.
- **GS key path is hard-coded** to `/etc/gs.key` in `graph.py` (`GS_KEY`).
- **fpvdgs is pure Python stdlib** — no third-party runtime deps; the wheel is self-contained.
- **Networking is `--network host`** — not negotiable for cluster mode (see Architecture).
- **No secrets in image layers** — `config.json`, `gs.key`, and the SSH key are always mounted.
- **All build context lives under `docker/fpvd/`.** The Dockerfile clones both source repos itself, so the build context stays tiny (no repo source is copied in).

---

## File Structure

- `docker/fpvd/Dockerfile` — multi-stage build (builder compiles wfb + fpvd wheel; runtime assembles the slim image).
- `docker/fpvd/.dockerignore` — keep the build context minimal.
- `docker/fpvd/config.cluster.example.json` — cluster config template the user copies and edits.
- `docker/fpvd/docker-compose.yml` — the canonical run: host network, caps, tun device, volume mounts.
- `docker/fpvd/README.md` — build + run instructions, secret provisioning, host prerequisites.

---

### Task 1: Multi-stage Dockerfile (builder + runtime)

**Files:**
- Create: `docker/fpvd/Dockerfile`
- Create: `docker/fpvd/.dockerignore`

**Interfaces:**
- Consumes: nothing (first task).
- Produces: a buildable image tag `fpvd:local` containing `/usr/bin/wfb_rx`, `/usr/bin/wfb_tx`, `/usr/bin/wfb_tun`, `/usr/bin/wfb_tx_cmd`, `/usr/bin/wfb_keygen` and a `fpvd` executable on PATH (from `/opt/venv/bin`). Default `ENTRYPOINT` runs `fpvd --config /etc/fpvd/config.json --port 8080` (logs to stderr → captured by `docker logs`). The `fpvd --dump-config` subcommand prints the default config JSON and exits 0 without needing a config file or network — used as the smoke test.

- [ ] **Step 1: Write `.dockerignore`**

Create `docker/fpvd/.dockerignore` so only the Dockerfile and small text files form the context (the Dockerfile clones source repos itself):

```
etc/
*.key
id_*
README.md
```

- [ ] **Step 2: Write the Dockerfile**

Create `docker/fpvd/Dockerfile`:

```dockerfile
# syntax=docker/dockerfile:1

########################  builder  ########################
FROM debian:bookworm AS builder

ARG WFB_NG_REF=2631e0d26fe070341cc945c3d12c85d24ed2e007
ARG FPVD_REF=98c73b7dc0bd73bdc1f2d067a9569746bbd6beae

RUN apt-get update && apt-get install -y --no-install-recommends \
        git ca-certificates build-essential g++ make \
        python3 python3-venv python3-pip \
        libpcap-dev libsodium-dev libevent-dev \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /src

# wfb-ng binaries. Keep .git so the Makefile's version.py step resolves a
# version; make all_bin builds wfb_rx wfb_tx wfb_keygen wfb_tx_cmd wfb_tun.
RUN git clone https://github.com/gilankpam/wfb-ng.git wfb-ng \
    && git -C wfb-ng checkout "${WFB_NG_REF}"
RUN make -C wfb-ng all_bin

# fpvd wheel. fpvdgs is pure stdlib, so --no-deps yields a complete wheel.
RUN git clone https://github.com/gilankpam/fpvd.git fpvd \
    && git -C fpvd checkout "${FPVD_REF}"
RUN python3 -m venv /opt/venv \
    && /opt/venv/bin/pip install --no-cache-dir --upgrade pip setuptools wheel \
    && /opt/venv/bin/pip wheel --no-deps --no-cache-dir -w /wheels ./fpvd/gs

########################  runtime  ########################
FROM debian:bookworm-slim AS runtime

RUN apt-get update && apt-get install -y --no-install-recommends \
        python3 python3-venv \
        openssh-client iproute2 \
        libpcap0.8 libsodium23 libevent-2.1-7 libevent-pthreads-2.1-7 \
    && rm -rf /var/lib/apt/lists/*

# wfb binaries must live in /usr/bin (graph.WFB_BIN_DIR is hard-coded).
COPY --from=builder /src/wfb-ng/wfb_rx     /usr/bin/wfb_rx
COPY --from=builder /src/wfb-ng/wfb_tx     /usr/bin/wfb_tx
COPY --from=builder /src/wfb-ng/wfb_tun    /usr/bin/wfb_tun
COPY --from=builder /src/wfb-ng/wfb_tx_cmd /usr/bin/wfb_tx_cmd
COPY --from=builder /src/wfb-ng/wfb_keygen /usr/bin/wfb_keygen

# fpvd venv (fpvd + fpvd-stats console scripts).
COPY --from=builder /opt/venv /opt/venv
COPY --from=builder /wheels /wheels
RUN /opt/venv/bin/pip install --no-cache-dir --no-index --find-links /wheels fpvdgs \
    && rm -rf /wheels
ENV PATH="/opt/venv/bin:${PATH}"

EXPOSE 8080/tcp 5600/udp
ENTRYPOINT ["fpvd", "--config", "/etc/fpvd/config.json", "--port", "8080"]
```

- [ ] **Step 3: Build the image**

Run:
```bash
cd docker/fpvd
docker build -t fpvd:local .
```
Expected: build completes with `naming to docker.io/library/fpvd:local`. If `make all_bin` fails on a missing header, add the corresponding `-dev` package in the builder `apt-get` line and rebuild.

- [ ] **Step 4: Smoke-test the wfb binaries are present, executable, and link cleanly**

Run:
```bash
docker run --rm --entrypoint sh fpvd:local -c \
  'for b in wfb_rx wfb_tx wfb_tun wfb_tx_cmd wfb_keygen; do \
     ldd /usr/bin/$b >/dev/null && echo "$b OK"; done'
```
Expected: five `… OK` lines and no `not found` in the ldd output. If a lib is `not found`, add its runtime package (e.g. `libpcap0.8`, `libsodium23`, `libevent-2.1-7`) to the runtime `apt-get` line and rebuild.

- [ ] **Step 5: Smoke-test fpvd runs**

Run:
```bash
docker run --rm --entrypoint fpvd fpvd:local --dump-config
```
Expected: prints the default config JSON (a block starting with `{` and containing `"pixelpilot"`), exits 0. This proves the Python package imports and the console script is on PATH.

- [ ] **Step 6: Commit**

```bash
git add docker/fpvd/Dockerfile docker/fpvd/.dockerignore
git commit -m "feat(docker): multi-stage fpvd image (wfb binaries + fpvd wheel)"
```

---

### Task 2: Cluster config template

**Files:**
- Create: `docker/fpvd/config.cluster.example.json`

**Interfaces:**
- Consumes: the `fpvd:local` image from Task 1 (uses its Python to validate).
- Produces: a config file that passes `fpvdgs.schema.validate_effective` when deep-merged onto the code defaults. It sets `link.cards` to a single remote OpenWRT card over SSH, `link.serverAddress: null` (host-net derivation is correct), and `pixelpilot.enabled: false`.

- [ ] **Step 1: Write the example config**

Create `docker/fpvd/config.cluster.example.json`. Base it on `package/fpvd/files/config.json`, changing only the `link.cards`, `link.serverAddress`, and `pixelpilot.enabled` fields (all other blocks keep the repo defaults):

```json
{
  "link": {
    "channel": 132,
    "width": 20,
    "txPowerDbm": null,
    "region": "US",
    "linkId": 7669206,
    "beamforming": { "enabled": false },
    "cards": [
      {
        "host": "192.168.1.1",
        "iface": "wlan0",
        "sshUser": "root",
        "sshPort": 22,
        "sshKey": "/etc/fpvd/id_node"
      }
    ],
    "serverAddress": null,
    "videoEncryption": false
  },
  "wfb": {
    "profile": "gs",
    "mavlink": { "peer": "connect://127.0.0.1:14550" },
    "txSelector": { "rssiDeltaDb": 3, "counterRelDelta": 0.1, "counterAbsDelta": 3 },
    "raw": {}
  },
  "drone": { "host": "10.5.0.10", "apiPort": 8080 },
  "dynamicLink": { "enabled": false },
  "idrForward": { "enabled": true, "port": 11223 },
  "connectionMonitor": { "enabled": true },
  "pixelpilot": {
    "enabled": false,
    "bin": "/usr/bin/pixelpilot",
    "rtpPort": 5600,
    "codec": "h265",
    "screenMode": "1920x1080@60"
  }
}
```

- [ ] **Step 2: Validate it against the fpvd schema inside the image**

Run (mount the example as the container's config and run the same validation `build_app` does):
```bash
docker run --rm -v "$PWD/docker/fpvd/config.cluster.example.json:/etc/fpvd/config.json:ro" \
  --entrypoint python3 fpvd:local -c \
  'from fpvdgs.config import ConfigStore; from fpvdgs import schema; \
   cfg = ConfigStore.load("/etc/fpvd/config.json").effective(); \
   schema.validate_effective(cfg); \
   assert cfg["link"]["cards"][0]["host"] == "192.168.1.1"; \
   assert cfg["pixelpilot"]["enabled"] is False; \
   print("config OK")'
```
Expected: `config OK`, exit 0. If it raises `SchemaError`, read the message and correct the offending field (e.g. `link.region`/`link.channel` are required; `link.width` must be one of the schema's valid widths).

- [ ] **Step 3: Commit**

```bash
git add docker/fpvd/config.cluster.example.json
git commit -m "feat(docker): cluster-mode fpvd config template"
```

---

### Task 3: docker-compose and README

**Files:**
- Create: `docker/fpvd/docker-compose.yml`
- Create: `docker/fpvd/README.md`

**Interfaces:**
- Consumes: `fpvd:local` (Task 1), `config.cluster.example.json` (Task 2).
- Produces: a compose service `fpvd` that builds the image, runs it with `network_mode: host`, `cap_add: [NET_ADMIN]`, `devices: [/dev/net/tun]`, and mounts host `./etc` → `/etc/fpvd` plus `./etc/gs.key` → `/etc/gs.key:ro`. README documents the full run.

- [ ] **Step 1: Write the compose file**

Create `docker/fpvd/docker-compose.yml`:

```yaml
services:
  fpvd:
    build:
      context: .
      dockerfile: Dockerfile
    image: fpvd:local
    # Host networking is required: derive_server_address must resolve the
    # PC's real LAN IP for the OpenWRT node's return frames, and the video
    # leg emits RTP to 127.0.0.1:5600 which only host networking exposes.
    network_mode: host
    # The tunnel leg opens /dev/net/tun for the drone return channel.
    cap_add:
      - NET_ADMIN
    devices:
      - /dev/net/tun
    volumes:
      # config.json, id_node (SSH key) live here.
      - ./etc:/etc/fpvd:ro
      # graph.GS_KEY is hard-coded to /etc/gs.key.
      - ./etc/gs.key:/etc/gs.key:ro
    restart: unless-stopped
```

- [ ] **Step 2: Validate the compose file parses**

Run:
```bash
docker compose -f docker/fpvd/docker-compose.yml config >/dev/null && echo "compose OK"
```
Expected: `compose OK`, exit 0. (This validates YAML + schema without starting anything.)

- [ ] **Step 3: Write the README**

Create `docker/fpvd/README.md`:

````markdown
# fpvd in Docker (cluster mode, x86-64 PC)

Runs the fpvd ground-station supervisor on a PC in **cluster mode**: the
WiFi radios live on an OpenWRT router reachable from this PC. The
container runs the wfb aggregator/distributor locally and drives the
router's forwarders/injectors over SSH. Decoded RTP video is exposed on
the host at **`udp://127.0.0.1:5600`**; the HTTP API on **`:8080`**.

No WiFi adapter is attached to the PC.

## Prerequisites

- The `tun` module loaded on the host (for the tunnel leg):
  ```sh
  sudo modprobe tun
  ```
- An OpenWRT node already running wfb-ng (`wfb_rx`/`wfb_tx`/`iw` present),
  reachable from this PC, with your SSH public key authorized for
  `root@<router>`.

## Provide secrets (mounted, never baked into the image)

```sh
cd docker/fpvd
mkdir -p etc
cp config.cluster.example.json etc/config.json          # edit router IP, channel, region, linkId
cp ../../package/wifibroadcast-ng/files/gs.key etc/gs.key # must match the drone
cp ~/.ssh/id_router etc/id_node                          # SSH key authorized on the router
chmod 600 etc/id_node
```

Edit `etc/config.json`:
- `link.cards[0].host` → the router's IP.
- `link.cards[0].iface` → the router's monitor-mode interface.
- `link.channel` / `link.region` / `link.linkId` → match the drone.

## Run

```sh
docker compose up --build
```

- RTP video: `udp://127.0.0.1:5600` (e.g. `ffplay -fflags nobuffer udp://127.0.0.1:5600`).
- fpvd API: `curl http://127.0.0.1:8080/config`.
- Logs: `docker compose logs -f`.

## Notes

- **Host networking is required** and is why no `-p` port mapping is
  needed — `5600` and `8080` are already on the host. Bridge mode breaks
  the node's return-frame routing and cannot expose the loopback RTP
  stream.
- To rebuild against newer source, pass build args:
  ```sh
  docker compose build --build-arg FPVD_REF=<sha> --build-arg WFB_NG_REF=<sha>
  ```
````

- [ ] **Step 4: Commit**

```bash
git add docker/fpvd/docker-compose.yml docker/fpvd/README.md
git commit -m "feat(docker): compose file + README for cluster fpvd"
```

---

## Self-Review

**Spec coverage:**
- Cluster aggregator/distributor runs locally, radios over SSH → Task 1 (binaries + fpvd), Task 2 (remote `link.cards`). ✓
- Host networking (return-path routing + RTP exposure) → Task 3 compose `network_mode: host`; README rationale. ✓
- Multi-stage x86-64 build from source → Task 1. ✓
- Secrets mounted at runtime → Task 3 volumes + README; `.dockerignore` keeps them out of context. ✓
- tun device for tunnel leg → Task 3 `cap_add`/`devices`; README `modprobe tun`. ✓
- RTP 5600 + API 8080 → hard-coded sink + `--port 8080`; README verification commands. ✓
- Deliverables (Dockerfile, compose, example config, .dockerignore, README) → Tasks 1–3. ✓

**Placeholder scan:** No TBD/TODO; every file has complete content; example IPs (`192.168.1.1`) are clearly-labeled user-edit points documented in the README, not plan placeholders. ✓

**Type consistency:** `WFB_BIN_DIR=/usr/bin` and `GS_KEY=/etc/gs.key` from `graph.py` are honored by the COPY targets and the compose mount. The validation command uses the real `ConfigStore.load(...).effective()` + `schema.validate_effective(...)` path from `supervisor.build_app`. Console script name `fpvd` matches `pyproject.toml` `[project.scripts]`. ✓
