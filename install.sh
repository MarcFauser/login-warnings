#!/bin/bash
# install.sh
#
# Installs the PostgreSQL collation version check on Debian-based systems:
#   /usr/local/sbin/pg-collation-check              writes /run/login-warnings/pg-collation
#   /usr/local/sbin/pg-collation-fix                rebuilds indexes, refreshes the collation version
#   /etc/systemd/system/pg-collation-check.service  runs the check after every boot
#   /etc/dpkg/dpkg.cfg.d/pg-collation-check         runs the check after every dpkg run
#   /etc/profile.d/login-warnings.sh                shows /run/login-warnings/* in every login shell
#   /etc/login-warnings.d/pg-collation              registers the check, so a missing result is reported
#
# Run as root from a checkout of this repository. Safe to run again; existing files are
# overwritten, which is also how updates are applied. Removes the login banner of version 1.x
# (/etc/update-motd.d/90-pg-collation), which this replaces.
set -euo pipefail

src=$(dirname "$(readlink -f "$0")")

if [ "$(id -u)" -ne 0 ]
then
    echo "Please run as root." >&2
    exit 1
fi

for file in pg-collation-check pg-collation-fix pg-collation-check.service dpkg-pg-collation-check.cfg login-warnings.sh
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

for dir in /etc/systemd/system /etc/dpkg/dpkg.cfg.d /etc/profile.d
do
    if [ ! -d "$dir" ]
    then
        echo "$dir not found; this needs systemd, dpkg and /etc/profile.d." >&2
        exit 1
    fi
done

install -m 0755 -o root -g root "$src/pg-collation-check" /usr/local/sbin/pg-collation-check
install -m 0755 -o root -g root "$src/pg-collation-fix" /usr/local/sbin/pg-collation-fix
install -m 0644 -o root -g root "$src/pg-collation-check.service" /etc/systemd/system/pg-collation-check.service
install -m 0644 -o root -g root "$src/dpkg-pg-collation-check.cfg" /etc/dpkg/dpkg.cfg.d/pg-collation-check
install -m 0644 -o root -g root "$src/login-warnings.sh" /etc/profile.d/login-warnings.sh
install -d -m 0755 -o root -g root /etc/login-warnings.d
printf 'pg-collation-check\n' > /etc/login-warnings.d/pg-collation.tmp
chmod 0644 /etc/login-warnings.d/pg-collation.tmp
mv -f /etc/login-warnings.d/pg-collation.tmp /etc/login-warnings.d/pg-collation

systemctl daemon-reload
systemctl enable --quiet pg-collation-check.service

echo "Installed version $(/usr/local/sbin/pg-collation-fix --version | awk '{ print $2 }'):"
echo "  /usr/local/sbin/pg-collation-check"
echo "  /usr/local/sbin/pg-collation-fix"
echo "  /etc/systemd/system/pg-collation-check.service (enabled)"
echo "  /etc/dpkg/dpkg.cfg.d/pg-collation-check"
echo "  /etc/profile.d/login-warnings.sh"
echo "  /etc/login-warnings.d/pg-collation"
if [ -e /etc/update-motd.d/90-pg-collation ]
then
    rm -f /etc/update-motd.d/90-pg-collation
    echo "Removed the login banner of version 1.x: /etc/update-motd.d/90-pg-collation"
fi
echo

if command -v pg_lsclusters >/dev/null 2>&1
then
    echo "Clusters (only PostgreSQL 15+ can be checked):"
    pg_lsclusters
    echo
fi

# Writes /run/login-warnings/pg-collation and shows it: the OK line or the warning.
/usr/local/sbin/pg-collation-check
