#!/usr/bin/env bash
#
# Local PostgreSQL setup for development.
# Creates the devuser role and app database to match docker-compose.yml.
#
# Prerequisites: PostgreSQL installed (brew install postgresql@18)
#
# Usage:
#   chmod +x scripts/postgres_setup.sh
#   ./scripts/postgres_setup.sh
#
set -euo pipefail

DB_USER="devuser"
DB_PASS="devpass"
DB_NAME="app"

echo "==> Creating database user '${DB_USER}'..."
createuser -s "$DB_USER" || echo "   User already exists."
psql -c "ALTER USER ${DB_USER} WITH PASSWORD '${DB_PASS}';"

echo "==> Creating database '${DB_NAME}'..."
createdb -O "$DB_USER" "$DB_NAME" || echo "   Database already exists."

echo "==> Running migrations..."
npm run db:migrate --workspace=backend

echo ""
echo "Done! Local database is ready."
echo "Start dev servers with: npm run dev"
