#!/bin/sh

while true
do
  test -r /etc/default/citruspilot && . /etc/default/citruspilot
  /usr/bin/citrusplay $CITRUSPLAY_ARGS
  rc=$?
  if [ $rc = 2 -o $rc = 143 -o $rc = 137 ]
  then
    echo "Citruspilot exited: $rc, skip restart ...."
    exit 2
  fi
  echo "Citruspilot exited: $rc, restart ...."
  sleep 1
done
