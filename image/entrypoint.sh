#!/bin/sh
# ask:        start Ollama on loopback, then answer $QUESTION once and exit.
# orders-api: run the mock orders API on loopback.
set -eu
case "${1:-ask}" in
  ask)
    : "${QUESTION:?set QUESTION}"
    /opt/ollama/bin/ollama serve >/tmp/ollama.log 2>&1 &
    i=0
    until python3 -c "import urllib.request; urllib.request.urlopen('http://127.0.0.1:11434/api/version', timeout=2)" 2>/dev/null; do
      i=$((i + 1)); [ "$i" -lt 60 ] || { echo '{"app":"sentinel-agent","event":"error","reason":"ollama did not start"}'; exit 1; }
      sleep 1
    done
    exec python3 -m sentinel ask "$QUESTION"
    ;;
  orders-api)
    exec python3 -m sentinel orders-api
    ;;
  *)
    echo "usage: ask | orders-api" >&2; exit 2
    ;;
esac
