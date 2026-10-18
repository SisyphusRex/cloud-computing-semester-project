#!/usr/bin/env bash
# Build the frontend image (frontend/Dockerfile) and check what nginx serves:
# the app, client-side routes, 404s for missing assets, health, and headers.
#   scripts/test-frontend-image.sh
#   DOCKER="sudo docker" scripts/test-frontend-image.sh
set -euo pipefail

DOCKER=${DOCKER:-docker}
IMAGE=li-frontend:test
PORT=${PORT:-18080}
API_BASE=https://203-0-113-1.sslip.io # fake; only checked in the CSP
failures=0

$DOCKER build -q -t "$IMAGE" --build-arg "VITE_API_BASE=$API_BASE" frontend > /dev/null
container=$($DOCKER run -d --rm -p "127.0.0.1:$PORT:8080" "$IMAGE")
trap '$DOCKER stop "$container" > /dev/null' EXIT

for _ in $(seq 20); do
  curl -sf "http://127.0.0.1:$PORT/health" > /dev/null && break
  sleep 0.5
done

check() {  # check <description> <command...>
  if "${@:2}"; then
    echo "  ok    $1"
  else
    echo "  FAIL  $1"
    failures=$((failures + 1))
  fi
}
status() { curl -s -o /dev/null -w '%{http_code}' "http://127.0.0.1:$PORT$1"; }
headers() { curl -s -D - -o /dev/null "http://127.0.0.1:$PORT$1"; }

echo "Frontend image"
check "/ serves the app" grep -q 'id="root"' <(curl -s "http://127.0.0.1:$PORT/")
check "/courses/1 falls back to index.html" test "$(status /courses/1)" = 200
check "missing asset is 404" test "$(status /assets/missing.js)" = 404
check "/health is 200" test "$(status /health)" = 200
check "CSP allows the API origin" grep -qi "content-security-policy:.*connect-src 'self' https://accounts.google.com/gsi/ $API_BASE;" <(headers /)
check "index.html is not cached" grep -qi '^cache-control: no-cache' <(headers /)
check "headers also on 404s" grep -qi '^x-content-type-options: nosniff' <(headers /assets/missing.js)

if (( failures )); then
  echo "$failures check(s) failed"
  $DOCKER logs "$container" | tail -20
  exit 1
fi
