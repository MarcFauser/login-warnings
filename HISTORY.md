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
