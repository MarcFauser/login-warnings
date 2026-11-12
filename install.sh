#!/bin/bash
# install.sh
#
# Installs login-warnings on Debian-based systems:
#   /usr/local/sbin/login-warnings               runs the checks, shows the results, switches checks on and off
#   /usr/local/sbin/apt-updates-check            writes /run/login-warnings/apt-updates
#   /usr/local/sbin/pg-collation-check           writes /run/login-warnings/pg-collation
#   /usr/local/sbin/pg-collation-fix             rebuilds indexes, refreshes the collation version
#   /etc/systemd/system/login-warnings.service   runs the checks after every boot
#   /etc/dpkg/dpkg.cfg.d/login-warnings          runs the checks after every dpkg run
#   /etc/apt/apt.conf.d/80login-warnings         refreshes the package lists daily, runs the checks after every apt update
#   /etc/profile.d/login-warnings.sh             shows the results in every interactive login shell
#   /etc/login-warnings.d/<check>                one file per enabled check (<check>.off: switched off)
#   /var/lib/login-warnings                      when the last apt update started and reached a repository
#
# Registers apt-updates, and pg-collation if PostgreSQL is installed locally. A check that was
# switched off (login-warnings disable) stays off. Run as root from a checkout of this
# repository. Safe to run again; existing files are overwritten, which is also how updates are
# applied. Removes what versions 1.x and 2.x installed under other names.
set -euo pipefail

src=$(dirname "$(readlink -f "$0")")

if [ "$(id -u)" -ne 0 ]
then
    echo "Please run as root." >&2
    exit 1
fi

for file in login-warnings apt-updates-check pg-collation-check pg-collation-fix \
    login-warnings.service dpkg-login-warnings.cfg apt-login-warnings.conf login-warnings.sh
do
    if [ ! -f "$src/$file" ]
    then
        echo "$src/$file not found. Run install.sh from a complete checkout of the repository." >&2
        exit 1
    fi
done

for dir in /etc/systemd/system /etc/dpkg/dpkg.cfg.d /etc/apt/apt.conf.d /etc/profile.d
do
    if [ ! -d "$dir" ]
    then
        echo "$dir not found; this needs systemd, dpkg, apt and /etc/profile.d." >&2
        exit 1
    fi
done

if ! command -v apt-get >/dev/null 2>&1
then
    echo "apt-get not found; this needs Debian or a derivative." >&2
    exit 1
fi

install -m 0755 -o root -g root "$src/login-warnings" /usr/local/sbin/login-warnings
install -m 0755 -o root -g root "$src/apt-updates-check" /usr/local/sbin/apt-updates-check
install -m 0755 -o root -g root "$src/pg-collation-check" /usr/local/sbin/pg-collation-check
install -m 0755 -o root -g root "$src/pg-collation-fix" /usr/local/sbin/pg-collation-fix
install -m 0644 -o root -g root "$src/login-warnings.service" /etc/systemd/system/login-warnings.service
install -m 0644 -o root -g root "$src/dpkg-login-warnings.cfg" /etc/dpkg/dpkg.cfg.d/login-warnings
install -m 0644 -o root -g root "$src/apt-login-warnings.conf" /etc/apt/apt.conf.d/80login-warnings
install -m 0644 -o root -g root "$src/login-warnings.sh" /etc/profile.d/login-warnings.sh
install -d -m 0755 -o root -g root /etc/login-warnings.d /var/lib/login-warnings

removed=()
# 2.x ran pg-collation-check from its own unit and dpkg hook; login-warnings runs it now.
if [ -e /etc/systemd/system/pg-collation-check.service ]
then
    systemctl disable --quiet pg-collation-check.service 2>/dev/null || true
    rm -f /etc/systemd/system/pg-collation-check.service \
          /etc/systemd/system/multi-user.target.wants/pg-collation-check.service
    removed+=(/etc/systemd/system/pg-collation-check.service)
fi
if [ -e /etc/dpkg/dpkg.cfg.d/pg-collation-check ]
then
    rm -f /etc/dpkg/dpkg.cfg.d/pg-collation-check
    removed+=(/etc/dpkg/dpkg.cfg.d/pg-collation-check)
fi
# 1.x showed the warning as a login message.
if [ -e /etc/update-motd.d/90-pg-collation ]
then
    rm -f /etc/update-motd.d/90-pg-collation
    removed+=(/etc/update-motd.d/90-pg-collation)
fi

# Registers a check as on, unless it was switched off.
register()
{
    if [ -f "/etc/login-warnings.d/$1.off" ]
    then
        echo "  $1: switched off, stays off (login-warnings enable $1)"
        return
    fi
    printf '%s-check\n' "$1" > "/etc/login-warnings.d/$1.tmp"
    chmod 0644 "/etc/login-warnings.d/$1.tmp"
    mv -f "/etc/login-warnings.d/$1.tmp" "/etc/login-warnings.d/$1"
    echo "  $1: on"
}

echo "Registering checks:"
register apt-updates
postgresql=0
if id postgres >/dev/null 2>&1 && command -v psql >/dev/null 2>&1
then
    postgresql=1
    register pg-collation
else
    echo "  pg-collation: not registered, no local PostgreSQL (user postgres or psql missing)"
fi

systemctl daemon-reload
systemctl enable --quiet login-warnings.service

echo
echo "Installed $(/usr/local/sbin/login-warnings --version):"
echo "  /usr/local/sbin/login-warnings"
echo "  /usr/local/sbin/apt-updates-check"
echo "  /usr/local/sbin/pg-collation-check"
echo "  /usr/local/sbin/pg-collation-fix"
echo "  /etc/systemd/system/login-warnings.service (enabled)"
echo "  /etc/dpkg/dpkg.cfg.d/login-warnings"
echo "  /etc/apt/apt.conf.d/80login-warnings"
echo "  /etc/profile.d/login-warnings.sh"
for file in ${removed[@]+"${removed[@]}"}
do
    echo "Removed $file (older version)"
done
echo
/usr/local/sbin/login-warnings list
echo

if [ "$postgresql" -eq 1 ] && command -v pg_lsclusters >/dev/null 2>&1
then
    echo "Clusters (only PostgreSQL 15+ can be checked):"
    pg_lsclusters
    echo
fi

# Runs every enabled check by hand and shows the results.
/usr/local/sbin/login-warnings
