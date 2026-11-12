# History

A narrative log of how this project came to be. The structured, versioned list of changes
lives in CHANGELOG.md; this file records the reasoning.

## 2026-10-25 - why it exists

After a Debian 12 to 13 release upgrade, PostgreSQL 18 warned on every new connection that a
database "has a collation version mismatch": it had been created with glibc collation
version 2.36, and the system now provided 2.41. Nobody noticed, because applications ignore
the warning. It only showed up when someone opened psql to check something else, and the
same had happened after earlier upgrades.

The cause is the glibc upgrade, not the PostgreSQL upgrade, although the two often come
together. Within one Debian release the glibc version stays the same, so the mismatch appears
about once every two years. B-tree indexes on text columns are stored in the old sort order;
until they are rebuilt, lookups can miss rows and unique indexes can let duplicates through.
Refreshing the collation version alone only silences the warning, so the order is always
reindex first, then refresh.

Three ways to deal with it were considered:

- A systemd oneshot unit that rebuilds the indexes at boot, ordered before the application.
  It was written first and then dropped: the event is rare, someone is logged in during a
  release upgrade anyway, and a reindex belongs in a window the administrator picks, not
  into an unattended boot.
- The builtin collation provider of PostgreSQL 17 with `C.UTF-8` removes the dependency on
  glibc altogether. Rejected: it sorts by code point (uppercase before lowercase, umlauts
  after "z"), and an existing database can only be switched by dump and restore.
- A login banner, chosen. It queries PostgreSQL directly at every login, so it appears by
  itself when a mismatch exists and disappears once it is fixed. There is no state file,
  timer or service that can drift out of step.

The scripts are meant for every server with a local PostgreSQL, so they mention no
particular application, and all texts are in English. The procedure the banner prescribes is
"run the fix, then reboot".

## 2026-10-26 - repository layout

The scripts were to be published on GitHub and installed on the servers from there. The
repository is public so that servers can fetch it without credentials; the scripts contain
nothing secret.

- The two scripts are files of their own instead of heredocs inside the installer, so a diff
  shows exactly what changed. `install.sh` only copies them with `install -m 0755`.
- The README runs `bash install.sh` rather than `./install.sh`, because the executable bit
  gets lost when files are uploaded through the GitHub web interface.
- There is deliberately no `curl | bash` one-liner. With a clone the files are on disk
  before anything runs, and `git log` shows what changed between updates.

This work, including the tests, happened in a chat with another assistant; the tests are not
part of this repository. According to that chat, they ran in a container against a simulated
psql and against a real PostgreSQL 16, and found two bugs that are fixed in the scripts as
taken over here: a database name containing a space was split in two by `for db in $dbs`
(names are now read line by line), and one failed database stopped the whole run (the script
now continues, keeps the old collation version for the failed database and exits with 1). A
duplicate key error caused by the changed sort order was reproduced as the most likely reason
for such a failure; the script and the README explain it.

## 2026-11-12 - repository set up

The prepared files were taken over with these changes:

- `.gitattributes` is `* -text` instead of `* text=auto eol=lf`. In these repositories git
  never converts line endings in either direction. LF for the scripts is guarded by a
  pre-commit hook that refuses a commit, instead of a conversion that silently bends the
  file into shape.
- A version number: `VERSION` in `pg-collation-fix`, printed by `--version` and by
  `install.sh`. Without it nobody can tell which state a server is running. The pre-commit
  hook requires a new version section in `CHANGELOG.md` with every commit and a matching
  `VERSION`.
- The README names the GitHub owner, says that all commands run as root, mentions
  `apt install git` for minimal installations, and has development and license sections.
- MIT license.

## 2026-11-12 - first real installation, orange banner

The first installation went to the server where the mismatch had been found (three databases,
2.36 -> 2.41), using the README's "without git" route, and the downloaded files were
byte-identical to the repository. The banner appeared in the installer and at a real login,
both in Windows Terminal and in Bitvise. Between the other login messages it did not look like
a warning, so it is now printed in orange (palette index 208) and the colour is reset at its
end.

## 2026-11-12 - 2.0.0: a file written by the check, shown by the login shell

In Bitvise the banner only appeared in the first terminal window. The OpenSSH source explains
it: sshd opens the PAM session, and pam_motd with it, once per connection right after
authentication (`sshd-session.c`, `do_pam_session`), and further windows are channels on the
same connection. sshd also clears the collected login messages as soon as the first channel of
any kind starts and shows them only in a terminal channel (`session.c`, `display_loginmsg` and
the `sshbuf_reset(loginmsg)` calls), so an SFTP window or a remote command opened first
swallows the login message. pam_motd's directories (`/run/motd.d` and others, pam_motd(8))
belong to the same session and have the same limit.

A first answer kept the login message and added a profile.d script that printed the full banner
in further windows and a reminder line in the first one, telling them apart by
`$SSH_CONNECTION` and a marker per connection. The user then suggested a simpler design: run
the check when something can change and write the result to a file, and let every interactive
login show the file. That replaced the first answer before it was committed:

- the login shell only prints a file, so every window, every user, no duplicates, and no
  PostgreSQL query or timeout at login;
- the check runs after every boot (systemd, after `postgresql.service`, which itself waits for
  every `postgresql@` cluster), after every dpkg run (`post-invoke`, which must never fail
  because a failing hook aborts dpkg) and by hand;
- at the user's suggestion it also compares with the glibc installed on disk, which closes the
  gap between a glibc update and the PostgreSQL restart; the warning then says to reboot or,
  as the user added, to restart PostgreSQL and run the check by hand;
- also at his suggestion, the warning names the time of the check and how to repeat it;
- a cluster that cannot be queried keeps the previous result instead of clearing it, so a
  failed check never reads as an all-clear;
- `/run/login-warnings` is a shared directory, so later checks can add their own file. If a
  second check appears, the display part may move to a repository of its own.

The trade-off: the warning shows the state of the last check, not of the moment of login.
Version 2.0.0, because the login message goes away and systemd and dpkg parts come in.

## 2026-11-12 - renamed to login-warnings

With the shared `/run/login-warnings` in place, the user wanted the repository named after the
whole idea rather than its first check, so that further checks can join it. He suggested
something like "MOTD server checks framework"; "MOTD" was left out because since 2.0.0 the
warning deliberately does not come from the login message, and `login-warnings` matches the
directory and the profile.d script that already carry the name. The repository was renamed on
GitHub (redirects from the old name do not matter: nobody else uses it) and locally.

Only the repository is renamed. `pg-collation-check`, `pg-collation-fix`, the systemd unit and
the dpkg hook keep their names, as the first check. The framework itself, a common runner that
executes every check at boot and after dpkg and lets each server choose its checks, waits for
the second check, so that its interface is not guessed from a single example.

## 2026-11-12 - 2.1.0: never silent

After the fix on the first server the login showed nothing, and the user pointed out that
nothing can also mean a bug, a check that never really ran. He had asked earlier for the time
of the last check "egal ob mit oder ohne Warnung"; 2.0.0 put it only into the warning. So the
removed file was the same mistake as a default value that means all-clear: a missing result
and a good result looked identical.

Now every state is visible and dated: a green OK line, the orange warning, an orange FAILED
line followed by the last successful result (the old "keep the previous file" would have kept
showing a green line while the checks failed), and, for a check registered in
`/etc/login-warnings.d` without any result file, "no result since boot" with the boot time.
The trigger ("at boot") stays in the line, and date and time are always there, as the user
asked.

## 2026-11-12 - 3.0.0: package updates, and the common runner

The user asked whether a Debian server runs `apt update` by itself, suspecting it does not, and
suggested showing the available updates at login. Measured on two servers: `apt-daily.timer`
fires twice a day, but `apt.systemd.daily` exits at once because no `APT::Periodic` setting
exists, and `/var/lib/apt/periodic` was empty. Ubuntu shows updates at login through
`update-notifier-common`; Debian 13 has no such package, only tools that mail or install
(apticron, cron-apt, unattended-upgrades). So the second check is new work, not a rebuild.

Decisions, each measured on the server before it was built in:

- The lists are refreshed by apt's own timer, switched on with
  `APT::Periodic::Update-Package-Lists "1"` in a file of our own, instead of a timer of our own.
- The count comes from `apt-get -s dist-upgrade` with `Debug::NoLocking` and without cache
  files: 0.9 seconds, and `pkgcache.bin` kept its timestamp. A security update shows its
  archive in the simulation line, for example `Debian-Security:13/stable-security`, checked on
  an installed package from the security archive.
- apt's update hooks were tested in a separate list directory: `Post-Invoke-Success` runs as
  soon as one repository was fetched, even when another one has no Release file and apt exits
  with 100, and only an unreachable source alone suppresses it. So the stamps can tell "reached
  no repository", not "a repository is broken", and the README says so. A failing hook makes
  `apt update` fail ("Problem executing scripts"), so every hook ends with `|| true`.
- Lists older than two days turn the line orange: `apt.systemd.daily` refreshes once per
  calendar day, and the timer runs at least once between 6:00 and 18:00, so a working refresh
  leaves at most about 42 hours between two updates. A first version showed four-day-old lists
  in green; the test caught it.
- Pending updates alone are shown in the terminal's normal colour, security updates in orange:
  a server is often a few updates behind, and a warning that is always orange teaches one to
  ignore it.

With the second check came the common runner announced at the rename. The user asked whether
a configuration tool is needed to choose the checks; from three options (commands in the
runner, renaming files by hand, an interactive menu) the user chose the commands: `login-warnings
list`, `enable` and `disable`. A check is on while `/etc/login-warnings.d/<check>` exists and
off as `<check>.off`, which `install.sh` respects, so a switched-off check survives updates.
The login shows only enabled checks, so switching one off takes effect at the next login.
Every check runs on every trigger: `pg-collation-check` after an apt update is unnecessary but
harmless, and the runner needs no rules per check.

Version 3.0.0, because the systemd unit and the dpkg hook change their names and the version
moves from `pg-collation-fix` to `login-warnings`.

## 2026-11-12 - 3.1.0: a frame and one section per check

Before 3.0.0 was pushed, the user looked at the login in Bitvise: the update line ran past the
window edge and wrapped in the middle of a word, and the two results did not read as belonging
together. The user sketched a frame with a header, one titled block per check and a closing
line. That is now the display: `login-warnings show` draws the frame, and every check writes
one section with a title line carrying the state and indented details below 80 columns. The
collation mismatch lost its own `====` banner, because inside the frame a second frame was
noise. All six states (updates, none, security updates with a mismatch, a failed apt update
with a newer glibc on disk, both checks failing, a missing result) were rendered on the server
from the shipped scripts with fake `apt-get`, `runuser` and `pg_lsclusters` in a temporary
folder, so the rare states were seen before anyone meets them at a login.

## 2026-11-12 - 3.2.0: releases and login-warnings update

The user asked whether a release that the installation downloads would be simpler, without
git. git was already optional (the README had a route through the archive of `main`); the real
gain is that a server installs a published version instead of whatever `main` holds at that
moment, and that an update becomes one command. GitHub documents
`/releases/latest/download/<asset>` as a fixed address of the newest release's uploaded file,
so the README and `login-warnings update` use that.

- A workflow creates the release on every push, because a release that has to be made by hand
  is the one that gets forgotten. Tags were unwanted in the user's repositories unless a way of
  publishing needs them; releases do. The workflow follows the user's caddy-deb repository
  (`actions/checkout@v7`, `ubuntu-24.04`, write permission only in the job) and reads the
  version with `awk ... exit` instead of `sed | head`, because Actions runs bash with pipefail.
- The archive comes from `git archive`, with the development files marked `export-ignore`, so
  the list of what a server gets lives next to the files.
- `login-warnings update` changes the decision of 2026-10-26 that there is no
  download-and-run one-liner. It downloads only from this repository's releases, unpacks next
  to the installed copy, shows the CHANGELOG sections that are new, and only then replaces the
  copy and runs `install.sh`. It refuses to install an older release over a newer version.

## 2026-11-12 - 3.3.0: knowing when an update is due

The user asked about two ways to learn about new versions: an apt package like caddy-deb, or a
self-check. The apt package was put aside for now: Debian Policy 9.1.2 forbids packages to place
files in `/usr/local`, so every path would move, the files under `/etc` would become conffiles
while the switches in `/etc/login-warnings.d` must not, and every server would need the package
source and its signing key. For a handful of servers the self-check gives the same
information with what already exists.

It runs where the network is expected anyway, after the daily apt update, and when run by hand;
never at login, at boot or after dpkg. It reads only the redirect of `/releases/latest`
(measured on the server: curl reports it as `redirect_url`, wget prints the `Location:` header
and exits with 8 because it is told not to follow). A failed look keeps the old answer, and the
closing line of the frame shows when the last successful look was, so a silent failure ages
visibly instead of reading as "up to date".

3.3.1 packs the archive with `tar.umask` 0022: unpacked on the server, git's default 0002 had
left the source folder group-writable. 3.3.2 shows every version a person reads as `vx.y.z`, at
the user's request; where a program reads the version, the bare number stays.
