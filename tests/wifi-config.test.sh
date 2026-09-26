#!/bin/sh
# Host-side tests for board/common/overlay/usr/sbin/wifi-config, the
# /config/wifi.toml -> wpa_supplicant/dnsmasq generator run by S39wifi.
#
#   sh tests/wifi-config.test.sh
#
# awk is run as `gawk --posix` when gawk is around, so a GNU-only construct
# fails here instead of on the target's BusyBox awk.

cd "$(dirname "$0")/.." || exit 1
GEN=$PWD/board/common/overlay/usr/sbin/wifi-config
DEFAULTS=$PWD/board/common/overlay/usr/share/config-defaults/wifi.toml

T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT

if command -v gawk >/dev/null; then
	mkdir "$T/bin"
	printf '#!/bin/sh\nexec gawk --posix "$@"\n' >"$T/bin/awk"
	chmod +x "$T/bin/awk"
	PATH=$T/bin:$PATH
fi

pass=0
fail=0
name=

# gen <toml-text>: write the toml, run the generator into $T/out.
gen() {
	rm -rf "$T/out"
	printf '%s\n' "$1" >"$T/wifi.toml"
	sh "$GEN" "$T/wifi.toml" "$T/out" 2>"$T/stderr"
}

ok() { pass=$((pass + 1)); }
ko() { fail=$((fail + 1)); echo "FAIL [$name] $*"; }

# has <file> <line>: the generated file contains that exact line.
has() {
	grep -qxF -- "$2" "$T/out/$1" 2>/dev/null && ok || {
		ko "$1 lacks: $2"
		sed 's/^/    | /' "$T/out/$1" 2>/dev/null
	}
}
lacks() { grep -qxF -- "$2" "$T/out/$1" 2>/dev/null && ko "$1 has: $2" || ok; }
exists() { [ -f "$T/out/$1" ] && ok || ko "$1 missing"; }
absent() { [ -e "$T/out/$1" ] && ko "$1 should not exist" || ok; }
warns() { grep -qi -- "$1" "$T/stderr" && ok || ko "no warning matching '$1' (stderr: $(cat "$T/stderr"))"; }
quiet() { [ -s "$T/stderr" ] && ko "unexpected stderr: $(cat "$T/stderr")" || ok; }

# ── The shipped default reproduces the old static hotspot ────────────────────
name=defaults
rm -rf "$T/out"
sh "$GEN" "$DEFAULTS" "$T/out" 2>"$T/stderr"
quiet
has wifi.env "MODE=ap"
has wifi.env "AP_ADDRESS=10.18.0.1"
has wifi.env "AP_NETMASK=255.255.255.0"
has wifi.env "CLIENT_TIMEOUT=30"
has wpa_ap.conf "    mode=2"
has wpa_ap.conf "    frequency=2437"
has wpa_ap.conf '    ssid="OpenIPC GS"'
has wpa_ap.conf '    psk="12345678"'
has dnsmasq.conf "interface=wlan0"
has dnsmasq.conf "dhcp-range=10.18.0.10,10.18.0.100,255.255.255.0,1h"
has dnsmasq.conf "address=/#/10.18.0.1"
has dnsmasq.conf "dhcp-option=option:router,10.18.0.1"
has dnsmasq.conf "dhcp-option=option:dns-server,10.18.0.1"
absent wpa_client.conf

# ── A missing file means all defaults, silently ──────────────────────────────
name=missing-file
rm -rf "$T/out"
sh "$GEN" "$T/does-not-exist.toml" "$T/out" 2>"$T/stderr"
has wifi.env "MODE=ap"
has wpa_ap.conf '    ssid="OpenIPC GS"'

# ── Every AP field is honoured ───────────────────────────────────────────────
name=ap-custom
gen 'mode = "ap"
[ap]
ssid = "My GS"
password = "hunter2hunter2"
channel = 11
address = "192.168.50.1"
netmask = "255.255.0.0"
dhcp_start = "192.168.50.100"
dhcp_end = "192.168.50.200"'
quiet
has wifi.env "MODE=ap"
has wifi.env "AP_ADDRESS=192.168.50.1"
has wifi.env "AP_NETMASK=255.255.0.0"
has wpa_ap.conf "    frequency=2462"
has wpa_ap.conf '    ssid="My GS"'
has wpa_ap.conf '    psk="hunter2hunter2"'
has dnsmasq.conf "dhcp-range=192.168.50.100,192.168.50.200,255.255.0.0,1h"
has dnsmasq.conf "address=/#/192.168.50.1"
has dnsmasq.conf "dhcp-option=option:router,192.168.50.1"

# ── Channel 1 and 13 are the ends of the range ───────────────────────────────
name=channel-1
gen '[ap]
channel = 1'
has wpa_ap.conf "    frequency=2412"
name=channel-13
gen '[ap]
channel = 13'
has wpa_ap.conf "    frequency=2472"

# ── Client mode, with the AP still generated for the fallback ────────────────
name=client
gen 'mode = "client"
[client]
ssid = "HomeRouter"
password = "correcthorse"
fallback_timeout = 45'
quiet
has wifi.env "MODE=client"
has wifi.env "CLIENT_TIMEOUT=45"
has wpa_client.conf '    ssid="HomeRouter"'
has wpa_client.conf '    psk="correcthorse"'
lacks wpa_client.conf "    mode=2"
exists wpa_ap.conf
exists dnsmasq.conf

# ── A client network with no password is an open network ─────────────────────
name=client-open
gen 'mode = "client"
[client]
ssid = "CafeWifi"
password = ""'
quiet
has wpa_client.conf '    ssid="CafeWifi"'
has wpa_client.conf "    key_mgmt=NONE"

# ── Off ──────────────────────────────────────────────────────────────────────
name=off
gen 'mode = "off"'
quiet
has wifi.env "MODE=off"

# ── TOML syntax: comments, spacing, single quotes, escapes ───────────────────
name=syntax
gen '# a comment
   mode="ap"   # trailing comment
[ap]   # section comment
ssid = "Hash # inside"
password='"'"'lit#eral1'"'"'
channel=6'
quiet
has wpa_ap.conf '    ssid="Hash # inside"'
has wpa_ap.conf '    psk="lit#eral1"'

name=escapes
gen '[ap]
ssid = "Say \"hi\" \\o/"'
quiet
has wpa_ap.conf '    ssid="Say "hi" \o/"'

# ── Keys are per section: [client].ssid does not leak into [ap] ──────────────
name=sections
gen '[client]
ssid = "HomeRouter"
[ap]
password = "apapapap"'
has wpa_ap.conf '    ssid="OpenIPC GS"'
has wpa_ap.conf '    psk="apapapap"'

# ── Windows line endings (file edited in Notepad) ────────────────────────────
name=crlf
printf 'mode = "client"\r\n[client]\r\nssid = "HomeRouter"\r\npassword = "correcthorse"\r\n' >"$T/wifi.toml"
rm -rf "$T/out"
sh "$GEN" "$T/wifi.toml" "$T/out" 2>"$T/stderr"
quiet
has wifi.env "MODE=client"
has wpa_client.conf '    ssid="HomeRouter"'
has wpa_client.conf '    psk="correcthorse"'

# ── UTF-8 BOM (also Notepad) ─────────────────────────────────────────────────
name=bom
printf '\357\273\277mode = "off"\n' >"$T/wifi.toml"
rm -rf "$T/out"
sh "$GEN" "$T/wifi.toml" "$T/out" 2>"$T/stderr"
has wifi.env "MODE=off"

# ── Bad values warn and fall back instead of breaking wifi ───────────────────
name=bad-mode
gen 'mode = "hotspot"'
warns mode
has wifi.env "MODE=ap"

name=client-no-ssid
gen 'mode = "client"
[client]
password = "correcthorse"'
warns ssid
has wifi.env "MODE=ap"
absent wpa_client.conf

name=client-short-password
gen 'mode = "client"
[client]
ssid = "HomeRouter"
password = "short"'
warns password
has wifi.env "MODE=ap"

name=ap-short-password
gen '[ap]
password = "short"'
warns password
has wpa_ap.conf '    psk="12345678"'

name=ap-long-password
gen "[ap]
password = \"$(printf '%064d' 0)\""
warns password
has wpa_ap.conf '    psk="12345678"'

name=ap-empty-ssid
gen '[ap]
ssid = ""'
warns ssid
has wpa_ap.conf '    ssid="OpenIPC GS"'

name=bad-channel
gen '[ap]
channel = 36'
warns channel
has wpa_ap.conf "    frequency=2437"

name=bad-channel-text
gen '[ap]
channel = "six"'
warns channel
has wpa_ap.conf "    frequency=2437"

name=bad-address
gen '[ap]
address = "10.18.0.300"
netmask = "255.255.255"
dhcp_start = "abc"
dhcp_end = ""'
warns address
warns netmask
warns dhcp_start
warns dhcp_end
has wifi.env "AP_ADDRESS=10.18.0.1"
has wifi.env "AP_NETMASK=255.255.255.0"
has dnsmasq.conf "dhcp-range=10.18.0.10,10.18.0.100,255.255.255.0,1h"

name=bad-timeout
gen '[client]
fallback_timeout = "soon"'
warns fallback_timeout
has wifi.env "CLIENT_TIMEOUT=30"

name=zero-timeout
gen '[client]
fallback_timeout = 0'
warns fallback_timeout
has wifi.env "CLIENT_TIMEOUT=30"

echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
