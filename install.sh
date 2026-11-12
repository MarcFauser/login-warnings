#!/bin/bash
# install.sh
#
# Installs the PostgreSQL collation version check on Debian-based systems:
#   /usr/local/sbin/pg-collation-fix    rebuilds indexes and refreshes the collation version
#   /etc/update-motd.d/90-pg-collation  login banner, shown only while a mismatch exists
#
# Run as root from a checkout of this repository. Safe to run again; existing files are
# overwritten, which is also how updates are applied.
set -euo pipefail

src=$(dirname "$(readlink -f "$0")")

if [ "$(id -u)" -ne 0 ]
then
    echo "Please run as root." >&2
    exit 1
fi

for file in pg-collation-fix 90-pg-collation
do
    if [ ! -f "$src/$file" ]
    then
        echo "$src/$file not found. Run install.sh from a complete checkout of the repository." >&2
        exit 1
    fi
done

if ! id postgres >/dev/null 2>&1 || ! command -v psql >/dev/null 2>&1
then
    echo "No local PostgreSQL installation found (user 'postgres' or psql missing)." >&2
    exit 1
fi

if [ ! -d /etc/update-motd.d ]
then
    echo "/etc/update-motd.d not found, login banner is not supported on this system." >&2
    exit 1
fi

install -m 0755 -o root -g root "$src/pg-collation-fix" /usr/local/sbin/pg-collation-fix
install -m 0755 -o root -g root "$src/90-pg-collation" /etc/update-motd.d/90-pg-collation

echo "Installed version $(/usr/local/sbin/pg-collation-fix --version | awk '{ print $2 }'):"
echo "  /usr/local/sbin/pg-collation-fix"
echo "  /etc/update-motd.d/90-pg-collation"
echo

if command -v pg_lsclusters >/dev/null 2>&1
then
    echo "Clusters (only PostgreSQL 15+ can be checked):"
    pg_lsclusters
    echo
fi

output=$(/etc/update-motd.d/90-pg-collation)
if [ -n "$output" ]
then
    echo "$output"
else
    echo "No collation version mismatch found."
fi
