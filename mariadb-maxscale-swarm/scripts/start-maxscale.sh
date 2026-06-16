#!/bin/sh
set -eu

MAXSCALE_PW="$(cat /run/secrets/maxscale_password)"
MAXSCALE_MONITOR_PW="$(cat /run/secrets/maxscale_monitor_password)"

sed \
  -e "s|__MAXSCALE_PASSWORD__|${MAXSCALE_PW}|g" \
  -e "s|__MAXSCALE_MONITOR_PASSWORD__|${MAXSCALE_MONITOR_PW}|g" \
  /etc/maxscale.cnf.d/maxscale.cnf.template > /etc/maxscale.cnf.d/generated-maxscale.cnf

exec maxscale -d -U maxscale -l stdout