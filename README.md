# login-warnings

Warnings that every interactive login shell on a Debian server shows, in every terminal
window. Each check writes one section of the display into `/run/login-warnings`, always with
the time it ran: green when all is well, orange when something needs attention.

```
----- login-warnings 3.3.0 ---------------------------------------------
Package updates: 3 (0 security)
  libpq5 postgresql-18 postgresql-client-common
  show: apt list --upgradable
  lists from 2026-11-12 21:53:09 +01:00 (50 min ago)
  checked 2026-11-12 22:43:09 +01:00 (at boot)
  check again: apt-updates-check

PostgreSQL collation: OK
  checked 2026-11-12 22:43:09 +01:00 (at boot)
  check again: pg-collation-check

----- latest release checked 2026-11-12 23:06:35 +01:00 ----------------
```

Every line stays below 80 columns, so nothing wraps in a normal terminal window.

Two checks so far:

| Check | Reports |
| --- | --- |
| `apt-updates` | Package updates offered by the package lists, by name, security updates separately, and how old the lists are. |
| `pg-collation` | PostgreSQL databases whose collation version no longer matches glibc, with a fix script. |

## How it works

| File | Purpose |
| --- | --- |
| `/usr/local/sbin/login-warnings` | Runs every enabled check, shows the results, switches checks on and off, installs updates. |
| `/etc/login-warnings.d/<check>` | One file per enabled check; its first line is the command that runs it. `<check>.off` is a check that is switched off. |
| `/etc/systemd/system/login-warnings.service` | Runs every enabled check once after every boot, after PostgreSQL has started. |
| `/etc/dpkg/dpkg.cfg.d/login-warnings` | Runs every enabled check after every dpkg run (`post-invoke`). |
| `/etc/apt/apt.conf.d/80login-warnings` | Refreshes the package lists once a day and runs every enabled check after every apt update. |
| `/etc/profile.d/login-warnings.sh` | Runs `login-warnings show` in interactive login shells: in every terminal window, for every user, and never in scripts or file transfers. `show` puts the sections of all enabled checks into one frame. |
| `/usr/local/sbin/apt-updates-check` | The `apt-updates` check; writes `/run/login-warnings/apt-updates`. |
| `/usr/local/sbin/pg-collation-check` | The `pg-collation` check; writes `/run/login-warnings/pg-collation`. |
| `/usr/local/sbin/pg-collation-fix` | Runs `REINDEX DATABASE` on every affected database, then `ALTER DATABASE ... REFRESH COLLATION VERSION`. The version is only refreshed if the reindex succeeded. |
| `/var/lib/login-warnings` | When the last apt update started and when it last reached a repository; the latest release and when it was checked. |

Nothing is ever silent: an empty login would look exactly like an all-clear. Every section
names date, time and trigger of its check (at boot, after a package change, after apt update,
by hand) and how to repeat it. A check that fails shows `CHECK FAILED` in orange and its last
successful result below. An enabled check without any result shows `NO RESULT` with the boot
time.
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

| State | Section |
| --- | --- |
| no updates | `Package updates: none` (green) |
| updates | `Package updates: 3 (0 security)`, the package names (plain) |
| security updates among them | `Package updates: 3 (2 security)`, a `security:` and an `other:` line (orange) |
| last apt update reached no repository or did not finish | an extra line saying so (orange) |
| lists older than two days | an extra line: the daily apt update has not run (orange) |
| no apt update since installation | an extra line asking for `apt update` (orange) |
| check failed | `Package updates: CHECK FAILED` with apt's error, then the last successful result (orange); exit status 1 |

Below the title every section shows how old the lists are, when the check ran and how to run
it again.

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

| State | Section |
| --- | --- |
| everything fine | `PostgreSQL collation: OK` (green) |
| mismatch | `PostgreSQL collation: VERSION MISMATCH` with the affected databases and the fix (orange) |
| glibc on disk newer than the running server | the same, with `(glibc on disk: 2.41)` behind the database and the advice to reboot or restart PostgreSQL first (orange) |
| check failed | `PostgreSQL collation: CHECK FAILED`, the port, then the last successful result (orange); exit status 1 |

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
- `wget` or `curl` (on a minimal installation: `apt install wget`)
- for `pg-collation`: PostgreSQL installed locally (see above)

## Installation

Every version is published as a GitHub release with an archive `login-warnings.tar.gz` that
holds only what a server needs. All commands are run as root.

```bash
wget -qO- https://github.com/MarcFauser/login-warnings/releases/latest/download/login-warnings.tar.gz | tar -xz -C /usr/local/src
```

```bash
bash /usr/local/src/login-warnings/install.sh
```

The installer copies the files into place, switches on the checks that fit, and prints the
installed version, the checks and their results.

## Update

```bash
login-warnings update
```

It downloads the latest release, shows the CHANGELOG sections since the installed version,
puts the release in place of `/usr/local/src/login-warnings` and runs its `install.sh`. If the
installed version is the latest one, or newer, it changes nothing.

You see at login when an update is due. After every apt update and when run by hand,
`login-warnings` asks GitHub which release is the latest (it reads the redirect of
`/releases/latest`, downloads nothing) and keeps the answer in
`/var/lib/login-warnings/latest-release`. The frame then names the installed version at the
top, a newer release in an orange section, and at the bottom when the latest release was last
checked:

```
----- login-warnings 3.3.0 ---------------------------------------------
...

login-warnings: 3.4.0 available
  installed: 3.3.0
  update: login-warnings update

----- latest release checked 2026-11-12 23:06:35 +01:00 ----------------
```

A login itself never goes online. If GitHub cannot be reached, the old answer stays and the
date at the bottom shows its age.

Servers installed before 3.2.0 have no `update` yet: remove the old source folders once
(`/usr/local/src/login-warnings`, `/usr/local/src/login-warnings-main`, and from the time the
repository was called `pg-collation-check`, `/usr/local/src/pg-collation-check` or
`/usr/local/src/pg-collation-check-main`) and run the two lines of the installation.
`install.sh` removes what 1.x and 2.x installed under other names.

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
rm -rf /etc/login-warnings.d /run/login-warnings /var/lib/login-warnings /usr/local/src/login-warnings
systemctl daemon-reload
```

Removing `/etc/apt/apt.conf.d/80login-warnings` also stops the daily refresh of the package
lists.

## Adding a check

A check is a command `/usr/local/sbin/<check>-check` that accepts `--quiet` and
`--trigger boot|dpkg|apt|manual`, writes its result to `/run/login-warnings/<check>` and keeps
any helper files as `/run/login-warnings/.<check>.*`. The result is one section: a title line
`<Title>: <STATE>`, the details indented by two spaces, every line below 80 columns, one colour
for the whole section, and always the time of the check. `login-warnings enable <check>`
registers it.

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

Releases are made by `.github/workflows/release.yml` on every push to `main`: if the newest
version in `CHANGELOG.md` has no release yet, it tags the pushed commit `v<version>`, builds
`login-warnings.tar.gz` with `git archive` (the files marked `export-ignore` in
`.gitattributes` stay out) and uses the version's CHANGELOG section as the release notes.

## License

[MIT](LICENSE)
