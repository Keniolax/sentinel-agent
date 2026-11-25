#!/bin/sh
# ask:        start the mock orders API and Ollama on loopback, then answer $QUESTION once
#             and exit. Azure Container Apps jobs have no sidecar that stops with the main
#             container, so the orders API runs as a background process here.
# orders-api: run the mock orders API on its own (local testing).
set -eu
wait_for() {
  i=0
  # Any HTTP answer, even 404, means the server is up.
  until python3 -c "
import urllib.error, urllib.request
try: urllib.request.urlopen('$1', timeout=2)
except urllib.error.HTTPError: pass" 2>/dev/null; do
    i=$((i + 1)); [ "$i" -lt 60 ] || { echo "{\"app\":\"sentinel-agent\",\"event\":\"error\",\"reason\":\"$2 did not start\"}"; exit 1; }
    sleep 1
  done
}
case "${1:-ask}" in
  ask)
    : "${QUESTION:?set QUESTION}"
    python3 -m sentinel orders-api >/tmp/orders-api.log 2>&1 &
    /opt/ollama/bin/ollama serve >/tmp/ollama.log 2>&1 &
    wait_for http://127.0.0.1:8081/ "orders api"
    wait_for http://127.0.0.1:11434/api/version ollama
    exec python3 -m sentinel ask "$QUESTION"
    ;;
  orders-api)
    exec python3 -m sentinel orders-api
    ;;
  *)
    echo "usage: ask | orders-api" >&2; exit 2
    ;;
esac
