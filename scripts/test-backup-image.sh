#!/usr/bin/env bash
# Build the backup image (backup/Dockerfile) and run it against a real Postgres,
# with a stub in place of Azure: the upload must arrive with the SAS and the blob
# type, decrypt with the private key, and restore to the same data. Also checks
# that a failed dump uploads nothing.
#   scripts/test-backup-image.sh
#   DOCKER="sudo docker" scripts/test-backup-image.sh
set -euo pipefail

DOCKER=${DOCKER:-docker}
IMAGE=li-backup:test
PG_PORT=${PG_PORT:-55434}
STUB_PORT=${STUB_PORT:-18090}
failures=0

work=$(mktemp -d)
mkdir -p "$work/secrets" "$work/uploads"
chmod -R a+rwX "$work"
cleanup() {
  [[ -n ${stub:-} ]] && kill "$stub" 2> /dev/null || true
  [[ -n ${postgres:-} ]] && $DOCKER stop "$postgres" > /dev/null
  rm -rf "$work"
}
trap cleanup EXIT

check() {  # check <description> <command...>
  if "${@:2}"; then
    echo "  ok    $1"
  else
    echo "  FAIL  $1"
    failures=$((failures + 1))
  fi
}

$DOCKER build -q -t "$IMAGE" backup > /dev/null

postgres=$($DOCKER run -d --rm --network host -e POSTGRES_USER=li -e POSTGRES_PASSWORD=li \
  -e POSTGRES_DB=li postgres:16 -p "$PG_PORT")
for _ in $(seq 60); do
  $DOCKER exec "$postgres" pg_isready -q -h 127.0.0.1 -p "$PG_PORT" -U li -d li && break
  sleep 0.5
done
sql() { $DOCKER exec -i "$postgres" psql -q -At -v ON_ERROR_STOP=1 -h 127.0.0.1 -p "$PG_PORT" -U li "$@"; }
cat db/migrations/*.sql | sql li
sql li -c "INSERT INTO users (email) SELECT 'u' || n || '@example.edu' FROM generate_series(1, 5) n"
sql li -c "CREATE DATABASE restored"

# Stands in for Azure: saves what it receives, including the request line.
python3 - "$STUB_PORT" "$work/uploads" << 'PY' &
import http.server
import pathlib
import sys

uploads = pathlib.Path(sys.argv[2])


class Stub(http.server.BaseHTTPRequestHandler):
    def do_PUT(self):
        (uploads / "blob").write_bytes(self.rfile.read(int(self.headers["Content-Length"])))
        (uploads / "request").write_text(f"{self.path}\n{self.headers['x-ms-blob-type']}\n")
        self.send_response(201)
        self.send_header("Content-Length", "0")
        self.end_headers()

    def log_message(self, *args):
        pass


http.server.ThreadingHTTPServer(("127.0.0.1", int(sys.argv[1])), Stub).serve_forever()
PY
stub=$!
sleep 1

$DOCKER run --rm --entrypoint age-keygen "$IMAGE" > "$work/key.txt" 2> /dev/null
recipient=$(sed -n 's/^# public key: //p' "$work/key.txt")
printf li > "$work/secrets/db-admin-password"
printf 'sv=test&sp=c&sig=fake' > "$work/secrets/backup-sas"

backup() {  # backup <database>: runs like the CronJob, with a read-only root filesystem
  $DOCKER run --rm --network host --read-only --tmpfs /work --user 10001 \
    -v "$work/secrets:/secrets:ro" \
    -e PGHOST=127.0.0.1 -e PGPORT="$PG_PORT" -e PGUSER=li -e PGDATABASE="$1" -e PGSSLMODE=disable \
    -e BACKUP_AGE_RECIPIENT="$recipient" \
    -e BACKUP_CONTAINER_URL="http://127.0.0.1:$STUB_PORT/backups" \
    "$IMAGE"
}

echo "Backup image"
output=$(backup li)
echo "$output"
check "logs success" grep -q '"event":"backup_succeeded"' <<< "$output"
check "the log doesn't contain the SAS" test "$(grep -c 'sig=fake' <<< "$output")" = 0
check "uploads to the container with the SAS" grep -Eq '^/backups/li-.*\.dump\.age\?sv=test&sp=c&sig=fake$' "$work/uploads/request"
check "uploads a block blob" grep -q '^BlockBlob$' "$work/uploads/request"
check "the blob is encrypted" test "$(head -c 21 "$work/uploads/blob")" = "age-encryption.org/v1"

$DOCKER run --rm -i --entrypoint sh -v "$work:/backup:ro" "$IMAGE" \
  -c 'age --decrypt -i /backup/key.txt /backup/uploads/blob' > "$work/dump"
$DOCKER exec -i "$postgres" pg_restore --no-owner -h 127.0.0.1 -p "$PG_PORT" -U li -d restored < "$work/dump"
check "restores the same rows" test "$(sql restored -c 'SELECT count(*) FROM users')" = 5

rm "$work/uploads/blob"
dump_failed=no
backup no_such_database > /dev/null 2>&1 || dump_failed=yes
check "a failed dump exits non-zero" test "$dump_failed" = yes
check "a failed dump uploads nothing" test ! -e "$work/uploads/blob"

if (( failures )); then
  echo "$failures check(s) failed"
  exit 1
fi
