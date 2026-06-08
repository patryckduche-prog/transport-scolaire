#!/usr/bin/env sh
set -eu

BACKUP_DIR="${BACKUP_DIR:-./backups/postgres}"
RETENTION_DAYS="${RETENTION_DAYS:-14}"
TIMESTAMP="$(date -u +%Y%m%d-%H%M%S)"
FILE="${BACKUP_DIR}/bus-scolaire-connect-${TIMESTAMP}.sql.gz"

mkdir -p "$BACKUP_DIR"

if [ "${DATABASE_URL:-}" != "" ]; then
  echo "Backing up external PostgreSQL database to $FILE"
  pg_dump "$DATABASE_URL" | gzip -9 > "$FILE"
else
  CONTAINER="${POSTGRES_CONTAINER:-transport-scolaire-deploy-postgres-1}"
  USER="${POSTGRES_USER:-bus}"
  DB="${POSTGRES_DB:-bus_scolaire_connect}"
  echo "Backing up Docker PostgreSQL container $CONTAINER to $FILE"
  docker exec "$CONTAINER" pg_dump -U "$USER" "$DB" | gzip -9 > "$FILE"
fi

find "$BACKUP_DIR" -name "bus-scolaire-connect-*.sql.gz" -type f -mtime +"$RETENTION_DAYS" -delete
echo "Backup created: $FILE"
