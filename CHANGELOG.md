# Changelog

All notable changes to this project are documented in this file.
The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project
uses [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [7.1.0] - 2026-11-26

### Added

- `pg-collation` checks PostgreSQL in Docker containers. It finds them by their server process
  and its cgroup, whatever the image, and queries them with `docker exec` and `psql` as the user
  the official `postgres` image makes superuser (`POSTGRES_USER`, `POSTGRES_USER_FILE`, `PGUSER`,
  else `postgres`). A container's own glibc counts, not the host's. At boot the check runs after
  `docker.service` and waits up to 60 seconds for the containers of its last run to answer.
  `pg-collation-fix --docker <container>` rebuilds the indexes in one. `install.sh` switches the
  check on where PostgreSQL runs in a container.
- Any other PostgreSQL server on the host (podman, a cluster in a unit of its own) is named in
  the section as not checked, and the section turns orange. Before, a host whose PostgreSQL ran
  only in Docker had no `pg-collation` section at all. Guests of the host (LXC) are left to their
  own check.

## [7.0.1] - 2026-11-26

### Fixed

- Under systemd, which runs services with SIGPIPE ignored, the run at boot logged
  `grep: write error: Broken pipe` on Proxmox VE hosts since 5.0.5: two lookups in
  `apt-updates-check` wrote into one `head -n 1`, and the second wrote after `head` had quit.
  The result was right. Every reader in the scripts that stopped before the end of its input
  (`head`, `grep -q`, `awk` with `exit`, a loop left early) now reads to the end (`sed -n 1p`,
  `grep ... >/dev/null`, a flag in `awk`), so that no writer meets a closed pipe, however much it
  writes.

## [7.0.0] - 2026-11-25

### Added

- A new check, `zvol-links` (`zvol-links-check`): ZFS volumes without a link in `/dev/zvol`.
  udev creates these links at boot and sometimes fails on one ("Failed to process device,
  ignoring: Unknown error 512") without trying again; Proxmox VE then waits 300 seconds and
  refuses to start the VM. Red with `udevadm trigger` and `qm start` commands for exactly the
  affected volumes; orange when the repair at boot brought links back, with the volumes and
  udev's message; the last repair of an earlier boot stays listed. Which volumes need a link
  follows `zvol_wait`'s rule.
- `login-warnings-zvol-repair.service` repairs this at boot, before Proxmox VE starts its guests:
  it waits until udev is idle, re-triggers udev for every volume whose zd device exists but has
  no link (at most three times each, for at most 60 seconds), and records what it did in
  `/var/lib/login-warnings/zvol-links-repair`. `install.sh` switches the check on where ZFS has
  volumes and enables the unit wherever ZFS is installed; the unit runs only while the check is
  switched on.

### Changed

- `login-warnings.service` runs after the repair, so that the section at boot shows it.

## [6.1.0] - 2026-11-25

### Added

- `restart` turns red when a replaced file came with a security update: the package that owns
  its path now (`dpkg -S`, in both spellings on a merged `/usr`, and as `<name>.so.*` for a
  library with a new file name) has its installed version from a security archive. The section
  names those packages. Only files of processes counted here, not of containers.
- With systemd itself or a service that should not be restarted on the fly among them, the
  section says first that a reboot covers all of this.

### Changed

- The lists of careful services, users, VMs and other programs stand on their own lines below
  their heading, like the services, so that a long list does not wrap into what looks like the
  next item.

## [6.0.0] - 2026-11-25

### Added

- A new check, `restart` (`restart-check`): running programs that still use files an update has
  replaced, usually libraries. It reads the executable mappings in `/proc/<pid>/maps`, as
  needrestart does, and assigns each process by its cgroup: services, with a `systemctl
  try-restart` command for exactly those; services that should not be restarted on the fly
  (dbus, systemd-logind, networking and others, from the lists of needrestart and checkrestart),
  apart from the command; systemd itself (`systemctl daemon-reexec`); logged-in users; Proxmox
  VE VMs. Processes in containers are only counted. `--details` lists every process with its
  files. `install.sh` switches it on everywhere.

## [5.1.0] - 2026-11-23

### Added

- `apt-updates` names the packages that `apt autoremove` would remove, in orange, with an
  `apt remove` command for exactly those. Most of them still have a source and were reported
  nowhere: on a Proxmox VE host apt offered to autoremove an old kernel that the repository
  still has, while the section said "none". Packages without a source are listed once, as in
  use or left over. They are removed, not purged, so that the next check judges the config files
  they leave like those of any removed package. A failed simulation is a failed check.

### Changed

- The README says that the rules for removed packages read only shell commands in a `postrm`;
  a Proxmox VE kernel's Perl `postrm` shows them nothing.

## [5.0.5] - 2026-11-19

### Fixed

- `apt-updates` asked dpkg about a path only as a removed package's `postrm` spells it. On a
  merged `/usr`, dpkg knows a file only under the name its package recorded, so a `postrm`
  that deletes `/lib/...` of a file an installed package recorded as `/usr/lib/...` could be
  listed as one whose config files can go. Paths below `/bin`, `/sbin`, `/lib`, `/lib32`,
  `/lib64` and `/libx32` are now asked in both spellings, where these are links into `/usr`.
- A variable that a `postrm` sets once, unindented and to a fixed value, is now put in before
  its paths are read. A kernel's `postrm` deletes `/lib/modules/$version/...`, its own module
  directory; read up to the variable it stood for everything below `/lib/modules/`, where the
  installed kernels keep their modules, and with both spellings every removed kernel would
  have had to stay. A variable set again, or by a `for` loop or `read`, stays a pattern.

## [5.0.4] - 2026-11-18

### Fixed

- `apt-updates` resolved each file of a package without a source before comparing it with the
  files processes map, links included. A link to another package's library, like
  `libatomic.so` in an old `libgcc-10-dev`, made the old package in use, and with it every
  package that depends on it: on one server 43 compilers and libraries from Debian 8 to 11
  were red. Only the directories are resolved now (`/lib` is `/usr/lib`).
- A dependency on a package without a source made it in use even when an installed package
  with a source provides it (`libgcc1`, provided by `libgcc-s1`). A dependency now counts only
  when no installed package with a source meets it, by name or as something it provides; 5.0.2
  did this for alternatives only.
- A removed package whose `postrm` deletes a link to a file of an installed package was listed
  as one whose config files can go. `pgdg-keyring` deletes
  `/etc/apt/trusted.gpg.d/apt.postgresql.org.gpg`, the link to `postgresql-client-common`'s key
  through which apt trusts the PostgreSQL repository; it now must stay.

## [5.0.3] - 2026-11-18

### Fixed

- `apt-updates` read a path in a `postrm` up to the first variable, so `rm
  /etc/nginx/modules-enabled/$to` became the directory `/etc/nginx/modules-enabled/`, which
  nginx-common owns, and six `libnginx-mod-*` packages that delete only their own links there
  were listed as config files that must stay. Such a path now stands for what lies below its
  beginning: dpkg -S gets it as a pattern, and the ucf registry is searched by its beginning.
- The comment above the rules and the README say that the check cannot see a `postrm` that
  deletes data no package owns, such as a database.

## [5.0.2] - 2026-11-18

### Fixed

- `apt-updates` counted every member of an alternative in a dependency as needed. With
  `python3.13` depending on `media-types | mime-support` and `media-types` installed, a left
  over `mime-support` showed as in use (red), and with it the Python 3.11 libraries that depend
  on it, and the `apt purge` command left them out. A member now counts only when no other
  member is installed with a source, by name or as something such a package provides.

## [5.0.1] - 2026-11-18

### Fixed

- README and HISTORY said that all three rules for config files that must stay came from real
  servers. Two did (a unit switched off, a file registered with ucf); the third, a conffile
  that another installed package owns, is a precaution that no server has shown. The README
  now also says how to bring such a file back after a purge (`--force-confmiss`). The scripts
  are unchanged.

## [5.0.0] - 2026-11-18

### Added

- `apt-updates` names the config files of removed packages (dpkg state `rc` or `ic`), split
  into those that can go and those that must stay, each with the reason: purging it would
  switch off a systemd unit that an installed package ships, or delete a file that an installed
  package owns or has registered with ucf, or a conffile that another installed package owns.
  Config files that must stay do not change the colour; those that can go make it orange.
- When something can go, the section ends with an `apt purge` command naming exactly those
  packages, split over several lines when it is long, without `-y`.

### Changed

- Installed packages that no source offers are split into those in use and those left over.
  In use (red, as before): a running process maps one of their files, they ship an enabled or
  active systemd unit, they are the running kernel or one apt keeps, or an installed package
  depends on them, directly or through a package in use. Left over (orange): nothing of that,
  and apt's simulated purge of them takes nothing else along. Only the leftovers go into the
  command.

## [4.3.0] - 2026-11-16

### Changed

- `apt-updates` shows pending updates in orange instead of the terminal's normal colour, and
  security updates in red (index 196 of the 256-colour palette) instead of orange. Installed
  packages that no package source offers are red as well, as they get no security updates.
  A problem with the package lists without any update stays orange, `none` stays green and
  `CHECK FAILED` stays orange.

## [4.2.1] - 2026-11-15

### Fixed

- `apt-updates` no longer reports the fallback kernel that apt keeps when no package source
  offers it any more. It follows apt's own rule: apt keeps the booted kernel and the newest
  ones, `APT::NeverAutoRemove::KernelCount` in all (2, and never fewer), together with their
  packages named in `APT::VersionedKernelPackages` (`linux-headers-<uname>` and the like).
  Older kernels are still reported, and so is the newest one, because a newest kernel without
  a source means the kernel gets no updates. With `APT::Protect-Kernels "false"` apt keeps
  none, and every kernel without a source is reported.

## [4.2.0] - 2026-11-15

### Added

- `apt-updates` names installed packages whose installed version no package source offers
  any more: after a source file was removed or emptied, or for a package installed from a
  `.deb` file. They get no updates, security updates included, and `apt-get dist-upgrade`
  does not mention them, so the section said `none` in green. Now it turns orange, lists them
  and shows `apt-cache policy <package>`. The check asks `apt-cache policy` about every
  installed package, without locking and without writing apt's cache files; if that or
  `dpkg-query` fails, the section shows `CHECK FAILED` with the last successful result, as it
  does when the simulation fails.

### Fixed

- Wrapped lines of `apt-updates` could reach 80 columns, and 82 in the last successful result
  that a failed check repeats with four more columns: the wrap width did not count the
  indentation. Every line now stays below 80, also there.

## [4.1.0] - 2026-11-15

### Changed

- `ssh-password` shows the command to copy, not only a description, when password login is
  on and writing `/etc/ssh/sshd_config.d/10-key-only.conf` switches it off: the file does not
  exist yet and sshd would read it before the setting that says yes (sshd's default, a line
  below the `Include`, or a file that sorts after it, such as `50-cloud-init.conf`). The
  command is split with backslashes, so every line stays below 80 columns. Where the file
  would not help, the section names what to change instead: the file itself when it exists,
  the line that sshd reads first, `/etc/ssh/sshd_config` when no `Include` reads the file, or
  the Match block that sets the value. sshd's debug output says where it reads each file and
  setting.

### Fixed

- `ssh-password` never named the file and line of a `PasswordAuthentication yes` and never
  listed Match blocks on a real server: sshd ends the lines it logs to stderr with CR LF, so
  its debug output read "yes" as "yes" plus CR. A `yes` set in a file showed as "set by a
  Match block", and the list of Match blocks stayed empty. The CR is removed first, also from
  sshd's message when `sshd -T` fails. Found on the first run of 4.1.0 against a real sshd;
  the tests had used debug output captured without the CR.

## [4.0.1] - 2026-11-14

### Fixed

- `ssh-password` reported `CHECK FAILED` although sshd had answered: the `ssh` client ends its
  messages on stderr with CR LF, and the line `Permission denied (publickey).` did not match
  with the CR at its end. The CR is removed before the line is read. Found on the first run on
  a real server; 4.0.0 was never released.
- When sshd gives no list of methods, the section says so ("no list of authentication methods
  from sshd at …") instead of "did not answer", which was wrong when it had answered.

## [4.0.0] - 2026-11-14

### Added

- A third check, `ssh-password`: it warns when the SSH server lets anyone log in with a
  password. It asks the running sshd on its local address which authentication methods it
  offers (the "none" request every client sends first; nothing logs in) and compares that with
  the configuration on disk (`sshd -T` for the same connection). Password login counts as on
  when sshd offers `password` or `keyboard-interactive`. States: `OFF` (green); `ON` with the
  file and line the setting comes from, or "sshd's default", and how to allow keys only;
  `ON` with "the configuration on disk allows keys only, but sshd still runs with the old
  one"; `ON AFTER RESTART` when only the configuration on disk allows passwords; `CHECK
  FAILED` with the last successful result; `NOTHING CHECKED` without an SSH server. Match
  blocks are evaluated only for root from the local address, so the section lists them.
- `install.sh` registers `ssh-password` when `sshd` is installed.

### Changed

- `login-warnings.service` starts after `ssh.service` and `ssh.socket`, so the check finds
  sshd listening at boot.

## [3.4.1] - 2026-11-13

### Fixed

- `apt-updates` no longer reports a finished apt update as "reached no repository or did not
  finish" when the clock was set back while it ran. It compared the times of the start and
  success stamps; after a reboot, an apt update started by another service at boot finished
  while NTP set the clock back by 0.6 seconds, so the success time lay one second before the
  start time. The start hook now leaves a marker in `/var/lib/login-warnings` that the success
  hook removes, and the check goes by the marker. `install.sh` carries over an unfinished apt
  update recorded by an older version.

## [3.4.0] - 2026-11-13

### Added

- `pg-collation` also checks the PostgreSQL bundled with the GitLab Linux package. It runs as
  `gitlab-psql` under `/var/opt/gitlab`, outside `pg_lsclusters`, so the check could not see
  it; it reaches it through `gitlab-psql` now. It is included when runit supervises it and it
  runs; at boot the check waits up to 60 seconds for it to answer, and
  `login-warnings.service` starts after `gitlab-runsvdir.service`.
- `pg-collation-fix --gitlab` rebuilds the affected databases of GitLab's PostgreSQL, as root
  and with the statement timeout turned off. It refuses while other GitLab services run. A
  mismatch there shows GitLab's procedure: `gitlab-ctl stop && gitlab-ctl start postgresql`,
  the fix, `gitlab-ctl start && pg-collation-check`.
- `install.sh` registers `pg-collation` also when only GitLab's PostgreSQL is there.

### Changed

- The OK section of `pg-collation` names the clusters it checked (`clusters: port 5432,
  GitLab`). With no running cluster it shows `NOTHING CHECKED` in orange instead of `OK`.
- `CHECK FAILED` names the cluster (`could not query: port 5432, GitLab`) instead of a port list.
- The Debian/PGDG part of the check runs only where the user `postgres` and `psql` exist;
  before, a host without them was asked on port 5432 and failed.

## [3.3.2] - 2026-11-12

### Changed

- Versions are shown as `vx.y.z` wherever a person reads them: the frame
  (`----- login-warnings v3.3.2 ---`), `login-warnings: v3.4.0 available` / `installed:`,
  `login-warnings --version`, the messages of `login-warnings update`, the installer and the
  title of the GitHub releases. Files that hold the version for programs (`VERSION=` in
  `login-warnings`, `/var/lib/login-warnings/latest-release`) and the headings of this file keep
  the bare number.
- The note for a missing apt update record says "no apt update recorded yet" instead of naming
  the major version.

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
