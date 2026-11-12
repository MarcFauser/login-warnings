# login-warnings

Warnings that every interactive login shell on a Debian server shows, in every terminal
window. Each check writes its result into `/run/login-warnings`, always with the time it ran:
a green line when all is well, an orange warning when something needs attention.

Two checks so far:

| Check | Reports |
| --- | --- |
| `apt-updates` | Package updates offered by the package lists, by name, security updates separately, and how old the lists are. |
| `pg-collation` | PostgreSQL databases whose collation version no longer matches glibc, with a fix script. |

## How it works

| File | Purpose |
| --- | --- |
| `/usr/local/sbin/login-warnings` | Runs every enabled check, shows the results, switches checks on and off. |
| `/etc/login-warnings.d/<check>` | One file per enabled check; its first line is the command that runs it. `<check>.off` is a check that is switched off. |
| `/etc/systemd/system/login-warnings.service` | Runs every enabled check once after every boot, after PostgreSQL has started. |
| `/etc/dpkg/dpkg.cfg.d/login-warnings` | Runs every enabled check after every dpkg run (`post-invoke`). |
| `/etc/apt/apt.conf.d/80login-warnings` | Refreshes the package lists once a day and runs every enabled check after every apt update. |
| `/etc/profile.d/login-warnings.sh` | Runs `login-warnings show` in interactive login shells: in every terminal window, for every user, and never in scripts or file transfers. |
| `/usr/local/sbin/apt-updates-check` | The `apt-updates` check; writes `/run/login-warnings/apt-updates`. |
| `/usr/local/sbin/pg-collation-check` | The `pg-collation` check; writes `/run/login-warnings/pg-collation`. |
| `/usr/local/sbin/pg-collation-fix` | Runs `REINDEX DATABASE` on every affected database, then `ALTER DATABASE ... REFRESH COLLATION VERSION`. The version is only refreshed if the reindex succeeded. |
| `/var/lib/login-warnings` | When the last apt update started and when it last reached a repository. |

Nothing is ever silent: an empty login would look exactly like an all-clear. Every result
names date, time and trigger of its check (at boot, after a package change, after apt update,
by hand) and how to repeat it. A check that fails says so in orange and shows its last
successful result below. An enabled check without any result says "no result since boot".
`/run` is emptied at reboot, and the run at boot writes the results again.

The warnings come from the login shell and not from the login message (motd): sshd shows the
login message only once per SSH connection, and clients like Bitvise open further terminal
windows on the same connection.

## Choosing the checks

`install.sh` switches on `apt-updates` and, if PostgreSQL is installed locally, `pg-collation`.
A check you switch off stays off when you install an update.

```bash
login-warnings list
login-warnings disable apt-updates
login-warnings enable apt-updates
```

`enable` runs the check at once and shows its result; `disable` removes its result, so the
login stops showing it immediately. If PostgreSQL is installed later, `login-warnings enable
pg-collation` switches its check on.

Run every enabled check by hand and see the results, or a single check:

```bash
login-warnings
apt-updates-check
pg-collation-check
```

## apt-updates: package updates

Debian does not refresh the package lists by itself. `apt-daily.timer` starts
`/usr/lib/apt/apt.systemd.daily` twice a day, but without an `APT::Periodic` setting the
script exits at once. `/etc/apt/apt.conf.d/80login-warnings` sets
`APT::Periodic::Update-Package-Lists "1"`, so the lists are refreshed once a day. Only the
lists are downloaded; no package is downloaded or installed.

The check itself downloads nothing. It simulates `apt-get dist-upgrade` on the lists on disk,
without locking and without writing apt's cache files, so it can run while apt or dpkg is
working. It runs after every apt update (by hand or from the timer), after every dpkg run (so
installed updates leave the list) and at boot.

| State | Login shows |
| --- | --- |
| no updates | `No package updates - checked 2026-11-12 22:29:32 +01:00 (by hand), lists from 2026-11-11 22:29:32 +01:00 (24 h ago). Check again: apt-updates-check` (green) |
| updates | `7 package updates (0 security) - checked 2026-11-12 22:35:20 +01:00 (after apt update), lists from 2026-11-12 22:35:19 +01:00 (0 min ago). Show: apt list --upgradable. Check again: apt-updates-check`, then the package names (plain) |
| security updates among them | the same, with the security updates listed first (orange) |
| last apt update reached no repository or did not finish | an orange line under the result |
| lists older than two days | an orange line: the daily refresh has not run |
| no apt update since installation | an orange line asking for `apt update` |
| check failed | `Package update check FAILED - …` with apt's error, then the last successful result (orange); exit status 1 |

Two days is the limit for old lists because `apt.systemd.daily` refreshes once per calendar
day and `apt-daily.timer` (6:00 and 18:00, up to 12 hours random delay) runs at least once
between 6:00 and 18:00 every day: with a working refresh at most about 42 hours pass between
two updates.

The apt hooks record when an apt update starts and when it reaches a repository. apt runs its
success hook as soon as at least one repository was fetched, also when another one fails
(measured with apt 3.0.4). So the check reports an apt update that reached no repository at
all, but not a single failing repository among working ones; `apt update` itself shows that.

## pg-collation: PostgreSQL collation versions

PostgreSQL databases using the libc collation provider record the glibc collation
version they were created with. After a glibc upgrade, typically a Debian release
upgrade, the sort order of text may have changed. B-tree indexes on text columns are
stored in the old order, so lookups can miss rows and unique indexes can let
duplicates through until the indexes are rebuilt.

PostgreSQL only reports this as a warning on every new connection:

```
WARNING:  database "example" has a collation version mismatch
DETAIL:  The database was created using collation version 2.36, but the operating system provides version 2.41.
```

Applications usually ignore this warning, so it goes unnoticed until someone opens a
psql session. The check makes it visible at login instead.

A database counts as affected when its stored collation version differs from the version
the running server reports, or, for the libc provider, from the glibc installed on disk.
The second catches a glibc update before PostgreSQL is restarted; the warning then asks for
a reboot or a PostgreSQL restart first.

| State | Login shows |
| --- | --- |
| everything fine | `PostgreSQL collation versions OK - checked 2026-11-12 21:57:13 +01:00 (at boot). Check again: pg-collation-check` (green) |
| mismatch | the orange warning, ending with `Checked … (after a package change). Check again: pg-collation-check` |
| check failed | `PostgreSQL collation check FAILED - … could not query the cluster on port(s) 5432 …`, then the last successful result (orange); exit status 1 |

Requirements: PostgreSQL 15 or newer from the Debian or PGDG packages; older versions do not
track the collation version per database and are skipped. Standby clusters are skipped; the
reindex on the primary is replicated to them. PostgreSQL running in containers is not covered.

### Fixing a mismatch

When the warning appears, rebuild the indexes and reboot:

```bash
runuser -u postgres -- /usr/local/sbin/pg-collation-fix
reboot
```

While indexes are rebuilt, queries on the affected tables have to wait. On large
databases, stop the applications using them first.

If a database fails, the script continues with the others, keeps the old collation
version for the failed one and exits with status 1. The warning stays until that
database is fixed as well. The most likely cause is a duplicate key error: the changed
sort order has let duplicates into a unique index. Resolve the duplicates and run the
script again.

Right after a glibc upgrade, the running PostgreSQL server still uses the old glibc until
it is restarted. A reindex then would still sort the old way, so the warning asks for a
reboot first, or for a PostgreSQL restart (`systemctl restart postgresql`, which restarts all
clusters) followed by `pg-collation-check`. After a reboot the check runs by itself.

## Requirements

- Debian or a derivative with systemd, dpkg and apt
- for `pg-collation`: PostgreSQL installed locally (see above)

## Installation

All commands are run as root. The installer copies the files into place, switches on the
checks that fit, and prints the installed version, the checks and their results. Run it again
after every update.

With git (on a minimal installation, `apt install git` first):

```bash
git clone https://github.com/MarcFauser/login-warnings.git /usr/local/src/login-warnings
bash /usr/local/src/login-warnings/install.sh
```

Update:

```bash
git -C /usr/local/src/login-warnings pull
bash /usr/local/src/login-warnings/install.sh
```

Without git, for the first installation and every update (the old folder is removed first,
so files dropped from the repository do not stay behind):

```bash
rm -rf /usr/local/src/login-warnings-main
wget -qO- https://github.com/MarcFauser/login-warnings/archive/refs/heads/main.tar.gz | tar -xz -C /usr/local/src
bash /usr/local/src/login-warnings-main/install.sh
```

Updating from 2.x replaces `pg-collation-check.service` and
`/etc/dpkg/dpkg.cfg.d/pg-collation-check` with `login-warnings.service` and
`/etc/dpkg/dpkg.cfg.d/login-warnings`; `install.sh` removes the old files. Up to version 2.0.0
the repository was called `pg-collation-check`. On a server installed from it, remove
`/usr/local/src/pg-collation-check` or `/usr/local/src/pg-collation-check-main` and install
from the new location.

To see which version is installed:

```bash
login-warnings --version
```

## Uninstall

```bash
systemctl disable --now login-warnings.service
rm -f /etc/systemd/system/login-warnings.service /etc/dpkg/dpkg.cfg.d/login-warnings \
      /etc/apt/apt.conf.d/80login-warnings /etc/profile.d/login-warnings.sh \
      /usr/local/sbin/login-warnings /usr/local/sbin/apt-updates-check \
      /usr/local/sbin/pg-collation-check /usr/local/sbin/pg-collation-fix
rm -rf /etc/login-warnings.d /run/login-warnings /var/lib/login-warnings
systemctl daemon-reload
```

Removing `/etc/apt/apt.conf.d/80login-warnings` also stops the daily refresh of the package
lists.

## Adding a check

A check is a command `/usr/local/sbin/<check>-check` that accepts `--quiet` and
`--trigger boot|dpkg|apt|manual`, writes its result to `/run/login-warnings/<check>` and keeps
any helper files as `/run/login-warnings/.<check>.*`. The result always names the time of the
check. `login-warnings enable <check>` registers it.

## Development

All files except the Windows launchers (`*.cmd`) must keep LF line endings. Git does not
convert line endings in this repository (`* -text` in `.gitattributes`), so a file saved with
CRLF on Windows would be committed that way: a script fails on the server with
`/bin/bash^M: bad interpreter`, and in the systemd unit or the dpkg hook line the CR becomes
part of the command.

On the machine you commit from, activate the guard once after cloning: double-click
`install-git-hooks.cmd` on Windows, or run `pwsh ./install-git-hooks.ps1`. It copies
`_git_hooks/pre-commit` into `.git/hooks`, which git does not version. The hook refuses a
commit that contains a file with CRLF line endings (except `*.cmd`), and one without a new
version section in `CHANGELOG.md` and a matching `VERSION` in `login-warnings`. None of these
files is needed on the servers.

## License

[MIT](LICENSE)
