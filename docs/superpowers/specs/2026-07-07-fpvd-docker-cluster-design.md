# fpvd Docker image (cluster mode, x86-64 PC) — design

Date: 2026-07-07

## Goal

Run the `fpvd` ground-station supervisor in a Docker container on a
development PC (x86-64), receiving a wfb link in **cluster mode** from an
OpenWRT router reachable from the container, and exposing the decoded
**RTP video on host UDP port 5600** plus the fpvd HTTP API on `:8080`.

No WiFi hardware is attached to the PC: the radios live on the OpenWRT
node. The container runs the cluster **aggregator/distributor** legs
locally and drives the node's forwarders/injectors over SSH.

## Background: how fpvd cluster mode works

fpvd (`fpvdgs`, Python ≥3.11) supervises the GS wfb data plane. When any
`link.cards` entry is remote (`host` set), `build_graph_remote`
(`gs/fpvdgs/wfb/graph.py`, `cluster.py`) renders a **cluster** graph:

- On each remote node: `wfb_rx -f` forwarders (one per card) and
  `wfb_tx -I` injectors, spawned by piping a bootstrap script over a
  **persistent SSH session** (`ssh … exec sh -s`, `cluster.NodeSession`).
  The node already has `wfb_rx`/`wfb_tx`/`iw` installed (existing wfb-ng
  OpenWRT setup) — out of scope for this image.
- On the GS (the container): per-service **aggregator** (`wfb_rx -a`) and
  **distributor** (`wfb_tx -d`) legs run locally. The video aggregator
  forwards decoded video to `127.0.0.1:5600` (`graph.VIDEO_UDP_PORT`,
  hard-coded sink `-c 127.0.0.1 -u 5600`). mavlink + tunnel legs also run.

Three legs per flight: video (rx only), mavlink (rx+tx), tunnel (rx+tx).
The **tunnel** leg opens a `tun` device for the drone return channel and
is built even when `dynamicLink.enabled` is false.

`cluster.derive_server_address(node_host, override)` decides the source IP
the node's forwarders send raw frames back to: it opens a UDP socket,
`connect()`s to the node (no packet sent), and reads the local address the
kernel would route from. `link.serverAddress` overrides it verbatim.

## Networking: host networking (required)

The container uses `--network host`. Rationale — two hard constraints:

1. **Return-path routing.** In bridge mode `derive_server_address` returns
   the container's private IP (e.g. `172.17.0.x`), which the OpenWRT node
   cannot route to; the aggregator would receive no frames. Host
   networking makes it return the PC's real LAN IP.
2. **RTP exposure.** The video leg emits to `127.0.0.1:5600` (container
   loopback). `-p 5600:5600/udp` cannot publish a loopback-bound UDP
   stream. Under host networking `127.0.0.1:5600` *is* the host loopback,
   so RTP is available to host players with no port publishing.

Host networking also gives the SSH client a direct path to the router and
puts the API on `:8080` of the host. Bridge mode was rejected: it needs a
`serverAddress` override, publishing several dynamic cluster UDP ports,
and an internal RTP relay, and still risks dropped frames.

## Image: multi-stage, x86-64

### Builder stage (`debian:bookworm`)

- `git clone https://github.com/gilankpam/wfb-ng.git`, checkout pinned
  commit `2631e0d26fe070341cc945c3d12c85d24ed2e007` (matches
  `package/wifibroadcast-ng/wifibroadcast-ng.mk`). Keep `.git` so the
  Makefile's `version.py` step resolves a version.
- `apt install`: `g++ make python3 libpcap-dev libsodium-dev
  libevent-dev`.
- `make all_bin` → `wfb_rx wfb_tx wfb_tx_cmd wfb_tun wfb_keygen`.
- Build the fpvd wheel from `gs/`: `pip wheel ./gs` (pyproject, setuptools
  backend) → `fpvdgs-0.1.0-*.whl`. fpvd source pinned to the same commit
  the repo currently uses (`package/fpvd/fpvd.mk` `FPVD_VERSION`).

### Runtime stage (`debian:bookworm-slim`)

- `apt install`: `python3` (3.11), `libpcap0.8 libsodium23 libevent-2.1-7`
  (wfb runtime libs), `openssh-client` (node sessions), `iproute2`
  (tun/link ops).
- `COPY` the five wfb binaries → `/usr/bin`.
- `pip install` the fpvdgs wheel (provides `fpvd` + `fpvd-stats` scripts).
- `ENTRYPOINT ["fpvd", "--config", "/etc/fpvd/config.json", "--port",
  "8080", "--log", "/dev/stdout"]`.

## Config & secrets: mounted at runtime

Nothing sensitive is baked in. The user mounts a host dir → `/etc/fpvd/`:

- `config.json` — cluster variant (see example below).
- `gs.key` — copied by the user from
  `package/wifibroadcast-ng/files/gs.key`; must match the drone. The
  engine reads `/etc/gs.key`, so the entrypoint/compose symlinks or the
  config points there (`graph.GS_KEY = /etc/gs.key`). Mount target
  `/etc/gs.key` directly, or bind `/etc/fpvd/gs.key` and symlink.
- `id_node` — SSH private key authorized on the OpenWRT router
  (`root@<router>`), referenced by `link.cards[].sshKey`.

Shipped example `config.cluster.example.json` differences from the SBC
default (`package/fpvd/files/config.json`):

```jsonc
{
  "link": {
    "cards": [
      { "host": "192.168.1.1", "iface": "wlan0",
        "sshUser": "root", "sshPort": 22, "sshKey": "/etc/fpvd/id_node" }
    ],
    "serverAddress": null            // host-net: derived LAN IP is correct
    // channel/width/region/linkId/videoEncryption as per drone
  },
  "pixelpilot": { "enabled": false } // no display on the PC
  // idrForward / connectionMonitor / dynamicLink left at defaults
}
```

`gs.key` path: `graph.GS_KEY` is `/etc/gs.key`. The compose file mounts
the host `./etc/gs.key` → `/etc/gs.key` (read-only) in addition to the
`/etc/fpvd` dir.

## Runtime requirements (tun device)

The tunnel leg opens `/dev/net/tun`, so the container needs:

- `--cap-add NET_ADMIN`
- `--device /dev/net/tun`

`modprobe tun` is a host responsibility (the module must be loaded on the
PC). Documented in the README.

## Deliverables

- `docker/fpvd/Dockerfile` — multi-stage build described above.
- `docker/fpvd/docker-compose.yml` — `network_mode: host`, `cap_add:
  [NET_ADMIN]`, `devices: [/dev/net/tun]`, volumes `./etc → /etc/fpvd`
  and `./etc/gs.key → /etc/gs.key:ro`, `restart: unless-stopped`.
- `docker/fpvd/config.cluster.example.json` — cluster config template.
- `docker/fpvd/.dockerignore`.
- `docker/fpvd/README.md` — build, provide `etc/{config.json,gs.key,
  id_node}`, `modprobe tun`, `docker compose up`, then play
  `udp://127.0.0.1:5600` and curl `http://127.0.0.1:8080`.

## Run shape

```sh
# one-time host prep
sudo modprobe tun

# provide secrets
mkdir -p docker/fpvd/etc
cp config.cluster.example.json docker/fpvd/etc/config.json   # edit router IP etc.
cp ../../package/wifibroadcast-ng/files/gs.key docker/fpvd/etc/gs.key
cp ~/.ssh/id_router docker/fpvd/etc/id_node

docker compose -f docker/fpvd/docker-compose.yml up --build

# RTP video:  udp://127.0.0.1:5600
# fpvd API:   http://127.0.0.1:8080/config
```

## Non-goals

- Local WiFi adapter passthrough (no cards on the PC).
- pixelpilot display / DVR inside the container.
- ARM/SBC images (buildroot already covers those).
- Provisioning the OpenWRT node's wfb-ng install or authorizing the SSH
  key on the router.

## Open risks

- `make all_bin` version stamping relies on `.git` + `python3`; verified
  the Makefile falls back gracefully, but the clone must retain `.git`.
- fpvd may reference other absolute paths (e.g. `/etc/gs.key`, wfb bin dir
  `/usr/bin`) — both satisfied by the image layout; confirm during
  implementation that no other host paths are assumed.
