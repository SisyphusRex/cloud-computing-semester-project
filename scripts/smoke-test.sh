#!/usr/bin/env bash
# Smoke-test a running stack that has LI_DEV_AUTH=1 (e.g. `make dev-up`).
#   scripts/smoke-test.sh [ingest_url] [search_url]
set -euo pipefail

INGEST=${1:-http://localhost:8081}
SEARCH=${2:-http://localhost:8082}
PROF="Authorization: Bearer dev:prof@example.edu"
STUDENT="Authorization: Bearer dev:student@example.edu"
CODE="SMOKE$RANDOM"

check() {  # check <expected status> <description> <curl args...>
  local want=$1 what=$2; shift 2
  local got
  got=$(curl -s -o /tmp/smoke-body -w '%{http_code}' "$@")
  if [[ $got != "$want" ]]; then
    echo "FAIL $what: expected $want, got $got: $(cat /tmp/smoke-body)"
    exit 1
  fi
  echo "ok   $what ($got)"
}

wait_ready() {  # wait_ready <url>: up to 90 s for the service and its database
  for _ in $(seq 90); do
    curl -sf -o /dev/null "$1/readyz" && { echo "ok   $1 ready"; return; }
    sleep 1
  done
  echo "FAIL $1 not ready after 90 s"
  exit 1
}

wait_ready "$INGEST"
wait_ready "$SEARCH"
check 401 "no token is rejected" "$SEARCH/search/courses"
check 403 "uninvited account is rejected" "$SEARCH/search/courses" \
  -H "Authorization: Bearer dev:uninvited-$RANDOM@example.edu"
check 200 "invited professor is a superuser (compose seed)" "$INGEST/ingest/me" -H "$PROF"
grep -q '"is_superuser":true' /tmp/smoke-body || { echo "FAIL prof@example.edu isn't a superuser"; exit 1; }
check 201 "professor creates a course" -X POST "$INGEST/ingest/courses" \
  -H "$PROF" -H 'Content-Type: application/json' -d "{\"code\":\"$CODE\",\"title\":\"Smoke test\"}"
check 403 "student cannot create a course" -X POST "$INGEST/ingest/courses" \
  -H "$STUDENT" -H 'Content-Type: application/json' -d '{"code":"X","title":"Y"}'
check 200 "student lists courses" "$SEARCH/search/courses" -H "$STUDENT"
grep -q "\"$CODE\"" /tmp/smoke-body || { echo "FAIL new course missing from listing"; exit 1; }
COURSE_ID=$(python3 -c 'import json; print([c["id"] for c in json.load(open("/tmp/smoke-body"))["courses"] if c["code"] == "'"$CODE"'"][0])')
check 200 "student searches the course" "$SEARCH/search/courses/$COURSE_ID/segments?q=lambda" -H "$STUDENT"
echo "smoke test passed"
