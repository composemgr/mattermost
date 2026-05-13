#!/usr/bin/env bash
# @Author    : Jason M. Hicks <casjay@yahoo.com>
# @Version   : 202405120000-git
# @Changelog : Initial release — MySQL to PostgreSQL migration for mattermost
# Migrates an existing mattermost MySQL install to PostgreSQL using pgloader.
# Run this script from the mattermost compose directory.
# Usage: ./scripts/migrate-mysql-to-postgres.sh

set -euo pipefail

MIGRATE_COMPOSE_DIR="${COMPOSE_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
MIGRATE_DB_USER="${DB_USER_NAME:-dbadmin}"
MIGRATE_DB_PASS="${DB_USER_PASS:-changeme_db_password}"
MIGRATE_DB_NAME="${DB_CREATE_DATABASE_NAME:-mattermost}"
MIGRATE_MYSQL_HOST="mattermost-db"
MIGRATE_MYSQL_PORT="3306"
MIGRATE_PG_HOST="mattermost-db-pg"
MIGRATE_PG_PORT="5432"
MIGRATE_PG_VOLUME="${MIGRATE_COMPOSE_DIR}/volumes/data/db/postgres/mattermost"
MIGRATE_MYSQL_VOLUME="${MIGRATE_COMPOSE_DIR}/volumes/data/db/mysql/mattermost"
MIGRATE_NETWORK="mattermost"

__log() { printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*"; }
__die() { printf '[ERROR] %s\n' "$*" >&2; exit 1; }

__check_prereqs() {
  __log "Checking prerequisites..."
  command -v docker >/dev/null 2>&1 || __die "docker is required"
  [[ -f "${MIGRATE_COMPOSE_DIR}/docker-compose.yaml" ]] || __die "docker-compose.yaml not found in ${MIGRATE_COMPOSE_DIR}"
  [[ -d "${MIGRATE_MYSQL_VOLUME}" ]] || __die "MySQL data volume not found at ${MIGRATE_MYSQL_VOLUME} — nothing to migrate"
  docker ps --format '{{.Names}}' | grep -q '^mattermost-db$' || __die "mattermost-db (MySQL) container is not running — start the old stack first"
}

__stop_app() {
  __log "Stopping mattermost app (keeping MySQL running)..."
  docker stop mattermost-app 2>/dev/null || true
}

__start_postgres() {
  __log "Starting temporary PostgreSQL container for migration..."
  mkdir -p "${MIGRATE_PG_VOLUME}"
  docker run -d \
    --name "${MIGRATE_PG_HOST}" \
    --network "${MIGRATE_NETWORK}" \
    -e POSTGRES_USER="${MIGRATE_DB_USER}" \
    -e POSTGRES_PASSWORD="${MIGRATE_DB_PASS}" \
    -e POSTGRES_DB="${MIGRATE_DB_NAME}" \
    -v "${MIGRATE_PG_VOLUME}:/var/lib/postgresql/data" \
    postgres:alpine
  __log "Waiting for PostgreSQL to be ready..."
  local MIGRATE_RETRIES=30
  until docker exec "${MIGRATE_PG_HOST}" pg_isready -U "${MIGRATE_DB_USER}" -d "${MIGRATE_DB_NAME}" >/dev/null 2>&1; do
    MIGRATE_RETRIES=$((MIGRATE_RETRIES - 1))
    [[ ${MIGRATE_RETRIES} -eq 0 ]] && __die "PostgreSQL did not become ready in time"
    sleep 2
  done
  __log "PostgreSQL is ready."
}

__run_pgloader() {
  __log "Running pgloader to migrate MySQL -> PostgreSQL..."
  # pgloader command file passed via stdin
  docker run --rm \
    --network "${MIGRATE_NETWORK}" \
    dimitri/pgloader:latest \
    pgloader \
    "mysql://${MIGRATE_DB_USER}:${MIGRATE_DB_PASS}@${MIGRATE_MYSQL_HOST}:${MIGRATE_MYSQL_PORT}/${MIGRATE_DB_NAME}" \
    "postgres://${MIGRATE_DB_USER}:${MIGRATE_DB_PASS}@${MIGRATE_PG_HOST}:${MIGRATE_PG_PORT}/${MIGRATE_DB_NAME}"
}

__verify_migration() {
  __log "Verifying migration — comparing row counts..."
  local MIGRATE_MYSQL_TABLES MIGRATE_TABLE MIGRATE_MYSQL_COUNT MIGRATE_PG_COUNT MIGRATE_FAIL=0

  MIGRATE_MYSQL_TABLES="$(docker exec mattermost-db mysql -u"${MIGRATE_DB_USER}" -p"${MIGRATE_DB_PASS}" "${MIGRATE_DB_NAME}" -sNe "SHOW TABLES;" 2>/dev/null)"

  while IFS= read -r MIGRATE_TABLE; do
    [[ -z "${MIGRATE_TABLE}" ]] && continue
    MIGRATE_MYSQL_COUNT="$(docker exec mattermost-db mysql -u"${MIGRATE_DB_USER}" -p"${MIGRATE_DB_PASS}" "${MIGRATE_DB_NAME}" -sNe "SELECT COUNT(*) FROM \`${MIGRATE_TABLE}\`;" 2>/dev/null)"
    MIGRATE_PG_COUNT="$(docker exec "${MIGRATE_PG_HOST}" psql -U "${MIGRATE_DB_USER}" -d "${MIGRATE_DB_NAME}" -tAc "SELECT COUNT(*) FROM \"${MIGRATE_TABLE}\";" 2>/dev/null || echo "TABLE_NOT_FOUND")"
    if [[ "${MIGRATE_MYSQL_COUNT}" != "${MIGRATE_PG_COUNT}" ]]; then
      printf '[MISMATCH] %s: MySQL=%s  PostgreSQL=%s\n' "${MIGRATE_TABLE}" "${MIGRATE_MYSQL_COUNT}" "${MIGRATE_PG_COUNT}" >&2
      MIGRATE_FAIL=1
    else
      printf '[OK]       %s: %s rows\n' "${MIGRATE_TABLE}" "${MIGRATE_MYSQL_COUNT}"
    fi
  done <<< "${MIGRATE_MYSQL_TABLES}"

  [[ ${MIGRATE_FAIL} -eq 1 ]] && __die "Row count mismatches detected — do NOT switch over yet. Investigate above tables."
  __log "All row counts match."
}

__cutover() {
  __log "Stopping temporary postgres container (will be re-created by compose)..."
  docker stop "${MIGRATE_PG_HOST}" && docker rm "${MIGRATE_PG_HOST}"

  __log "Stopping MySQL container..."
  docker stop mattermost-db && docker rm mattermost-db

  __log "Bringing up new stack with PostgreSQL..."
  docker compose -f "${MIGRATE_COMPOSE_DIR}/docker-compose.yaml" up -d

  __log "Migration complete. Mattermost is now running on PostgreSQL."
  __log "MySQL data preserved at: ${MIGRATE_MYSQL_VOLUME}"
  __log "Remove it manually once you have confirmed the new stack is healthy:"
  printf '  rm -rf %s\n' "${MIGRATE_MYSQL_VOLUME}"
}

__main() {
  __log "=== Mattermost MySQL -> PostgreSQL migration ==="
  __log "Compose dir : ${MIGRATE_COMPOSE_DIR}"
  __log "Database    : ${MIGRATE_DB_NAME}"
  __log "DB user     : ${MIGRATE_DB_USER}"
  printf '\n'

  __check_prereqs
  __stop_app
  __start_postgres
  __run_pgloader
  __verify_migration
  __cutover
}

__main "$@"
