#!/usr/bin/env bash

set -euo pipefail

# USAGE: DBNAME=<database_name> ./etc/scripts/_wait_db_connection.sh [command...]
#
# Waits for PostgreSQL to accept connections, then execs any trailing arguments.
# Example (wait only):   DBNAME=postgres ./etc/scripts/_wait_db_connection.sh
# Example (then run):    DBNAME=ysc_dev ./etc/scripts/_wait_db_connection.sh mix ecto.migrate

# $1 - the max number of attempts
# $2 - the seconds to sleep between attempts
# $3... - the command to run
retry() {
  local max_attempts="${1}"
  shift
  local seconds="${1}"
  shift
  local cmd=("$@")
  local attempt_num=1

  until "${cmd[@]}"; do
    if [ "${attempt_num}" -eq "${max_attempts}" ]; then
      echo "Attempt ${attempt_num} failed and there are no more attempts left!"
      return 1
    else
      echo "Attempt ${attempt_num} failed! Trying again in ${seconds} seconds..."
      attempt_num=$((attempt_num + 1))
      sleep "${seconds}"
    fi
  done
}

retry 5 1 psql -h localhost -p 5432 -U postgres --dbname="${DBNAME}" -c '\l' >/dev/null

echo >&2 "$(date +%Y%m%dt%H%M%S) Postgres is up - executing command"

exec "$@"
