# Changelog

All notable changes to this project are documented in this file.
The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project
uses [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
