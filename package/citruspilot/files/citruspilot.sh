#!/bin/sh
#
# Supervisor for citrusplay: restart it if it crashes, but exit cleanly (without
# restarting) when the init script stops us. start-stop-daemon -K signals THIS
# wrapper, so we must trap that and forward it to the player — otherwise the
# wrapper dies and orphans citrusplay, which keeps holding DRM master + the
# screen. citrusplay catches SIGTERM and exits 0, so we run it in the background
# and wait, letting the trap fire while we block.

child=

terminate() {
  [ -n "$child" ] && kill -TERM "$child" 2>/dev/null
  wait "$child" 2>/dev/null
  exit 0
}
trap terminate TERM INT

while true
do
  test -r /etc/default/citruspilot && . /etc/default/citruspilot
  /usr/bin/citrusplay $CITRUSPLAY_ARGS &
  child=$!
  wait "$child"
  rc=$?
  echo "Citruspilot exited: $rc, restart ...."
  sleep 1
done
