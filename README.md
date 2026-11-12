# login-warnings

Warnings that every interactive login shell on a Debian server shows, in every terminal
window. A check writes its warning into `/run/login-warnings` and removes it once the problem
is solved.

The first and so far only check, `pg-collation-check`, reports PostgreSQL collation version
mismatches and comes with a fix script. Further checks are planned; when the second one
arrives, the checks will get a common runner.

## Background: PostgreSQL collation versions

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
psql session. This repository makes it visible at login instead.

## How it works

A check writes its result into a file, and every interactive login shell shows that file:

| File | Purpose |
| --- | --- |
| `/usr/local/sbin/pg-collation-check` | Checks all local clusters and writes an orange warning with the affected databases, the fix instructions, the time of the check and how to repeat it to `/run/login-warnings/pg-collation`. Removes the file when everything is fine. |
| `/etc/systemd/system/pg-collation-check.service` | Runs the check once after every boot, after PostgreSQL has started. |
| `/etc/dpkg/dpkg.cfg.d/pg-collation-check` | Runs the check after every dpkg run (`post-invoke`), so a glibc or PostgreSQL update shows up at once. |
| `/etc/profile.d/login-warnings.sh` | Prints every file in `/run/login-warnings` in interactive login shells: in every terminal window, for every user, and never in scripts or file transfers. |
| `/usr/local/sbin/pg-collation-fix` | Runs `REINDEX DATABASE` on every affected database, then `ALTER DATABASE ... REFRESH COLLATION VERSION`. The version is only refreshed if the reindex succeeded. |

A database counts as affected when its stored collation version differs from the version
the running server reports, or, for the libc provider, from the glibc installed on disk.
The second catches a glibc update before PostgreSQL is restarted; the warning then asks for
a reboot or a PostgreSQL restart first.

Run the check by hand at any time:

```bash
pg-collation-check
```

If a cluster cannot be queried, the check keeps the previous result and exits with status 1,
so a failed check never looks like an all-clear. `/run` is emptied at reboot, and the check
at boot writes the file again.

The warning is shown by the login shell and not by the login message (motd): sshd shows the
login message only once per SSH connection, and clients like Bitvise open further terminal
windows on the same connection.

`/run/login-warnings` is meant to be shared: other checks can put their own file there and
remove it once their problem is solved.

## Requirements

- Debian or a derivative with systemd and dpkg
- PostgreSQL installed locally from the Debian or PGDG packages
- PostgreSQL 15 or newer; older versions do not track the collation version per
  database and are skipped
- Standby clusters are skipped; the reindex on the primary is replicated to them

PostgreSQL running in containers is not covered.

## Installation

All commands are run as root. The installer copies the scripts into place and prints the
installed version and the current status. Run it again after every update.

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

Up to version 2.0.0 the repository was called `pg-collation-check`. On a server installed
from it, remove `/usr/local/src/pg-collation-check` or `/usr/local/src/pg-collation-check-main`
and install from the new location; the installed files keep their names.

To see which version is installed:

```bash
/usr/local/sbin/pg-collation-fix --version
```

## Fixing a mismatch

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

## Uninstall

```bash
systemctl disable --now pg-collation-check.service
rm -f /etc/systemd/system/pg-collation-check.service /etc/dpkg/dpkg.cfg.d/pg-collation-check \
      /usr/local/sbin/pg-collation-check /usr/local/sbin/pg-collation-fix /run/login-warnings/pg-collation
systemctl daemon-reload
```

`/etc/profile.d/login-warnings.sh` only shows what is in `/run/login-warnings`; remove it as
well if no other check uses that directory.

## Development

All files except the Windows launchers (`*.cmd`) must keep LF line endings. Git does not
convert line endings in this repository (`* -text` in `.gitattributes`), so a file saved with
CRLF on Windows would be committed that way: a script fails on the server with
`/bin/bash^M: bad interpreter`, and in the systemd unit or the dpkg hook line the CR becomes
part of the command.

On the machine you commit from, activate the guard once after cloning: double-click
`install-git-hooks.cmd` on Windows, or run `pwsh ./install-git-hooks.ps1`. It copies
`_git_hooks/pre-commit` into `.git/hooks`, which git does not version. The hook refuses a
commit that contains a file with CRLF line endings (except `*.cmd`), and one without a new version section
in `CHANGELOG.md` and a matching `VERSION` in `pg-collation-fix`. None of these files is
needed on the servers.

## License

[MIT](LICENSE)
