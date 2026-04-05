#!/usr/bin/env bash
set -uo pipefail

# Don't use set -e — we handle errors per-command with || true to avoid
# the setup script aborting partway through in web environments.

echo "==> Setting up Raif development environment"

# Install system dependencies if apt-get is available (e.g. Claude Code web containers)
if command -v apt-get &> /dev/null; then
  PACKAGES_TO_INSTALL=""

  # PostgreSQL and libpq (needed to compile pg gem)
  if ! command -v psql &> /dev/null; then
    PACKAGES_TO_INSTALL="$PACKAGES_TO_INSTALL postgresql postgresql-contrib libpq-dev"
  fi

  # MySQL client libs (needed to compile mysql2 gem)
  if ! dpkg -s default-libmysqlclient-dev &> /dev/null 2>&1; then
    PACKAGES_TO_INSTALL="$PACKAGES_TO_INSTALL default-libmysqlclient-dev"
  fi

  # Chrome (needed for Capybara/Cuprite feature specs)
  if ! command -v google-chrome &> /dev/null && ! command -v chromium-browser &> /dev/null && ! command -v chromium &> /dev/null; then
    PACKAGES_TO_INSTALL="$PACKAGES_TO_INSTALL chromium"
  fi

  # Build essentials
  if ! command -v make &> /dev/null; then
    PACKAGES_TO_INSTALL="$PACKAGES_TO_INSTALL build-essential pkg-config git libyaml-dev"
  fi

  if [ -n "$PACKAGES_TO_INSTALL" ]; then
    echo "==> Installing system packages:$PACKAGES_TO_INSTALL"
    sudo apt-get update -qq || true
    sudo apt-get install -y --no-install-recommends $PACKAGES_TO_INSTALL || true
  fi
fi

# Start PostgreSQL if not running
if command -v pg_isready &> /dev/null; then
  if ! pg_isready -q 2>/dev/null; then
    echo "==> Starting PostgreSQL..."
    if command -v pg_ctlcluster &> /dev/null; then
      sudo pg_ctlcluster $(pg_lsclusters -h | head -1 | awk '{print $1, $2}') start 2>/dev/null || true
    elif [ -d /usr/lib/postgresql ]; then
      PG_VERSION=$(ls /usr/lib/postgresql/ | sort -V | tail -1)
      sudo -u postgres /usr/lib/postgresql/${PG_VERSION}/bin/pg_ctl start -D /var/lib/postgresql/${PG_VERSION}/main -l /var/log/postgresql/postgresql.log 2>/dev/null || true
    fi
    sleep 2
  fi
fi

# Ensure postgres user/role exists and can create databases
if command -v psql &> /dev/null; then
  sudo -u postgres psql -c "ALTER USER postgres WITH SUPERUSER CREATEDB;" 2>/dev/null || true
fi

# Point Cuprite at chromium if google-chrome isn't available
if ! command -v google-chrome &> /dev/null && command -v chromium &> /dev/null; then
  export CHROMIUM_BIN=$(which chromium)
  export BROWSER_PATH=$(which chromium)
fi

# Install Ruby dependencies
echo "==> Installing Ruby dependencies..."
bundle install --jobs=4

# Install JS dependencies
echo "==> Installing JS dependencies..."
yarn install

# Build CSS assets
echo "==> Building CSS..."
yarn build:css || true

# Set up test database
echo "==> Setting up test database..."
export RAILS_ENV=test

# Use DATABASE_URL if set, otherwise rely on database.yml defaults
if [ -z "${DATABASE_URL:-}" ]; then
  # Try connecting with default config first; if it fails, try setting DATABASE_URL for local postgres
  if ! bin/rails app:db:create 2>/dev/null; then
    export DATABASE_URL="postgres://postgres:postgres@localhost:5432/raif_dummy_test"
    bin/rails app:db:create 2>/dev/null || true
  fi
else
  bin/rails app:db:create 2>/dev/null || true
fi

bin/rails app:db:migrate:reset 2>/dev/null || bin/rails app:db:migrate || true

echo "==> Setup complete!"
