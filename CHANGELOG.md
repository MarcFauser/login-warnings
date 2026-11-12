# Changelog

All notable changes to this project are documented in this file.
The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project
uses [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [2.0.1] - 2026-11-12

### Changed

- The repository is renamed from `pg-collation-check` to `login-warnings`, because further
  checks are to follow; `pg-collation-check` stays the name of the first check. The README
  installs to `/usr/local/src/login-warnings` and explains how to move a server installed
  from the old name. The installed files keep their names; only comments and the
  `Documentation=` link of the systemd unit change.

### Fixed

- README: the installation without git now removes the old folder before extracting, so files
  dropped from the repository do not stay behind (`90-pg-collation` remained after the update
  from 1.0.0).

## [2.0.0] - 2026-11-12

### Changed

- The warning no longer comes from the login message. `pg-collation-check` (formerly
  `/etc/update-motd.d/90-pg-collation`) writes it to `/run/login-warnings/pg-collation`, and
  `/etc/profile.d/login-warnings.sh` shows that file in every interactive login shell. It now
  appears in every terminal window, also further windows on the same SSH connection, for every
  user, and logins no longer query PostgreSQL.
- The warning states when the check ran (at boot, after a package change, by hand) and how
  to run it again.
- A database also counts as affected when its stored version differs from the glibc installed
  on disk (libc provider), so a glibc update is reported before PostgreSQL is restarted. The
  warning then asks for a reboot or a PostgreSQL restart first, because a reindex would still
  use the old glibc.
- If a cluster cannot be queried, the previous result is kept and the check exits with 1
  instead of reporting no mismatch.
- `pg-collation-fix` ends with a hint to reboot or run the check.
- The pre-commit hook checks every file except `*.cmd` for CRLF, not only scripts.

### Added

- `pg-collation-check.service`: runs the check once after every boot, after PostgreSQL.
- `/etc/dpkg/dpkg.cfg.d/pg-collation-check`: runs the check after every dpkg run.

### Removed

- `/etc/update-motd.d/90-pg-collation`; `install.sh` deletes it when updating from 1.x.

## [1.1.0] - 2026-11-12

### Changed

- The login banner is printed in orange (index 208 of the 256-colour palette), so it stands out
  as a warning among the other login messages. The colour is reset at its end.

## [1.0.0] - 2026-11-12

### Added

- Login banner `/etc/update-motd.d/90-pg-collation`: at every login it checks all online
  primary clusters running PostgreSQL 15 or newer and lists the databases whose stored
  collation version differs from the one the operating system provides, together with the
  fix instructions. It prints nothing while everything matches.
- `/usr/local/sbin/pg-collation-fix`: runs `REINDEX DATABASE` and then
  `ALTER DATABASE ... REFRESH COLLATION VERSION` on every affected database. The version is
  only refreshed after a successful reindex; a failed database is reported, the others are
  still processed, and the script exits with status 1. `--version` prints the version.
- `install.sh` copies both scripts into place and prints the installed version, the
  clusters and the current status.
- Pre-commit hook (`_git_hooks/pre-commit`, installed with `install-git-hooks.cmd` or
  `install-git-hooks.ps1`): refuses scripts with CRLF line endings and commits without a new
  version.
