# Nightly database backup (ADR 0004). pg_dump must not be older than the server,
# so move postgresql16-client when Cloud SQL's major version changes.
#   docker build -t li-backup backup
FROM alpine:3.22
RUN apk add --no-cache age curl postgresql16-client
COPY backup.sh /usr/local/bin/backup.sh
USER 10001
CMD ["backup.sh"]
