#!/usr/bin/env sh
set -eu

if [ $# -lt 1 ]; then
  echo "Usage: scripts/restore-postgres.sh backups/postgres/file.sql.gz"
  exit 1
fi

FILE="$1"
if [ ! -f "$FILE" ]; then
  echo "Backup file not found: $FILE"
  exit 1
fi

if [ "${DATABASE_URL:-}" != "" ]; then
  echo "Restoring external PostgreSQL database from $FILE"
  gunzip -c "$FILE" | psql "$DATABASE_URL"
else
  CONTAINER="${POSTGRES_CONTAINER:-transport-scolaire-deploy-postgres-1}"
  USER="${POSTGRES_USER:-bus}"
  DB="${POSTGRES_DB:-bus_scolaire_connect}"
  echo "Restoring Docker PostgreSQL container $CONTAINER from $FILE"
  gunzip -c "$FILE" | docker exec -i "$CONTAINER" psql -U "$USER" "$DB"
fi

echo "Restore completed"
