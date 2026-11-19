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

## 2026-11-13 - 3.4.0: GitLab's bundled PostgreSQL

During the rollout, `install.sh` on the GitLab server registered only `apt-updates`: GitLab's
own PostgreSQL 17 runs as `gitlab-psql` under `/var/opt/gitlab`, there is no user `postgres`,
no `psql` in the path and no `pg_lsclusters`. Read by hand through `gitlab-psql`, every
database stored 2.41, matching the glibc on disk, and `ldd` showed the server binary linked
against the system `libc.so.6`. So a Debian release upgrade hits it like any other cluster
(the server went from Debian 12 to 13 on 2026-02-14), and the user asked for the check to
cover it.

- `gitlab-psql` is GitLab's documented database console. It reads user, socket and port from
  `/opt/gitlab/etc/gitlab-psql-rc` and drops privileges itself; a `-d` given after it wins
  over its default database (measured: `current_database()` was `postgres`). Building the
  connection from the rc file would duplicate what the wrapper already knows.
- A stopped GitLab PostgreSQL is skipped like an offline Debian cluster. At boot that would
  be wrong: runit starts PostgreSQL only after `gitlab-runsvdir.service`, so the check would
  skip it and report OK without it. At boot it therefore waits up to 60 seconds and fails if
  it gets no answer.
- An OK over no cluster at all is the empty-set all-clear this project exists to avoid, so the
  OK section now lists the clusters it checked and an empty run says `NOTHING CHECKED`.
- The fix follows GitLab's documentation ("Rebuild all indexes"): downtime, `SET
  statement_timeout = 0` (GitLab sets one minute; measured), `REINDEX DATABASE`, `REFRESH
  COLLATION VERSION`. `pg-collation-fix --gitlab` refuses while other GitLab services run,
  because a reindex would hold their tables for the whole rebuild.

Tested on the GitLab server from a private folder, with the result written there: OK with
`clusters: GitLab`, the boot run in one second, and the mismatch, glibc-on-disk, failure and
nothing-found sections produced synthetically; the fix found nothing to do and its guard
refused with the rebuild statements replaced by `SELECT`.

## 2026-11-13 - 3.4.1: the order of the hooks, not the clock

After package updates during the rollout a server was rebooted, and the first login showed
"the apt update started 17:00:21 reached no repository or did not finish", although that apt
update had worked. The boot journal explained it: `patchmon-agent.service` runs an apt update when it
starts, and while it ran, ntpdate set the clock back by 0.6 seconds. The start stamp was
written before the step (17:00:21), the success stamp after it (17:00:20), and the check took
"success before start" for an apt update that never got through. One apt update, not two: the
checks that its `Post-Invoke` hook ran show up once in the agent's journal.

Comparing two wall-clock times cannot tell the order of two events when the clock may jump
between them, and at boot it does. The hooks themselves run in a fixed order, so the start
hook now leaves a marker and the success hook removes it; the check reports an unfinished
apt update while the marker is there. A server updated from an older version may have a failed
apt update recorded the old way, so `install.sh` carries it over once, read with the old rule,
and only while the installed `apt-updates-check` does not know the marker yet; after that the
old rule is never applied again.

Tested on that server from a private folder: the stamps of that boot gave the false alarm with
3.4.0 and none with 3.4.1; a start without success, start then success, a clock set back
between the two, and an empty marker; and the carry-over block, cut from the shipped
`install.sh`, in five cases with the old and the new script as the installed one.

## 2026-11-14 - 4.0.0: a warning when SSH accepts passwords

During the rollout three servers had password login switched off by hand, and the user asked
for a warning wherever it is still possible. Asked from outside the same evening, 13 of the 17
servers that answered offered `password` (one name did not resolve). Version 4.0.0 because a
new check is a new function, as the user counts versions.

- **The running sshd is asked, not only its configuration.** sshd reads the configuration when
  it starts, so a file changed without a restart would read as "off" while passwords still
  work. The check connects to its own sshd and sends the `none` request every client starts
  with; the answer lists the methods (`Permission denied (publickey).`, measured on a server
  over `127.0.0.1` and `::1`). It logs one `Connection closed by authenticating user root ...
  [preauth]` line and logs nobody in. OpenSSH 10.0 penalises addresses that fail to log in
  (`PerSourcePenalties`, enforced from 15 seconds of penalty); five probes within 0.3 seconds
  were all answered.
- **The configuration on disk is compared with it,** evaluated for the same connection
  (`sshd -T -C user=root,addr=…`), so a pending restart shows in both directions: "sshd still
  runs with the old one" and `ON AFTER RESTART`.
- **Match blocks are listed, not evaluated.** Measured with a throwaway configuration fed to
  `sshd -T -f /dev/stdin` (a process-substitution path does not work, sshd closes the
  descriptor): without `-C`, sshd ignores Match blocks, and a `Match Address 10.0.0.0/8` with
  `PasswordAuthentication yes` only showed up with `-C addr=10.1.2.3`. All addresses and users
  cannot be tried, so the section lists the blocks. sshd itself names them, from every included
  file, in its debug output (`checking syntax for 'Match …'`), and names the file and line of
  every setting it reads outside Match blocks (`<file>:<line> setting …`); the first one wins.
  That is where "set in" and "sshd's default" come from.
- **The fix in the warning sets only the two authentication settings.** The user's own drop-in
  on three servers also sets `PermitRootLogin prohibit-password`; written by the check's advice
  on a server with `PermitRootLogin no`, that line would win (first value) and allow root again.

Tested in a WSL distribution with a fake `sshd` and `ssh` fed with `sshd -T` output captured on
a server: all states, a listener on IPv6 only, keyboard-interactive set through its old name
`ChallengeResponseAuthentication`, a setting from a matching Match block and from a file
sorting after the suggested drop-in, and the width of every line, also inside the last result
that a failed check repeats with four more columns of indentation.

4.0.1, the same evening: the first run on a real server (a Debian 13 container, from a folder
in `/tmp`, removed afterwards) said `CHECK FAILED` with sshd's own answer `Permission denied
(publickey).` printed below it. `od -c` showed why: the `ssh` client ends its stderr messages
with `\r\n`, and the pattern expected the full stop at the end of the line. The fake `ssh` of
the tests printed a line I had typed, without the CR, so every test passed. The fake now adds
the CR, and run against 4.0.0 it turns every state in which sshd answers into `CHECK FAILED`;
the check removes the CR first. The fallback message said "did not answer" although sshd had
answered; it now says that no list of methods came back. After the fix the server showed `OFF`
and `sshd offers: publickey`, one journal line per run, and `/run/login-warnings` untouched.

## 2026-11-15 - 4.1.0: the command to copy

While switching servers to keys only, the user asked why the section describes the fix ("set
PasswordAuthentication and KbdInteractiveAuthentication to no, e.g. in …") instead of showing
the `printf` line he was given each time. There was no reason on record. Three things stood in
the way of printing it blindly: the command is 117 characters and the section keeps every line
below 80; a `>` overwrites a drop-in that may exist already; and the drop-in only helps if sshd
reads it before the line that says yes.

- **The command is split with backslashes,** in three lines, so it fits and can be copied in
  one piece together with the restart line. The tests run the printed lines with bash against
  a scratch file and compare what they wrote.
- **Where sshd would read the drop-in is taken from its debug output,** which it already reads
  for "set in". OpenSSH 10.0p2, `servconf.c` lines 2343-2365: each Include logs `new include
  <glob>` (relative paths made absolute under `/etc/ssh`), then `including <file>` for every
  file in the order `glob(3)` returns them, or `no match for <glob>`. `glob` is called without
  `GLOB_NOSORT`, and sshd sets no locale (`setlocale` appears neither in `sshd.c` nor in
  `servconf.c`; `ssh.c` as a control has it), so the order is the C locale's. Lines 1377-1378:
  a setting is logged only where it applies, never inside an inactive Match block, and the
  first value wins. So the drop-in decides if sshd would reach its place - after the files of
  that Include that sort before it, before those that sort after it and before the rest of the
  file holding the Include - before the line that says yes, or if nothing says yes.
- **Otherwise the section says what to change**, not a command: the drop-in itself if it
  exists, the line sshd reads first, `/etc/ssh/sshd_config` when no Include reads the drop-in,
  the Match block that sets the value. Two cases are left with the old wording: an Include
  that follows a Match line (it may sit inside the block) and a glob with brackets.

Tested with the fakes from 4.0.0, fed with debug output built from the real one: an empty
`sshd_config.d` (Debian's default), the drop-in present, `yes` in `50-cloud-init.conf`, in
`05-early.conf`, in `sshd_config` above and below the Include, in the drop-in itself and in a
Match block, keyboard-interactive under its old name, an Include of another directory, no
Include at all, a Match line before the Include and a glob with brackets. A copy with the
sort comparison turned round failed five expectations.

The first run against a real sshd (a Debian 13 server whose SSH already allowed keys only; a
copy of its `sshd_config` in a folder in `/tmp` whose `Include` pointed to a test directory,
and a copy of the check that asked sshd with `-f` for that file and wrote its result there)
went wrong in two ways: an empty directory gave "no Include reads" instead of the command,
and a `yes` in a file gave "set by a Match block". Shown with `cat -A`: sshd ends what it logs
to stderr with CR LF (`log.c` line 409, `"%s%s%.*s\r\n"`), as the `ssh` client does, which
4.0.1 had dealt with only for the client. The glob from the debug output ended in a CR and
matched nothing, and every value read as "yes" plus CR. So 4.0.0 and 4.0.1 never showed "set
in" or the Match blocks on a real server; "sshd's default" worked because nothing was found.
The fixtures had been captured in a way that dropped the CR, which is why every test passed -
the same trap as with the client's CR in 4.0.0. The fake `sshd` now adds the CR; against the
check without the fix that turns 33 expectations red, with it none.

After the fix the same server gave the expected advice in each case: the command for an empty
directory and for `yes` in `50-cloud-init.conf` or in a Match block for another network, the
line to change for `yes` in `05-early.conf` and above the `Include`, the existing drop-in, and
`/etc/ssh/sshd_config` when the `Include` reads a missing directory. The printed command, run
as printed, wrote the two lines, and the next run said `OFF`. Against the real configuration
the check said `OFF`; the folder was removed afterwards, and the real result file stayed as it
was.

## 2026-11-15 - 4.2.0: packages that no source offers any more

The user asked why a Debian 13 container with MariaDB 12.1 from MariaDB's own repository was not
offered a newer MariaDB. Its source file had been empty since February, so apt knew 12.1.2 only
from `/var/lib/dpkg/status`, and Debian's own 11.8 is older, which apt never installs over a
newer version. Ten packages could not get any update for nine months, security updates
included, and since login-warnings was installed there, the login had said `Package updates:
none` in green: the simulation only lists what it would install. The user asked for a warning.

- **The installed version is compared, not the package name.** `apt list '~o'` (obsolete
  packages) was empty on that server, because Debian knows every one of the ten names. `apt-cache
  policy` lists every version of a package with the files it comes from, and the installed one
  is marked `***`; a version whose only file is `/var/lib/dpkg/status` has no source. It runs
  without locking and without apt's cache files, like the simulation, and took about a second
  for the whole check there.
- **dpkg and apt name packages differently.** `dpkg-query` names a package of the native
  architecture with it (`libmariadb3:amd64`), `apt-cache policy` prints `libmariadb3:`. The first
  fake for the tests used the dpkg form and silently dropped `libmariadb3`; the expected list of
  ten names caught it.
- **A package without a source counts like a security update** and makes the section orange, as
  it can never get one.

Tested with fakes for `apt-get`, `apt-cache` and `dpkg-query` fed with the output captured on
that container: the real state, the same without the ten packages (green), one package, an
update next to them, a package of a foreign architecture and one no source knows at all, and
`apt-cache` and `dpkg-query` failing. Three deliberately broken copies failed: one that took
every version as sourced, one that looked at all versions instead of the installed one, and the
old wrap width. That last one was a bug of its own: `wrap` folded at 76 columns and then added
the indentation, so a line with four columns of it could reach 80, and the last successful
result, which a failed check repeats with four more, 82. The width now counts the indentation.

Then the check ran on the container itself, from a copy that wrote its result into a temporary
folder: orange, the ten packages, widest line 74 columns, the real result file unchanged, the
folder removed afterwards.

## 2026-11-15 - 4.2.1: not the fallback kernel

The package lists of Debian 13 offered kernel images back to 6.12.90 that day, so an older
kernel still installed would show up as a package without a source. The user wanted to see
those, they can go, but not the fallback kernel that is always kept.

What counts as kept is apt's decision, so the check follows apt's source rather than a rule of
its own. salsa.debian.org and sources.debian.org answered with a proof-of-work page, so the
code was read in the GitHub mirror of apt at 3.0.3; the changelog of 3.0.4, the version in
Debian 13, lists only security fixes elsewhere. `apt-pkg/algorithms.cc`, lines 1476-1629: a
kernel is an installed package `linux-image-<uname>` (or `kfreebsd-image-`, `gnumach-image-`)
whose uname starts with digits and a dot; apt keeps the booted one and the newest ones by
package version, `APT::NeverAutoRemove::KernelCount` in all and never fewer than 2, and for
each kept uname, and always for the booted one, protects every package `<pattern>-<uname>` for
the patterns in `APT::VersionedKernelPackages` (`linux-.*`, `.*-modules` and others). The check
reads the same settings with `apt-config dump`, takes the installed versions from the policy it
already has, and orders them with `dpkg --compare-versions`: by string order 6.12.117 sorts
before 6.12.38.

One deliberate difference: the newest kernel is reported when no source offers it. apt keeps
it, but then the kernel gets no updates, which is what the section is for. And a limit: apt
also keeps what a kept package depends on, such as `linux-headers-<version>-common` and
`linux-kbuild-<version>` for the headers of the fallback kernel. The check does not follow
dependencies, so those would show up once their version has left the archive.

Tested with the fakes of 4.2.0 and three kernels in the format of the real policy blocks (two
without a source, the newest with one): booted the newest, an older one, the oldest, a kernel
without a package as in a container, `KernelCount` 3, `Protect-Kernels` false, and a single
kernel without a source. Four broken copies failed: string order instead of dpkg's, no filter,
the newest kernel hidden as well, and the booted kernel ignored.

Then on two real servers, from a copy that wrote its result into a temporary folder, removed
afterwards; the real result files stayed as they were. A Debian 13 VM had two kernels, both
still in the security archive, so a plain run did not reach the filter. A wrapper around
`apt-cache` that dropped the source lines of chosen packages let the real `apt-config`, `uname`
and dpkg decide: without a source, the older kernel was hidden, the booted newest one shown,
with both only the newest, and `linux-image-amd64` shown. A Proxmox VE 9 host keeps its kernels
as `proxmox-kernel-*`, which apt does not treat as kernels; Proxmox protects them with
`APT::NeverAutoRemove` patterns instead. Its repository offered every installed kernel and
every older version, so the check reports none; one that lost its source would be reported,
which the README says.

Both servers showed what 4.2.0 had found on the container, at a larger scale: 44 and 36
packages that no source offers, libraries left over from earlier Debian releases (`libssl1.0.2`
and `gcc-6-base` from Debian 9 on the VM, `python3.9` and `perl-modules-5.32` from Debian 11 on
the Proxmox host). On the VM 36 of the 44 were marked as installed by hand, and `apt-get -s
autoremove` removed none of them. The README now names release upgrades among the causes.

## 2026-11-16 - 4.3.0: updates orange, security updates red

During the rollout of 4.2.1 the user asked for other colours: pending updates showed in the
terminal's normal colour, which in his terminal reads as light green and so close to the
all-clear, and he wanted them orange, and security updates red. This turns round the choice of
3.0.0, where updates alone stayed plain so that an always-orange section would not teach
anyone to ignore it; with red for what is urgent, orange can mean "something to do" again.

- Red is index 196 of the 256-colour palette, next to orange as index 208, so neither depends
  on the terminal's colour scheme.
- Packages that no source offers turn red too. Since 4.2.0 they counted like a security
  update, because they never get one; the rule stays.
- A problem with the lists alone (no apt update yet, old lists, an apt update that reached no
  repository) stays orange, like `CHECK FAILED` in every check: it says the result may be
  incomplete, not that something urgent is waiting.

Tested with the fakes of 4.2.x, extended by an update without security, a security update and
lists three days old. The security update is a real simulation line, captured on a Debian 13
server by simulating the reinstall of a package from the security archive. Run against the same
tests, 4.2.1 failed the four expectations whose colour changed and passed the others.

## 2026-11-18 - 5.0.0: what can go, what must stay, and the command

Cleaning up after 4.2.1 found 13 to 44 libraries per server left over from Debian 9 to 12, and
Debian 13's release notes advise `apt purge '?obsolete'` and `apt purge '?config-files'`. Done
by hand, server by server, three config-file packages turned out to break something when
purged: `pve-kernel-helper` switches off `proxmox-boot-cleanup.service`, which
`proxmox-kernel-helper` now ships; `ifupdown` next to `ifupdown2` switches off
`networking.service`, which brings up the network of a container; `grub-pc` on a host that
boots with `grub-efi-amd64` deletes `/etc/default/grub`, which grub-efi-amd64 has registered
with ucf, and can delete `/boot/grub`. The user asked whether the check could tell such
packages, list them separately and stay green, and added that running the patterns on
everything is the dangerous part, so a command that removes only what is superfluous would be
good in the output.

- **Config files of removed packages** are new in the section. The three traps became two
  rules on the `postrm` script: a unit given to `deb-systemd-helper purge` that an installed
  package ships, and a path the script deletes that an installed package owns (`dpkg -S`) or
  has registered (`/var/lib/ucf/registry`). A third rule, a conffile in the package's own file
  list that another installed package owns, came from the script used for the manual cleanup
  and has not been seen on a server (5.0.0 said otherwise; corrected in 5.0.1). Those that
  must stay are listed with the reason and leave the section green, as the user asked; those
  that can go make it orange. The rules are not a proof, and the README says so. The state
  is read from its second letter: on one container `ifupdown` was `ic`, not `rc`, and a filter
  on `rc` would have missed exactly the case the trap was found in.
- **Packages without a source** are split, and here the user's wish was turned round: a
  package in use without a source is the case 4.2.0 was made for (MariaDB 12.1 running for
  nine months without updates), so it stays red, and the leftovers became orange. In use
  means: a running process maps one of its files, it ships an enabled or active unit, it is
  the running kernel or one apt keeps, or an installed package depends on it, directly or
  through a package in use. The last part covers a compat package that nothing depends on
  but that belongs to software in use. The kernel names mapped files by the resolved path, and
  packages from older releases list `/lib/...`, which is `/usr/lib` on Debian 13, so the
  package's paths are resolved first. A simulated purge of the leftovers has the last word: if
  it would take anything else along, they all count as in use.
- **The command** names the leftovers and the config files that can go, never a pattern, and
  has no `-y`, so apt shows its list and asks.

Tested with the fakes, extended by fake `dpkg -L`/`-S`, `systemctl`, `/proc/<pid>/maps`, dpkg's
info directory and the ucf registry: MariaDB running and not running, a package mapped through
`/lib`, one needed by an installed package, a purge that would take another package along, the
running kernel with kernel protection off, and the three traps with `postrm` lines quoted from
the real scripts. Six copies with one rule taken out each failed exactly in their test. Then
on two servers from a copy that wrote into a temporary folder: on a PBS host with `grub-pc` and
`pve-kernel-helper` both were named as must stay with the right reason and the section stayed
green; on another, with the source of three packages hidden from the check, the PBS server
package and `libssl3t64` were in use and `less` left over, with `apt purge less`. That `less`
counts as left over shows the limit the README names: not in use means not in use now.

## 2026-11-18 - 5.0.2: an alternative is not a dependency

The first server of the rollout after 5.0.1, a Debian 13 VM upgraded from Debian 12, had 19
packages without a source. 5.0.1 called three of them in use: `mime-support` and the two Python
3.11 libraries. No process mapped their files, and apt's simulated purge of all 19 took nothing
else along. The cause was the dependency list: it split `Depends` at `|` as well as at `,`, so
`python3.13`, which depends on `media-types | mime-support`, counted as needing
`mime-support`, although `media-types` was installed. The Python 3.11 libraries depend on
`mime-support` and followed it. The error kept packages rather than removing them, but it
showed red for software that does not run, and the `apt purge` line left the three out.

A member of an alternative now counts only when no other member is installed with a source,
by name or as something such a package provides. A member whose partner is only virtual and
not provided still counts, which keeps a package rather than removing it, and the simulated
purge still has the last word. Tested with a new fake case for all three (partner installed,
partner provided, partner missing); two copies with the rule taken out, one without the
alternatives and one without `Provides`, failed exactly there. On the server, from a copy in a
temporary folder, all 19 were then left over and the command named them.

## 2026-11-18 - 5.0.3: a path that stops at a variable

The next server had no packages without a source but 16 removed packages with config files,
and 5.0.2 kept six of them: `libnginx-mod-*`, "its purge would delete /etc/nginx/modules-enabled/
of nginx-common". Their `postrm` deletes `/etc/nginx/modules-enabled/$to` and `$to.removed`,
its own links, which on that server were six dead `.removed` links from 2022. The pattern that
finds paths in a `postrm` stops at the first `$`, so the path became the directory, and
`dpkg -S` names nginx-common as its owner. The check said "must stay" for a purge that only
removes leftovers.

A path cut short by a variable or a wildcard now stands for what lies below its beginning.
`dpkg -S` takes `<beginning>*` as a pattern over the files that packages own, and `*` there does
not match the directory itself: measured on the server, `/etc/nginx/modules-enabled/*` found no
owner while `/etc/nginx/sites-available/*` found nginx-common's `default`. The paths are read
line by line, because a shell loop over them would expand the pattern against the disk.

The round also raised the other limit: the server before had two removed XWiki packages, and a
`postrm` that drops a database or deletes a data directory would not show up in any of the
three rules, because data belongs to no package. Their scripts were read by hand
and did nothing of the kind; the README and the comment above the rules now say that the check
cannot see this.

Tested with a fake case built from the real `postrm` lines next to one that deletes below a
directory with an owned file; a copy that cuts the path as before failed there. On the server,
from a temporary copy, all 16 could then go.

## 2026-11-18 - 5.0.4: links, provided names, and a key for apt

A server upgraded release by release since Debian 8 had 71 packages without a source, and
5.0.3 called 43 of them in use, red: four generations of gcc, their libraries, `libgcc1`.
Nothing of them ran. Two rules were wrong.

The files of a package were resolved with `realpath` before they were compared with the files
processes map. That was meant for `/lib`, a link to `/usr/lib` on Debian 13, but it also
follows links that a package ships to files of another package: an old `libgcc-10-dev` has
`libatomic.so` pointing to `libatomic.so.1` of `libatomic1`, which half the processes map. Now
only the directories are resolved, and the file keeps its name. The dependencies did the rest:
everything that depends on the old gcc libraries followed them.

`libgcc1` itself was in use because installed packages still depend on it by that name.
`libgcc-s1` provides it. 5.0.2 had taught the check that an alternative is met by any installed
member; a single name met by a provider is the same case, and now a dependency counts only when
no installed package with a source meets it.

On the same server, `pgdg-keyring`, removed long ago, would have been listed as one that can
go. Its `postrm` deletes `/etc/apt/trusted.gpg.d/apt.postgresql.org.gpg`, a link nobody owns,
pointing to `postgresql-client-common`'s copy of the key; the PostgreSQL repository there has
no `signed-by`, so apt trusts it only through that link. None of the rules saw it, because the
link belongs to no package. A link that the `postrm` deletes and that points to a file of an
installed package now keeps the package: something set it up for that package.

Tested with two fake cases (a link into another package plus a provided dependency; the key
link next to a plain file nobody owns); three copies with one of the fixes taken out failed
exactly there, and two copies of 5.0.2/5.0.3 rules no longer matched the code and were
rewritten for it. On the server, from a temporary copy, all 71 were left over and
`pgdg-keyring` must stay, next to `grub-pc`.

## 2026-11-19 - 5.0.5: two spellings of one file, and the kernel's own version

On the same server a folder below `/lib/modules` was nearly taken for one that belongs to no
package: `dpkg -S /lib/modules/6.12.116+deb13-amd64` said "no path found". It belongs to the
installed fallback kernel, which dpkg recorded as `/usr/lib/modules/...`. On a merged `/usr`,
`/lib` is a link to `usr/lib`, and dpkg answers only for the spelling a package recorded. The
rules for removed packages asked dpkg about paths as the `postrm` spells them, so a `postrm`
that deletes `/lib/...` of a file an installed package recorded as `/usr/lib/...` would have
been listed as one that can go. Seen on no server; found by reading the code after that slip.

Paths below `/bin`, `/sbin`, `/lib`, `/lib32`, `/lib64` and `/libx32` are now asked in both
spellings, and only where those are links into `/usr`: where they are real directories, the
other spelling is another file. The links are looked up below `ROOT`, empty on a server, so
that the tests can build both kinds of system.

The obvious way of doing it would have kept every removed kernel. Debian's kernel `postrm`
deletes `/lib/modules/$version/.fresh-install` and `/lib/modules/$version/$extra_file`; since
5.0.3 such a path stands for everything below `/lib/modules/`, and in the other spelling that
holds the modules of each installed kernel (5,179 files each, measured on the server). Removed
kernels could go before only because the spellings differed. The script sets
`version=6.12.117+deb13-amd64` once, at the top, so a variable that a `postrm` sets once,
unindented and to a fixed value, is now put in before its paths are read, and the path becomes
the kernel's own module directory. A variable set again, or by a `for` loop or `read`, keeps its
name and stays a pattern: its value is not known.

Tested with two fake cases on the same removed packages, merged and not merged: a kernel with
the lines of a real `postrm`, a library and a plugin directory in the other spelling, and two
packages that set a variable twice or read it. Six copies with one of the rules taken out
failed there. On the server, from a temporary copy, `grub-pc` and `pgdg-keyring` still must
stay; the new functions, run there on the real kernel `postrm` with a version that is not
installed, found no owner with the value put in, and both installed kernels without it.
