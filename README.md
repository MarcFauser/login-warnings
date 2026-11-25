# login-warnings

Warnings that every interactive login shell on a Debian server shows, in every terminal
window. Each check writes one section of the display into `/run/login-warnings`, always with
the time it ran: green when all is well, orange when something needs attention, red for
security updates.

```
----- login-warnings v4.0.0 --------------------------------------------
Package updates: 3 (0 security)
  libpq5 postgresql-18 postgresql-client-common
  show: apt list --upgradable
  lists from 2026-11-12 21:53:09 +01:00 (50 min ago)
  checked 2026-11-12 22:43:09 +01:00 (at boot)
  check again: apt-updates-check

PostgreSQL collation: OK
  clusters: port 5432
  checked 2026-11-12 22:43:09 +01:00 (at boot)
  check again: pg-collation-check

SSH password login: OFF
  sshd offers: publickey
  checked 2026-11-12 22:43:09 +01:00 (at boot)
  check again: ssh-password-check

----- latest release checked 2026-11-12 23:06:35 +01:00 ----------------
```

Every line stays below 80 columns, so nothing wraps in a normal terminal window.

Five checks so far:

| Check | Reports |
| --- | --- |
| `apt-updates` | Package updates offered by the package lists, by name, security updates separately, how old the lists are, installed packages that no package source offers any more (in use, or left over from an older release), config files of removed packages that can go or must stay, and the `apt purge` command for exactly what can go; packages `apt autoremove` would remove, with an `apt remove` command for exactly those. |
| `pg-collation` | PostgreSQL databases whose collation version no longer matches glibc, with a fix script. Covers the Debian/PGDG clusters and the PostgreSQL bundled with the GitLab Linux package. |
| `ssh-password` | Whether the SSH server accepts password logins, where the setting comes from, and how to allow keys only. |
| `restart` | Programs that still use files an update has replaced, usually libraries: the services with a `systemctl try-restart` command for exactly those, systemd itself, logged-in users and Proxmox VE VMs; red when one of the files came with a security update. |
| `zvol-links` | ZFS volumes that have no link in `/dev/zvol`, so that a Proxmox VE VM using one does not start, with the commands that bring the link back; what the repair at boot re-triggered. |

## How it works

| File | Purpose |
| --- | --- |
| `/usr/local/sbin/login-warnings` | Runs every enabled check, shows the results, switches checks on and off, installs updates. |
| `/etc/login-warnings.d/<check>` | One file per enabled check; its first line is the command that runs it. `<check>.off` is a check that is switched off. |
| `/etc/systemd/system/login-warnings.service` | Runs every enabled check once after every boot, after PostgreSQL has started (and after `gitlab-runsvdir.service`, which starts GitLab's PostgreSQL), after sshd listens (`ssh.service` or `ssh.socket`) and after the zvol link repair. |
| `/etc/systemd/system/login-warnings-zvol-repair.service` | Re-triggers udev at boot for ZFS volumes without a link in `/dev/zvol`, before Proxmox VE starts its guests. Enabled where ZFS is installed; runs only while `zvol-links` is switched on. |
| `/etc/dpkg/dpkg.cfg.d/login-warnings` | Runs every enabled check after every dpkg run (`post-invoke`). |
| `/etc/apt/apt.conf.d/80login-warnings` | Refreshes the package lists once a day and runs every enabled check after every apt update. |
| `/etc/profile.d/login-warnings.sh` | Runs `login-warnings show` in interactive login shells: in every terminal window, for every user, and never in scripts or file transfers. `show` puts the sections of all enabled checks into one frame. |
| `/usr/local/sbin/apt-updates-check` | The `apt-updates` check; writes `/run/login-warnings/apt-updates`. |
| `/usr/local/sbin/ssh-password-check` | The `ssh-password` check; writes `/run/login-warnings/ssh-password`. |
| `/usr/local/sbin/pg-collation-check` | The `pg-collation` check; writes `/run/login-warnings/pg-collation`. |
| `/usr/local/sbin/pg-collation-fix` | Runs `REINDEX DATABASE` on every affected database, then `ALTER DATABASE ... REFRESH COLLATION VERSION`. The version is only refreshed if the reindex succeeded. With `--gitlab` it works on GitLab's bundled PostgreSQL. |
| `/usr/local/sbin/restart-check` | The `restart` check; writes `/run/login-warnings/restart`. |
| `/usr/local/sbin/zvol-links-check` | The `zvol-links` check; writes `/run/login-warnings/zvol-links`. With `--repair`, the repair the unit above runs at boot. |
| `/var/lib/login-warnings` | When the last apt update started and when it last reached a repository, and a marker while an apt update has not reached one; the latest release and when it was checked; the last zvol link repair that did something (`zvol-links-repair`). |

Nothing is ever silent: an empty login would look exactly like an all-clear. Every section
names date, time and trigger of its check (at boot, after a package change, after apt update,
by hand) and how to repeat it. A check that fails shows `CHECK FAILED` in orange and its last
successful result below. An enabled check without any result shows `NO RESULT` with the boot
time.
`/run` is emptied at reboot, and the run at boot writes the results again.

The warnings come from the login shell and not from the login message (motd): sshd shows the
login message only once per SSH connection, and clients like Bitvise open further terminal
windows on the same connection.

## Choosing the checks

`install.sh` switches on `apt-updates` and `restart`, `ssh-password` if an SSH server (`sshd`)
is installed, `pg-collation` if PostgreSQL is installed locally (from the Debian or PGDG packages, or
bundled with the GitLab Linux package), and `zvol-links` if ZFS has volumes (`zfs list -t volume`).
A check you switch off stays off when you install an update.

```bash
login-warnings list
login-warnings disable apt-updates
login-warnings enable apt-updates
```

`enable` runs the check at once and shows its result; `disable` removes its result, so the
login stops showing it immediately. If PostgreSQL is installed later, `login-warnings enable
pg-collation` switches its check on. Likewise `login-warnings enable zvol-links` for ZFS volumes
created later; if ZFS itself came later, run `bash /usr/local/src/login-warnings/install.sh`
again, which enables the repair at boot.

Run every enabled check by hand and see the results, or a single check:

```bash
login-warnings
apt-updates-check
pg-collation-check
ssh-password-check
restart-check
zvol-links-check
```

## apt-updates: package updates

Debian does not refresh the package lists by itself. `apt-daily.timer` starts
`/usr/lib/apt/apt.systemd.daily` twice a day, but without an `APT::Periodic` setting the
script exits at once. `/etc/apt/apt.conf.d/80login-warnings` sets
`APT::Periodic::Update-Package-Lists "1"`, so the lists are refreshed once a day. Only the
lists are downloaded; no package is downloaded or installed.

The check itself downloads nothing. It simulates `apt-get dist-upgrade` on the lists on disk,
without locking and without writing apt's cache files, so it can run while apt or dpkg is
working. It runs after every apt update (by hand or from the timer), after every dpkg run (so
installed updates leave the list) and at boot.

It also asks `apt-cache policy` which versions the package lists offer of every installed
package, and names the packages whose installed version none of them offers any more. Such a
package gets no updates, security updates included, and the simulation does not show it: its
package source was removed or the source file emptied, it was installed from a `.deb` file, or
it is left over from an older Debian release (libraries such as `libssl1.1` stay installed
after a release upgrade, and most of them are marked as installed by hand, so `apt autoremove`
keeps them).
`apt list '~o'` does not find all of them, because it matches only a package whose name no
source knows: when the source of a newer version is gone and Debian still offers an older
version under the same name, which apt never installs over the newer one, `~o` lists nothing.

### In use or left over

A package without a source is either software that runs and gets no updates, the urgent case,
or a leftover that nothing needs. The check tells them apart and lists them separately:

- **In use** (red): a running process has one of its files mapped (a library or the
  executable), it ships a systemd unit that is enabled or active, it is the running kernel or
  one that apt keeps, or an installed package depends on it, directly or through another
  package in use. A package that depends on one in use belongs to the same software and is in
  use too, like `mariadb-server-compat` next to `mariadb-server`. A dependency counts only when
  no installed package with a source satisfies it, by name or as something it provides: in
  `media-types | mime-support` an installed `media-types` is enough, and a dependency on
  `libgcc1` is met by `libgcc-s1`, which provides it. A package's files are compared with the
  mapped ones after resolving their directories (`/lib` is `/usr/lib`), not the files
  themselves: a link a package ships to another package's library (`libatomic.so` in
  `libgcc-10-dev`) does not make it in use.
- **Left over** (orange): nothing of the above. apt's simulated purge of all leftovers must
  remove nothing else; if it would, they all count as in use. "Now" is the limit: a program
  that only runs now and then, from cron or by hand, is not seen.

A package that cannot be checked counts as in use.

### Config files of removed packages

A package removed without purging leaves its config files and the dpkg state `rc` (or `ic`).
Debian's release notes advise `apt purge '?config-files'` after a release upgrade, but purging
runs the package's `postrm` script, and on real servers that broke what an installed package
needs. A package with config files left must stay when its purge would

- switch off a systemd unit with `deb-systemd-helper` that an installed package now ships
  (`pve-kernel-helper` and `proxmox-boot-cleanup.service` of `proxmox-kernel-helper`;
  `ifupdown` and `networking.service` of `ifupdown2`),
- delete a file that an installed package owns or has registered with `ucf` (`grub-pc` and
  `/etc/default/grub` on a host that boots with `grub-efi-amd64`); a path that the script
  builds with a variable or a wildcard (`rm /etc/nginx/modules-enabled/$to`) stands for what
  lies below its beginning, not for the directory it stops in,
- delete a link that nobody owns but that points to a file of an installed package
  (`pgdg-keyring` and `/etc/apt/trusted.gpg.d/apt.postgresql.org.gpg`, through which apt
  trusts the PostgreSQL repository with the key of `postgresql-client-common`), or
- delete a conffile from its own file list that another installed package owns.

The others can go. The first three were seen on real servers; the last is a precaution and has
not been seen: when a conffile moves to another package, dpkg normally takes it off the old
package's list (as with `/etc/magic` from `libmagic1` to `libmagic1t64`). None of this is a
proof: the check reads the `postrm`, it does not run it, and it reads the shell commands `rm`,
`ucf` and `deb-systemd-helper`: a `postrm` in another language, like the Perl script of a Proxmox
VE kernel, shows it nothing. Nor can it see a `postrm` that deletes data no package owns, such
as a database or a data directory: for a package of software that keeps data, read the script
before purging it.

Paths are read the way dpkg knows them. On a merged `/usr` (`/lib` is a link to `usr/lib`,
likewise `/bin`, `/sbin`, `/lib32`, `/lib64`, `/libx32`), dpkg finds a file only under the
name its package recorded: a Debian 13 kernel's modules are `/usr/lib/modules/...`, while its
`postrm` deletes `/lib/modules/$version/...`. So a path below these links is looked up in both
spellings, and only where they are links. A variable that the `postrm` sets once, unindented
and to a fixed value, is put in first: the kernel's `version=6.12.117+deb13-amd64` makes the
path its own module directory instead of everything below `/lib/modules/`, where the modules of
every installed kernel are. A variable set again, or by a `for` loop or `read`, stays a
pattern.

Should a conffile ever be in the way, the package can still be purged and the file brought
back by its owner: `apt install --reinstall -o Dpkg::Options::=--force-confmiss <owner>`
installs config files that are missing. Local changes to the file are lost that way, so keep a
copy first.

### The command

When something can go, the section ends with an `apt purge` command that names exactly the
leftovers and the config files that can go, never a pattern like `'?obsolete'`, which would
take packages in use and config files that must stay along. It has no `-y`: apt lists what it
would remove and asks first. Long commands are split with backslashes so that they can be
copied in one piece.

### Packages apt no longer needs

The check also simulates `apt autoremove` and names what it would remove: packages installed
automatically that nothing installed needs any more and that `APT::NeverAutoRemove` does not
keep. Most of them still have a source and show up nowhere else, an old kernel above all. Those
without a source are listed once, as in use or left over. The section ends with an `apt remove`
command for exactly these packages, not `apt purge`: a removal leaves their config files, and
the next check names those as config files of removed packages and says whether they can go or
must stay, as for any other removed package.

### Kernels

Old kernels show up as left over once their version has left the archive, and the command
names them. The kernel that apt keeps as a fallback is not reported: apt keeps the running
kernel and the newest ones, two in all unless `APT::NeverAutoRemove::KernelCount` says more, and
the check applies the same rule. The newest kernel is reported as in use when no source offers
it, because then the kernel gets no updates. Proxmox VE kernels (`proxmox-kernel-*`) are not kernels to apt:
Proxmox keeps them through `APT::NeverAutoRemove`, which the check does not read, so one would
be reported if the Proxmox repository stopped offering it. On a Proxmox VE 9 host checked on
2026-11-16 the repository offered every installed kernel and all older versions. An old kernel
that apt would autoremove and that still has a source appears under packages apt no longer
needs. A kernel installed by hand is never one of them: apt keeps it until it is removed by name.

| State | Section |
| --- | --- |
| no updates | `Package updates: none` (green) |
| updates | `Package updates: 3 (0 security)`, the package names (orange) |
| security updates among them | `Package updates: 3 (2 security)`, a `security:` and an `other:` line (red) |
| last apt update reached no repository or did not finish | an extra line saying so (orange) |
| lists older than two days | an extra line: the daily apt update has not run (orange) |
| no apt update since installation | an extra line asking for `apt update` (orange) |
| installed packages in use that no package source offers | an extra line naming them and `show: apt-cache policy <package>` (red, as they get no security updates) |
| packages left over without a source | `left over, without a source and not in use now:` and their names (orange) |
| packages apt no longer needs | `no longer needed, apt autoremove would remove them:`, their names, and the `apt remove` command for exactly those (orange) |
| config files of removed packages that can go | `config files of removed packages that can go:` and their names (orange) |
| config files that must stay | `config files of removed packages that must stay:`, each with the reason (no change of colour) |
| something can go | `remove what can go`, then the `apt purge` command for exactly those packages |
| check failed | `Package updates: CHECK FAILED` with apt's error, then the last successful result (orange); exit status 1 |

Below the title every section shows how old the lists are, when the check ran and how to run
it again. The whole section takes the colour of its most serious line: red before orange
before green.

Two days is the limit for old lists because `apt.systemd.daily` refreshes once per calendar
day and `apt-daily.timer` (6:00 and 18:00, up to 12 hours random delay) runs at least once
between 6:00 and 18:00 every day: with a working refresh at most about 42 hours pass between
two updates.

The apt hooks record when an apt update starts and when it reaches a repository. apt runs its
success hook as soon as at least one repository was fetched, also when another one fails
(measured with apt 3.0.4). So the check reports an apt update that reached no repository at
all, but not a single failing repository among working ones; `apt update` itself shows that.

The start hook also leaves a marker that the success hook removes, and the check reports an
apt update as unfinished while the marker is there. It does not compare the two times: when the
clock is set back during an apt update, for example by NTP at boot, the success time can lie
before the start time.

## pg-collation: PostgreSQL collation versions

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
psql session. The check makes it visible at login instead.

A database counts as affected when its stored collation version differs from the version
the running server reports, or, for the libc provider, from the glibc installed on disk.
The second catches a glibc update before PostgreSQL is restarted; the warning then asks for
a reboot or a PostgreSQL restart first.

| State | Section |
| --- | --- |
| everything fine | `PostgreSQL collation: OK` and the clusters that were checked, e.g. `clusters: port 5432, GitLab` (green) |
| mismatch | `PostgreSQL collation: VERSION MISMATCH` with the affected databases and the fix (orange) |
| glibc on disk newer than the running server | the same, with `(glibc on disk: 2.41)` behind the database and the advice to reboot or restart PostgreSQL first (orange) |
| no running cluster | `PostgreSQL collation: NOTHING CHECKED` (orange), so that an empty check never reads as OK |
| check failed | `PostgreSQL collation: CHECK FAILED`, the cluster (port or GitLab), then the last successful result (orange); exit status 1 |

Requirements: PostgreSQL 15 or newer from the Debian or PGDG packages, or bundled with the
GitLab Linux package; older versions do not track the collation version per database and are
skipped. Standby clusters are skipped; the reindex on the primary is replicated to them.
PostgreSQL running in containers is not covered.

GitLab's bundled PostgreSQL runs as the user `gitlab-psql` under `/var/opt/gitlab`, outside
`pg_lsclusters`; the check reaches it through `gitlab-psql`. It links against the system
glibc, so a Debian release upgrade affects it like any other cluster. The check includes it
when runit supervises it (`/opt/gitlab/service/postgresql`) and it is running; at boot it waits
up to 60 seconds for it to answer, because runit starts it only after
`gitlab-runsvdir.service`.

### Fixing a mismatch

When the warning appears, rebuild the indexes and reboot:

```bash
runuser -u postgres -- /usr/local/sbin/pg-collation-fix
reboot
```

While indexes are rebuilt, queries on the affected tables have to wait. On large
databases, stop the applications using them first.

If a database fails, the script continues with the others, keeps the old collation
version for the failed one and exits with status 1. The warning stays until that
database is fixed as well. The most likely cause is a duplicate key error: the changed
sort order has let duplicates into a unique index. Resolve the duplicates and run the
script again.

Right after a glibc upgrade, the running PostgreSQL server still uses the old glibc until
it is restarted. A reindex then would still sort the old way, so the warning asks for a
reboot first, or for a PostgreSQL restart (`systemctl restart postgresql`, which restarts all
clusters, or `gitlab-ctl restart postgresql` for GitLab) followed by `pg-collation-check`.
After a reboot the check runs by itself.

#### GitLab

For GitLab's bundled PostgreSQL the warning gives GitLab's own procedure ("Rebuild all
indexes" in GitLab's documentation on upgrading the operating system for PostgreSQL): stop
GitLab except its PostgreSQL, rebuild, start it again.

```bash
gitlab-ctl stop && gitlab-ctl start postgresql
/usr/local/sbin/pg-collation-fix --gitlab
gitlab-ctl start && pg-collation-check
```

`pg-collation-fix --gitlab` runs as root and works through `gitlab-psql`. It turns off the
statement timeout of one minute that GitLab sets, and it refuses to rebuild while other GitLab
services are still running.

## ssh-password: SSH password login

A server that accepts passwords over SSH can be attacked by guessing them, and on a public
address such attempts never stop. Debian's sshd accepts passwords unless told otherwise:
`/etc/ssh/sshd_config` leaves `PasswordAuthentication` commented out, so sshd's default `yes`
applies.

sshd reads its configuration when it starts, so the check asks two sources:

- **The running sshd.** The check connects to it on the local address it listens on
  (`127.0.0.1` or `::1` for a wildcard listener) and asks which authentication methods it
  offers, with the `none` request every SSH client sends first. Nothing logs in, no key or
  agent is used, and nothing is written to root's SSH files. sshd logs `Connection closed by
  authenticating user root 127.0.0.1 port ... [preauth]`.
- **The configuration on disk.** `sshd -T -C` gives the settings for the same connection (root
  from that address), and sshd's debug output (`sshd -T -ddd`) names the file and line each
  setting comes from.

Password login counts as on when sshd offers `password` or `keyboard-interactive`; with PAM,
keyboard-interactive asks for the account's password as well.

| State | Section |
| --- | --- |
| no password login | `SSH password login: OFF` and the methods sshd offers (green) |
| password login | `SSH password login: ON`, the methods, whether root may use a password (`PermitRootLogin`), where `PasswordAuthentication yes` or `KbdInteractiveAuthentication yes` comes from (a file and line, sshd's default, or a Match block), and how to allow keys only (orange) |
| password login, but the configuration on disk allows keys only | `ON` and the command that restarts sshd (orange) |
| keys only, but the configuration on disk allows passwords | `ON AFTER RESTART`: sshd uses it when it restarts, at the latest at the next boot (orange) |
| an account with an empty password got in | `ON` with that line (orange) |
| `sshd -T` fails or sshd does not answer | `SSH password login: CHECK FAILED` with the reason, then the last successful result (orange); exit status 1 |
| no SSH server installed | `SSH password login: NOTHING CHECKED` (orange) |

`Match` blocks change settings per user, group, address or host, and the check evaluates them
only for root from the local address. A block like `Match Address 10.0.0.0/8` with
`PasswordAuthentication yes` allows passwords from that network while the check sees keys only,
so every section lists the Match blocks sshd reads, also those in included files.

### Allowing keys only

First make sure that a key login works, in a second window that stays open. Then, on a
Debian server whose `/etc/ssh/sshd_config.d` holds no `10-key-only.conf` yet (the section
shows these lines itself when they would work):

```bash
printf '%s\n' 'PasswordAuthentication no' 'KbdInteractiveAuthentication no' > /etc/ssh/sshd_config.d/10-key-only.conf
```

```bash
sshd -t && systemctl restart ssh && ssh-password-check
```

Debian's `sshd_config` includes `/etc/ssh/sshd_config.d/*.conf` near its top (line 12 in
Debian 13), and sshd keeps the first value it reads. So this file wins over a
`PasswordAuthentication yes` further down in `sshd_config` and over a file that sorts after it,
such as `50-cloud-init.conf`. A value set before the `Include` line, or in a file that sorts
before it, still wins. The check works this out from sshd's debug output, which names every
file an `Include` reads, in the order sshd reads them, and the file and line of every setting.
It shows the command only when the file would decide; otherwise it says what to change: the
file itself when it exists already, the line sshd reads first, `/etc/ssh/sshd_config` when no
`Include` reads the file, or the Match block that sets the value.

Use `restart`, not `reload`: where sshd is socket-activated (`systemctl is-active ssh.socket`
says `active`), `systemctl reload ssh` ends sshd with "Cannot bind any address", and only the
next connection starts it again, through the socket (measured 2026-11-14, Debian 13, OpenSSH
10.0).

A server that should accept passwords: `login-warnings disable ssh-password`.

The check runs at boot, after dpkg and apt update and by hand; after a change to sshd's
configuration, run `ssh-password-check` (the command above ends with it). OpenSSH 9.8 and newer
refuse addresses for a while that keep failing to log in (`PerSourcePenalties`, from 15 seconds
of penalty on by default); five checks within 0.3 seconds were not refused (OpenSSH 10.0,
measured 2026-11-14).

## restart: programs that use replaced files

An update replaces a library on disk, but a program that is already running keeps using the old
one, with its bugs and security holes, until it is restarted. dpkg replaces a file by renaming
the new one over it, so the running program still maps the old file, and the kernel names it
`<path> (deleted)` in `/proc/<pid>/maps`. The maintainer scripts of many packages restart their
own services; what is left shows up here. Debian has two tools for this question, `needrestart`
and `checkrestart` (in `debian-goodies`); the check follows their method and needs neither.

It reads the executable mappings of every process, as `needrestart` does: a deleted log or
data file is not code and needs no restart. It leaves out what is deleted by design: SysV shared
memory, `memfd` (where dotnet keeps executable code), `/dev`, `/tmp`, `/run` and a few JIT
files. Each process is assigned by its cgroup:

| cgroup of the process | shown as |
| --- | --- |
| `/system.slice/.../<unit>.service`, or a cgroup below it | the service, with `systemctl try-restart` for exactly these |
| a service that should not be restarted on the fly | `restart with care, or reboot` |
| `/init.scope` (PID 1) | `systemd itself: systemctl daemon-reexec` |
| `/user.slice/user-<uid>.slice/...` | the user, who logs out and in again |
| `/qemu.slice/<vmid>.scope` (Proxmox VE: its `kvm` and `swtpm`) | the VM, which needs to be stopped and started |
| anything else | the program and its PID |

The services that should not be restarted on the fly are those that `needrestart` does not
restart by itself (`override_rc`: dbus, systemd-logind, networking, NetworkManager, getty,
docker, lxc, lxcfs, libvirt, display managers, oneshot jobs and others) and `checkrestart`'s
`dangerous-unit` list (dbus, systemd-logind, gdm, console-getty).

A process whose root directory is another file system than PID 1's and that is not part of a
system service runs in a container; the files in its maps are the container's. It is only
counted, and the login-warnings inside the container sees it. Neither the mount namespace nor
the root alone tells a container (measured on a Debian 13 container, 2026-11-25): services with
`ProtectSystem` or `PrivateTmp` have a mount namespace of their own but the same root, Docker
containers have a root of their own, and postfix's chrooted `pickup` has another root but runs
in `postfix.service`.

When systemd itself or one of the careful services is among them, the section says first that a
reboot covers all of this: that is usually the case after an update of a library systemd links,
such as libzstd, which then shows up in almost every process.

The section turns red when one of the replaced files came with a security update, and names the
packages: the package that owns the file's path now (`dpkg -S`, in both spellings on a merged
`/usr`, and as `<name>.so.*` for a library whose new version has another file name) has its
installed version from a security archive (`-security/` in `apt-cache policy`). The running
programs do not have that fix yet. A security update that is not installed at all is not counted
here; `apt-updates` names it.

`restart-check --details` lists every process with the replaced files it uses.

Not seen: scripts of interpreters (Python, Perl) whose modules changed, a file that is changed in
place instead of replaced, and whether the running kernel is older than the installed one. The
result is the state when the check last ran: after restarting something by hand, run
`restart-check`.

| State | Section |
| --- | --- |
| nothing uses a replaced file | `Restart needed: none` and how many processes were read (green) |
| something does | `Restart needed: 2 services, systemd, 1 user`, the lists and commands above (orange) |
| a replaced file came with a security update | the same, with `security updates that the running programs do not have yet:` and the packages (red) |
| only processes in containers do | `none`, with a line that counts them (green) |
| no process could be read | `Restart needed: CHECK FAILED`, then the last successful result (orange); exit status 1 |

## zvol-links: links of ZFS volumes

ZFS turns every volume (zvol) into a block device `/dev/zd<N>`, and udev gives it a link
`/dev/zvol/<pool>/<volume>` (`60-zvol.rules`, which names it with `zvol_id`). Proxmox VE opens a
VM disk on ZFS through that link. When udev fails on a zd device at boot, it logs
`zd640: Failed to process device, ignoring: Unknown error 512` and does not try again;
`zfs-volume-wait.service` only waits, and Proxmox VE starts its guests without waiting for it.
Proxmox VE then waits 300 seconds for the link and refuses to start the VM
(`no zvol device link for 'vm-114-disk-2' found after 300 sec`). Triggering udev again for that
device brings the link back, without a reboot. On one Proxmox VE 9 host the journal showed the
udev message in 3 of 99 boots, under kernels 6.14 and 7.0.

Which volumes should have a link follows `zvol_wait` (OpenZFS 2.4.4): not those with
`volmode=none`, nor `volmode=default` while the module's `zvol_volmode` is 3, nor redacted
volumes, volumes whose key is not loaded, or a partially received volume without a
`<name>/%recv` clone. A link counts when it leads to a block device, as Proxmox VE checks it.

### The repair at boot

`login-warnings-zvol-repair.service` runs `zvol-links-check --repair --trigger boot` after the
pools are imported (`zfs-import.target`) and before `pve-guests.service`. It waits until udev is
idle (`udevadm settle`), re-triggers udev (`udevadm trigger --action=add /dev/zd<N>`) for every
volume that has no link while its zd device exists, at most three times each, and checks again,
for at most 60 seconds. A volume without a zd device is waited for, not triggered: ZFS has not
created the device yet, so udev has nothing to process. What the repair did goes to the journal
(`journalctl -u login-warnings-zvol-repair`), to a record of this boot in `/run/login-warnings`,
and, when it re-triggered something or a link is still missing, to
`/var/lib/login-warnings/zvol-links-repair`, which later boots show as the last repair. A link
the repair cannot bring back is reported as missing, and the VM fails as before. The service
runs only while the check is switched on.

`zvol-links-check --repair --dry-run` says what the repair would do and changes nothing.
`zvol-links-check --repair` by hand repairs the same way but records nothing, so that the
section never calls it a repair at boot; run `zvol-links-check` afterwards.

| State | Section |
| --- | --- |
| every volume has its link | `Zvol links: OK`, how many volumes, and whether the repair ran in this boot (green) |
| the repair at boot re-triggered udev | `Zvol links: REPAIRED AT BOOT`, the volumes and their zd devices, when, and udev's message (orange) |
| a volume has no link | `Zvol links: MISSING`, the volumes with zd device and VM, then `udevadm trigger --action=add /dev/zd<N> && udevadm settle` and `qm start <vmid>` for exactly those (red) |
| udev failed on a partition of a zd device in this boot | an extra line naming it; Proxmox VE needs no partition links (orange) |
| an earlier boot needed a repair | `last repair in an earlier boot:`, the time and the volumes (no change of colour) |
| ZFS not loaded, or no volume that should have a link | `Zvol links: NOTHING CHECKED` (orange) |
| `zfs list` fails | `Zvol links: CHECK FAILED` with zfs's message, then the last successful result (orange); exit status 1 |

The section shows the state when the check last ran: at boot after the repair, after dpkg and apt
update, and by hand. After bringing a link back by hand, run `zvol-links-check`.

## Requirements

- Debian or a derivative with systemd, dpkg and apt
- `wget` or `curl` (on a minimal installation: `apt install wget`)
- for `pg-collation`: PostgreSQL installed locally, from the Debian or PGDG packages or bundled
  with the GitLab Linux package (see above)
- for `ssh-password`: the OpenSSH server (`openssh-server`, which brings the `ssh` client the
  check uses)
- for `zvol-links`: OpenZFS (`zfsutils-linux`, which brings the `zvol_id` the check uses)

## Installation

Every version is published as a GitHub release with an archive `login-warnings.tar.gz` that
holds only what a server needs. All commands are run as root.

```bash
wget -qO- https://github.com/MarcFauser/login-warnings/releases/latest/download/login-warnings.tar.gz | tar -xz -C /usr/local/src
```

```bash
bash /usr/local/src/login-warnings/install.sh
```

The installer copies the files into place, switches on the checks that fit, and prints the
installed version, the checks and their results.

## Update

```bash
login-warnings update
```

It downloads the latest release, shows the CHANGELOG sections since the installed version,
puts the release in place of `/usr/local/src/login-warnings` and runs its `install.sh`. If the
installed version is the latest one, or newer, it changes nothing.

You see at login when an update is due. After every apt update and when run by hand,
`login-warnings` asks GitHub which release is the latest (it reads the redirect of
`/releases/latest`, downloads nothing) and keeps the answer in
`/var/lib/login-warnings/latest-release`. The frame then names the installed version at the
top, a newer release in an orange section, and at the bottom when the latest release was last
checked:

```
----- login-warnings v3.3.0 --------------------------------------------
...

login-warnings: v3.4.0 available
  installed: v3.3.0
  update: login-warnings update

----- latest release checked 2026-11-12 23:06:35 +01:00 ----------------
```

A login itself never goes online. If GitHub cannot be reached, the old answer stays and the
date at the bottom shows its age.

Servers installed before 3.2.0 have no `update` yet: remove the old source folders once
(`/usr/local/src/login-warnings`, `/usr/local/src/login-warnings-main`, and from the time the
repository was called `pg-collation-check`, `/usr/local/src/pg-collation-check` or
`/usr/local/src/pg-collation-check-main`) and run the two lines of the installation.
`install.sh` removes what 1.x and 2.x installed under other names.

To see which version is installed:

```bash
login-warnings --version
```

## Uninstall

```bash
systemctl disable --now login-warnings.service login-warnings-zvol-repair.service
rm -f /etc/systemd/system/login-warnings.service /etc/systemd/system/login-warnings-zvol-repair.service \
      /etc/dpkg/dpkg.cfg.d/login-warnings /etc/apt/apt.conf.d/80login-warnings \
      /etc/profile.d/login-warnings.sh /usr/local/sbin/login-warnings \
      /usr/local/sbin/apt-updates-check /usr/local/sbin/ssh-password-check \
      /usr/local/sbin/restart-check /usr/local/sbin/zvol-links-check \
      /usr/local/sbin/pg-collation-check /usr/local/sbin/pg-collation-fix
rm -rf /etc/login-warnings.d /run/login-warnings /var/lib/login-warnings /usr/local/src/login-warnings
systemctl daemon-reload
```

Removing `/etc/apt/apt.conf.d/80login-warnings` also stops the daily refresh of the package
lists.

## Adding a check

A check is a command `/usr/local/sbin/<check>-check` that accepts `--quiet` and
`--trigger boot|dpkg|apt|manual`, writes its result to `/run/login-warnings/<check>` and keeps
any helper files as `/run/login-warnings/.<check>.*`. The result is one section: a title line
`<Title>: <STATE>`, the details indented by two spaces, every line below 80 columns, one colour
for the whole section, and always the time of the check. `login-warnings enable <check>`
registers it.

## Development

All files except the Windows launchers (`*.cmd`) must keep LF line endings. Git does not
convert line endings in this repository (`* -text` in `.gitattributes`), so a file saved with
CRLF on Windows would be committed that way: a script fails on the server with
`/bin/bash^M: bad interpreter`, and in the systemd unit or the dpkg hook line the CR becomes
part of the command.

On the machine you commit from, activate the guard once after cloning: double-click
`install-git-hooks.cmd` on Windows, or run `pwsh ./install-git-hooks.ps1`. It copies
`_git_hooks/pre-commit` into `.git/hooks`, which git does not version. The hook refuses a
commit that contains a file with CRLF line endings (except `*.cmd`), and one without a new
version section in `CHANGELOG.md` and a matching `VERSION` in `login-warnings`. None of these
files is needed on the servers.

Releases are made by `.github/workflows/release.yml` on every push to `main`: if the newest
version in `CHANGELOG.md` has no release yet, it tags the pushed commit `v<version>`, builds
`login-warnings.tar.gz` with `git archive` (the files marked `export-ignore` in
`.gitattributes` stay out) and uses the version's CHANGELOG section as the release notes.

## License

[MIT](LICENSE)
