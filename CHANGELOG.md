# Changelog

All notable changes to this project are documented in this file.
The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project
uses [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [3.3.1] - 2026-11-12

### Fixed

- The release archive no longer unpacks group-writable files (664/775): the workflow runs
  `git archive` with `tar.umask` 0022 instead of git's default 0002, so the files in
  `/usr/local/src/login-warnings` get 644/755. The installed files were not affected;
  `install.sh` sets their modes itself.

## [3.3.0] - 2026-11-12

### Added

- Self-check: after every apt update and when run by hand, `login-warnings` reads the latest
  release from the redirect of `/releases/latest` (curl or wget, 10 seconds at most, nothing is
  downloaded) and keeps it in `/var/lib/login-warnings/latest-release`. A newer release shows
  as an orange section `login-warnings: <version> available` with `login-warnings update`.

### Changed

- The frame names the installed version at the top (`----- login-warnings 3.3.0 ---`) and at
  the bottom when the latest release was last checked, or that it never was.

## [3.2.0] - 2026-11-12

### Added

- GitHub releases: `.github/workflows/release.yml` publishes every new version on push to
  `main` as release `v<version>` with the archive `login-warnings.tar.gz` (only the files a
  server needs) and the version's CHANGELOG section as release notes.
- `login-warnings update`: downloads the latest release with wget or curl, shows the CHANGELOG
  sections since the installed version, replaces `/usr/local/src/login-warnings` and runs its
  `install.sh`. It changes nothing when the installed version is the latest or newer.

### Changed

- The README installs from the latest release into `/usr/local/src/login-warnings` instead of
  a git clone or the archive of `main`, so a server gets a published version, and needs neither
  git nor the branch.

## [3.1.0] - 2026-11-12

### Changed

- The login display is framed: `----- login-warnings -----` above, a line of dashes below,
  one section per check with an empty line between them.
- Every check writes one section: a title line with the state (`Package updates: 3 (0
  security)`, `PostgreSQL collation: OK`, `VERSION MISMATCH`, `CHECK FAILED`), the details
  indented by two spaces, and every line below 80 columns, instead of one long line that the
  terminal wrapped. A failed check indents its last successful result below it.
- The collation mismatch is no longer a separate banner with `====` lines but a section like
  the others; a newer glibc on disk is shown as `(glibc on disk: 2.41)` behind the database.
- A registered check without a result shows `<check>: NO RESULT` with the boot time.

## [3.0.0] - 2026-11-12

### Added

- Second check `apt-updates` (`/usr/local/sbin/apt-updates-check`): lists the package updates
  the package lists offer, by name and with security updates separately, says how old the
  lists are, and warns in orange about security updates, about lists older than two days and
  about an apt update that reached no repository. It simulates `apt-get dist-upgrade` without
  locking and without writing apt's cache files.
- `/etc/apt/apt.conf.d/80login-warnings`: refreshes the package lists once a day through
  `apt-daily.timer` (`APT::Periodic::Update-Package-Lists "1"`; Debian does not do this by
  default), records when an apt update starts and when it reaches a repository
  (`/var/lib/login-warnings`), and runs the checks after every apt update.
- Common runner `/usr/local/sbin/login-warnings`: runs every enabled check (after boot, dpkg
  and apt update), shows the results (`login-warnings show`), and switches checks on and off
  (`login-warnings list`, `enable <check>`, `disable <check>`). A switched-off check is kept as
  `/etc/login-warnings.d/<check>.off` and stays off on updates. `login-warnings --version`.

### Changed

- `pg-collation-check.service` and `/etc/dpkg/dpkg.cfg.d/pg-collation-check` are replaced by
  `login-warnings.service` and `/etc/dpkg/dpkg.cfg.d/login-warnings`, which run every enabled
  check; `install.sh` removes the old files.
- The login shows the results of enabled checks only (`/etc/profile.d/login-warnings.sh` runs
  `login-warnings show`), instead of every file in `/run/login-warnings`.
- `install.sh` no longer requires PostgreSQL: it registers `apt-updates` always and
  `pg-collation` only with a local PostgreSQL.
- `pg-collation-check` also accepts `--trigger apt` and rejects unknown triggers.

### Removed

- `pg-collation-fix --version`; the version is now shown by `login-warnings --version`.

## [2.1.0] - 2026-11-12

### Changed

- The login is never silent: without a mismatch `pg-collation-check` writes a green line
  `PostgreSQL collation versions OK - checked <date time zone> (<trigger>)` instead of removing
  its file, because an empty login looked exactly like a check that never ran.
- A failed check (a cluster cannot be queried) writes an orange FAILED line with date and time,
  followed by the last successful result, instead of silently keeping the old file. The last
  successful result is kept in `/run/login-warnings/.pg-collation.last`.

### Added

- `/etc/login-warnings.d/pg-collation` registers the check. When a registered check has no
  result file, the login shell reports `pg-collation: no result since boot (<boot time>).
  Run: pg-collation-check`.

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
