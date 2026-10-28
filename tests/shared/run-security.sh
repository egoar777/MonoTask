#!/bin/bash
set -euo pipefail
root_dir=$(cd "$(dirname "$0")/../.." && pwd)
container_name="monotask-shared-check-$$"
test_log=$(mktemp)
cleanup() {
    docker rm -f "$container_name" >/dev/null 2>&1 || true
    rm -f "$test_log"
}
trap cleanup EXIT
# Ephemeral local PostgreSQL: never reads .env or connects to a production server.
docker run --rm --name "$container_name" -e POSTGRES_PASSWORD=local-test-only -d postgres:17-alpine >/dev/null
ready=false
for attempt in {1..40}; do
    if docker exec "$container_name" pg_isready -U postgres >/dev/null 2>&1; then ready=true; break; fi
    sleep 1
done
if [ "$ready" != true ]; then echo "Local PostgreSQL did not start" >&2; exit 1; fi
for source in tests/shared/bootstrap.sql docs/supabase_schema.sql docs/migrations/20261028_shared_lists.sql docs/migrations/20261028_shared_lists.sql tests/shared/security.sql; do
    if ! docker exec -i "$container_name" psql -U postgres -v ON_ERROR_STOP=1 < "$root_dir/$source" >> "$test_log" 2>&1; then
        cat "$test_log"; exit 1
    fi
done
tail -5 "$test_log"
