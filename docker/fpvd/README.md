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

The compose file mounts host `./etc/fpvd` → `/etc/fpvd` and host
`./etc/gs.key` → `/etc/gs.key`, so the layout is:

```sh
cd docker/fpvd
mkdir -p etc/fpvd
cp config.cluster.example.json etc/fpvd/config.json      # edit router IP, channel, region, linkId
cp ~/.ssh/id_router etc/fpvd/id_node                     # SSH key authorized on the router (sshKey path in config)
chmod 600 etc/fpvd/id_node
cp ../../package/wifibroadcast-ng/files/gs.key etc/gs.key # must match the drone
```

The whole `etc/` tree is git-ignored (it holds your keys). Create these
files **before** the first `up` — Docker bind-mounts create a directory in
their place if the source path is missing.

Edit `etc/fpvd/config.json`:
- `link.cards[0].host` → the router's IP.
- `link.cards[0].iface` → the router's monitor-mode interface.
- `link.channel` / `link.region` / `link.linkId` → match the drone.

## Run

```sh
docker compose up --build
```

- RTP video: `udp://127.0.0.1:5600` (e.g. `ffplay -fflags nobuffer udp://127.0.0.1:5600`).
- fpvd API: `curl http://127.0.0.1:8080/healthz`, `.../gs/status`, `.../gs/config`, `.../gs/nodes`.
- Logs: `docker compose logs -f`.

## Notes

- **Host networking is required** and is why no `-p` port mapping is
  needed — `5600` and `8080` are already on the host. Bridge mode breaks
  the node's return-frame routing (`derive_server_address` would hand the
  node the container's private IP) and cannot expose the loopback RTP
  stream.
- **`iw` + `NET_ADMIN` are required even with no local radio.** On startup
  the engine runs `iw reg set <link.region>` locally to set the GS
  regulatory domain. If `iw` is missing (or `NET_ADMIN` is not granted)
  this fails and the engine aborts with
  `radio_init failed for wlans=[]` — the link never comes up. The image
  ships `iw`; the compose file grants `NET_ADMIN`.
- **The build uses the host network** (`build.network: host` in the
  compose file). On hosts where Docker's default bridge can't resolve or
  reach the Debian mirror — e.g. an IPv6-only mirror, or container DNS
  returning no A records — the `apt-get` steps time out otherwise. If you
  build with plain `docker build` instead of compose, add the flag:
  ```sh
  docker build --network=host -t fpvd:local .
  ```
- To rebuild against newer source, pass build args:
  ```sh
  docker compose build --build-arg FPVD_REF=<sha> --build-arg WFB_NG_REF=<sha>
  ```
