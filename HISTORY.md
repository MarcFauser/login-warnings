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
