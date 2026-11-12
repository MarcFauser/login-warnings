# pg-collation-check

Login banner and fix script for PostgreSQL collation version mismatches on Debian.

## Background

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

## What gets installed

| File | Purpose |
| --- | --- |
| `/etc/update-motd.d/90-pg-collation` | Checks all local clusters at every login and shows a banner with the affected databases and the fix instructions. Prints nothing while everything is fine. |
| `/usr/local/sbin/pg-collation-fix` | Runs `REINDEX DATABASE` on every affected database, then `ALTER DATABASE ... REFRESH COLLATION VERSION`. The version is only refreshed if the reindex succeeded. |

There is no state file, timer or service. The banner queries PostgreSQL directly, so
it appears by itself when a mismatch exists and disappears once it is fixed.

## Requirements

- Debian or a derivative where `pam_motd` runs `/etc/update-motd.d`
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
git clone https://github.com/MarcFauser/pg-collation-check.git /usr/local/src/pg-collation-check
bash /usr/local/src/pg-collation-check/install.sh
```

Update:

```bash
git -C /usr/local/src/pg-collation-check pull
bash /usr/local/src/pg-collation-check/install.sh
```

Without git:

```bash
wget -qO- https://github.com/MarcFauser/pg-collation-check/archive/refs/heads/main.tar.gz | tar -xz -C /usr/local/src
bash /usr/local/src/pg-collation-check-main/install.sh
```

To see which version is installed:

```bash
/usr/local/sbin/pg-collation-fix --version
```

## Fixing a mismatch

When the banner appears, rebuild the indexes and reboot:

```bash
runuser -u postgres -- /usr/local/sbin/pg-collation-fix
reboot
```

While indexes are rebuilt, queries on the affected tables have to wait. On large
databases, stop the applications using them first.

If a database fails, the script continues with the others, keeps the old collation
version for the failed one and exits with status 1. The banner stays until that
database is fixed as well. The most likely cause is a duplicate key error: the changed
sort order has let duplicates into a unique index. Resolve the duplicates and run the
script again.

Right after a glibc upgrade, the running PostgreSQL server still reports the old
version until it is restarted. The banner therefore appears after the reboot that
follows the upgrade, which is also the right moment for the reindex.

## Uninstall

```bash
rm -f /etc/update-motd.d/90-pg-collation /usr/local/sbin/pg-collation-fix
```

## Development

The shell scripts must keep LF line endings. Git does not convert line endings in this
repository (`* -text` in `.gitattributes`), so a script saved with CRLF on Windows would be
committed that way and fail on the server with `/bin/bash^M: bad interpreter`.

On the machine you commit from, activate the guard once after cloning: double-click
`install-git-hooks.cmd` on Windows, or run `pwsh ./install-git-hooks.ps1`. It copies
`_git_hooks/pre-commit` into `.git/hooks`, which git does not version. The hook refuses a
commit that contains a script with CRLF line endings, and one without a new version section
in `CHANGELOG.md` and a matching `VERSION` in `pg-collation-fix`. None of these files is
needed on the servers.

## License

[MIT](LICENSE)
