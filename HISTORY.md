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

## 2026-11-23 - 5.1.0: what apt autoremove would remove

On a Proxmox VE host apt said that a package was "automatically installed and is no longer
required", an older kernel of the 7.0 series, while the login section said "Package updates:
none". Nothing was wrong with the rules; the kernel was simply outside them. The check reports
packages without a source and removed packages with config files, and this kernel still had a
source: the Proxmox repository keeps the older kernels. Proxmox's own `APT::NeverAutoRemove`
lines keep the running kernel and the newest of each series, so apt would autoremove it. The
README even said that on Proxmox an old kernel shows up only once the repository stops offering
it.

The check now runs `apt-get -s autoremove` next to the upgrade simulation, without locking, and
names what apt would remove. A package without a source that apt would autoremove too stays
where it was, in use or left over, so nothing is listed twice. The command is `apt remove`, not
`apt purge`: purging runs the `postrm`, which the rules for removed packages exist to check,
and a removal leaves the package's config files for exactly that check on the next run. That is
two steps for a kernel, and each of them is checked.

On the same host, the kernel's `postrm` turned out to be Perl: `unlink` and `glob` instead of
`rm`. The rules read shell commands only, so such a script shows them nothing; for this kernel
it deletes only its own initrd and module index files, read by hand. The README says so now.

A kernel installed by hand is not covered: apt never autoremoves it, so it stays until it is
removed by name. The same host had one.

Tested with three fake cases: the lines apt printed on the host, a package that is also left
over without a source (with an architecture suffix on one name), and a failed simulation. Four
copies with one part taken out failed there. On the host, from a temporary copy, the section
named the kernel and the command, with the real result file untouched.

## 2026-11-25 - 6.0.0: programs that use replaced files

After bringing the same Proxmox VE host up to date, the user asked whether the login could also
show services and programs that still use outdated libraries. An update replaces a library on
disk; a program that runs keeps the old one until it restarts. On another server that week,
systemd, logind, sshd, journald, networkd and PostgreSQL had kept an old libzstd after a
security update until a reboot.

Debian has two tools for this, and both were read before anything was built: `needrestart`
(Perl, the main script and its example configuration, read from GitHub) and `checkrestart` from
`debian-goodies` 0.88.2 (Python, downloaded with apt into a temporary folder and unpacked, not
installed; sources.debian.org answered with a proof-of-work page). Both find processes whose
maps name a deleted file and assign them to a systemd unit by their cgroup. They differ in what
counts: `checkrestart` reports every deleted file a process holds, logs and data included, and
needs a long list of excluded paths or a filter to files from packages; `needrestart` looks only
at executable mappings. The check follows `needrestart` here, with its list of what is deleted
by design (SysV, memfd, `/dev`, `/tmp`, `/run`, JIT files). It takes the services that should not
be restarted on the fly from both, `systemctl try-restart` and a details view from
`checkrestart`. Neither is called: `needrestart` hooks into apt and by default asks after every
upgrade, which would change how apt behaves on the servers; `checkrestart` needs Python and
`lsof` and writes for a terminal. Its filter to package files was left out on purpose, because
it would miss software outside packages, such as GitLab's `/opt/gitlab/embedded` or a Node.js
from nvm, which need a restart after their own updates as much as anything else.

Containers needed a measurement. The first idea, a mount namespace other than PID 1's, was
wrong: on a Debian 13 container, caddy, MariaDB, systemd-logind, systemd-networkd and postfix's
master ran in mount namespaces of their own (`ProtectSystem`, `PrivateTmp`) and are services of
that system, while the Docker containers also had their own. The root file system told them
apart, Docker containers have their own, except for postfix's `pickup`, which runs chrooted and
so has another root as well, inside `postfix.service`. So a process counts as a container's when
its root differs and it is not part of a system service. The same container showed why only
executable mappings count: 206 of 274 deleted mappings were not executable (memfd, `/dev/zero`,
SysV), and the 68 executable ones were all `memfd:doublemapper` of a dotnet in a Docker container.

Tested with seven fake cases on a fake `/proc` (nothing replaced next to what is deleted by
design; every kind of process at once; the details; a restart command long enough to be split;
only a container; nothing readable; no root for PID 1). Nine copies with one rule taken out each
failed there. On the container, from a temporary copy: green, 44 processes, 35 ms. As a
positive control, a `sleep` started in the SSH session with `LD_PRELOAD` on a copy of libz whose
file was then deleted: the check named a session of root with that file, and the process and the
folder were removed afterwards.

Then on the Proxmox VE 9 host that had just been updated, from a temporary copy: 35 of 451
processes in 302 ms, 17 services, systemd-logind among those to restart with care, systemd
itself, and six VMs, each as `/qemu.slice/<vmid>.scope` with its `kvm` and `swtpm`. The run also
found a rule wrong: systemd-udevd runs in `systemd-udevd.service/udev`, a cgroup below its
service, and would have been listed as another program. A service now counts with the cgroups
below it as well; a fake case covers it, and a copy with the old rule fails there. The host ran
no LXC containers, so containers have only been seen from inside one so far.

Version 6.0.0, because a new check is a new function.

## 2026-11-25 - 6.1.0: a reboot, and the security updates

Within the hour the user saw long lists on every server and asked whether they were right. On
the Proxmox VE host they were, every one of them: the host had booted on 2026-11-21, and dpkg's
log showed two updates since, both from the security archive (krb5 on 2026-11-23, libzstd on
2026-11-25). Every process the check named had started before them; the pvedaemon workers of
that night only looked newer, they are forked from a pvedaemon that is not. libzstd comes in
through `libsystemd-shared`, so systemd itself, journald, udevd, logind, sshd and every Proxmox
service map it, and krb5 through everything with GSSAPI, QEMU included.

So a long list is the normal case after such an update, and the useful answer is a reboot. With
systemd itself or a service that should not be restarted on the fly among the processes, the
section now says that first. And it now tells whether the restart matters for security: the
package that owns a replaced file's path now is asked with `dpkg -S`, in both spellings on a
merged `/usr` and, for a library whose new version has another file name, as `<name>.so.*`
(checkrestart's way); if `apt-cache policy` shows its installed version from a `-security/`
archive, the running programs miss that fix, and the section turns red, as `apt-updates` does
for a security update not yet installed. On the host, with the same name for the old and the
new libzstd (a Debian security update keeps the upstream version), it named the five krb5 and
libzstd packages.

The long lists also showed a layout fault: a list after a heading on the same line wrapped onto
a line with the heading's indentation and looked like the next item. Every list now stands
below its heading, as the services did.

Tested with the fakes of 6.0.0, extended by a fake `dpkg -S` and `apt-cache policy` (the libzstd
block as the host printed it): a file found under its own name, one only in the other spelling,
one only by the soname pattern, a package whose security update waits uninstalled (not red), and
a container's file from a security update (not red either). Seven new copies with one part taken
out failed there, the seventeen in all. On the host, from a temporary copy, 896 ms; on the
container, still green.

## 2026-11-25 - 7.0.0: a VM disk without its link

The same evening a VM on the Proxmox VE host did not start after a reboot: "no zvol device link
for 'vm-114-disk-2' found after 300 sec". udev had failed on the zd device of that volume at boot
("Failed to process device, ignoring: Unknown error 512"), and nothing tried again.
`udevadm trigger --action=add` on the device brought the link back, and the VM started without a
reboot of the host. The journal showed the same udev message in 3 of 99 boots, under kernels 6.14
and 7.0. The user wanted to see it at an SSH login when this happens.

Read on the host before anything was built: `zfs-volume-wait.service` (`zvol_wait`, OpenZFS
2.4.4) only waits; Proxmox VE's `zfs_wait_for_zvol_link` (`ZFSPoolPlugin.pm`, libpve-storage-perl
9.1.26) looks for a block device behind the link for 300 seconds in a worker and never re-triggers
udev; and `pve-guests.service` is ordered after nothing of ZFS, so the guests started while
`zvol_wait` was still waiting. So the check takes `zvol_wait`'s rule for which volumes need a link
(volmode, redaction, key status, partial receive), counts a link the way Proxmox VE does (a block
device behind it), and finds the zd device of a volume with `zvol_id`, as the udev rule does.

The repair is a oneshot unit after `zfs-import.target` and before `pve-guests.service`. It
re-triggers only what udev would have handled: a volume whose zd device exists, once udev is idle,
at most three times. A volume without a zd device waits for ZFS, not for udev, and waiting is all
that helps there. 60 seconds is its limit, because every second of it delays the guests. Its
record in `/var/lib` survives the reboot, so the next boots still say that a repair was needed;
the record of the current boot lives in `/run`.

Two faults turned up before the release. The fakes showed that at its deadline the repair forgot
that udev had been idle and reported it as still busy. The test on the host, which ran the repair
by hand, showed that such a run would appear at the next login as a repair at boot. Now only the
unit's run (`--trigger boot`) records anything, and a fake case covers a repair by hand.

Tested with nineteen fake cases (every state of the section, the repair with and without a zd
device, a trigger that does not help, udev that stays busy, a dry run, the next boot, a repair by
hand) and sixteen copies with one rule taken out each, every one failing there. On the host, from
a temporary copy that wrote into a temporary folder: OK with 49 volumes, and a dry run of the
repair in 149 ms. Then the failure on purpose: a 4 MB test volume, whose link was deleted by hand
while its zd device stayed. The check reported it as missing with the trigger command, the repair
brought the link back in 1.3 seconds, and the check then showed the repair. The test volume was
destroyed afterwards, and the 49 volumes had their 49 links again. `systemd-analyze verify` found
nothing to complain about in the unit. Its place in the boot order shows only in a real reboot,
which has not happened yet.

Version 7.0.0, because a new check is a new function.

## 2026-11-26 - 7.0.1: a writer that meets a closed pipe

Installing 7.0.0 on the Proxmox VE host, run as a transient systemd unit so that a dropped SSH
connection could not cut it short, printed one stray line: `grep: write error: Broken pipe`.
systemd runs services with SIGPIPE ignored (`IgnoreSIGPIPE=yes`, the default, read from both
units of this project). A program that writes into a pipe whose reader has stopped then does not
die quietly from the signal, as it does in a terminal, but gets an error and says so on stderr,
which is the journal. The journal of the host had that line once in every boot since the boot
after 5.0.5 went in, and not in the boots before.

Two guesses were wrong before the cause was found: replacing `head` at the two places that looked
alike changed nothing. A trace with `sh -x` of a temporary copy under systemd found it: the rule
for systemd units asks `owners` for both spellings of a unit file and pipes both answers into one
`head -n 1`. The first answer arrives, `head` quits, and the second `owners` writes into the closed
pipe. The result never changed: the scripts run under `sh` without `pipefail`, and the status of a
pipe is that of `head`.

Measured with `dash` and `trap '' PIPE`, which is inherited the way `IgnoreSIGPIPE=yes` is, 300 runs
for each shape: two writers in turn into `head -n 1`, 299 errors; one writer with a few lines, 0,
because it writes them at once before the reader can stop; any writer of more than 64 KiB, the
size of a pipe, the shell's own `printf` included, every time, also into `awk` with `exit` or
`grep -q`; a loop left with `break`, every time; a here-document, never; and `sed -n 1p` in place
of `head`, never in any shape. With `pipefail` the status is 141 without the signal ignored and 2
with it.

So every reader in the scripts that stopped before the end of its input now reads to the end, 36
places in all, also the ones that only worked because their data was small: `sed -n 1p` and
`sed -n 1,3p` for `head`, `grep ... >/dev/null` for `grep -q`, a flag for `awk`'s `exit` (two of
those programs read sshd's debug output in `ssh-password-check`, which can exceed 64 KiB), and a
loop in `zvol-links-check` that ran to its end instead of leaving at the first volume without a zd
device.

Tested: the four test suites, once as before and once with SIGPIPE ignored. On 7.0.0 the
apt-updates suite showed 28 write errors with SIGPIPE ignored, now none; with only the one line put
back, 28 again. Their output did not change against 7.0.0 apart from the times of an `ls -l`, so the
change is one of form. A lint that lists such readers found the 36 places in 7.0.0 and none now. The
copies with one rule taken out still fail in all three suites that have them.

Version 7.0.1: a fix, nothing new.

## 2026-11-26 - 7.1.0: PostgreSQL in Docker

On a host whose only PostgreSQL ran in a Docker container, a dump printed PostgreSQL's warning
that the database `postgres` was made with collation version 2.36 while the system provides 2.41,
and the login had shown nothing. The user's words: the tool was installed and showed nothing,
which is exactly what it was built for. The README said that containers were not covered, and
`install.sh` had not even switched the check on there, so there was no section at all, not even
`NOTHING CHECKED`: the silence the README promises never to allow.

Read and measured before anything was built: the official image's entrypoint makes
`POSTGRES_USER` the superuser (`initdb --username="$POSTGRES_USER"`) and leaves local connections
on initdb's `trust`; on the host the role `postgres` did not exist, because `POSTGRES_USER` named
another. The container's server process had the cgroup `/system.slice/docker-<id>.scope` and
`containerd-shim` as its parent. At the last boot `login-warnings.service` had run in the same two
seconds as `docker.service`, while the containers got their networks 0.4 seconds before Docker
reported ready: without an ordering the check at boot would have missed them.

So the check now finds PostgreSQL by its server processes in `/proc` and sorts them by cgroup:
native Debian/PGDG clusters, GitLab's under `gitlab-runsvdir.service`, Docker containers, guests of
the host (LXC, which check themselves), and anything else, which is named as not checked so that
PostgreSQL on the host is never passed over. Containers are queried with `docker exec` and `psql`
as the image's superuser; the host's glibc on disk is left out for them, since a container runs
with its image's. `login-warnings.service` runs after `docker.service`, and at boot the check
waits up to 60 seconds for the containers of its last run, kept in `/var/lib`, and checks a running
one even if its server was not seen, so that one that never answers fails the check.
`pg-collation-fix --docker` rebuilds the indexes in a container.

Tested with twenty-eight fake cases against a fake `/proc` and `docker`, whose `exec` runs the
check's own shell code in the container's environment, so the choice of the user is the real one;
twenty copies with one rule taken out each fail there. One did not at first: the copy without the
LXC rule passed, because the guests in the test ran `postgresql@` units, which the rule for
native clusters already recognises. The rule matters for Docker inside a guest, which the host's
`docker` does not know, and the case got that. Then live, with the user's consent, on the Docker
host: a test database made with `postgres:16` on Debian 12 (glibc 2.36), the same folder started
with `postgres:16` on Debian 13 (2.41), which printed the very warning of the dump. The check
reported the mismatch for its three databases, `--docker` rebuilt them, and the check then said OK
for that container and the real one; afterwards the test container, its folder and the image were
removed. Read only on three more hosts: a second Docker host (OK), the GitLab host (its server in
`/gitlab.slice/gitlab-runsvdir.service`, OK) and a Proxmox VE host with a cluster in an LXC guest
(`/lxc/102/...`, left out, nothing named as not checked).

Version 7.1.0, chosen by the user: the same check for one more kind of cluster, like GitLab's in
3.4.0.
