#!/bin/sh
# /etc/profile.d/login-warnings.sh - sourced by /etc/profile in login shells.
#
# Prints every file in /run/login-warnings in interactive shells, so the result of each check
# appears in every terminal window, including further windows on the same SSH connection (the
# login message itself is shown only once per connection). Each check writes its own file:
# an OK line or a warning, both with the time of the check.
#
# Every check is registered in /etc/login-warnings.d/<name> (one line: the command to run it
# by hand). A registered check without a result file has not run since boot; that is reported
# too, because an empty display would look exactly like an all-clear.
#
# Non-interactive shells print nothing, so scripts and file transfers are not disturbed.

case $- in
    *i*) ;;
    *) return 0 ;;
esac

for _login_warning in /etc/login-warnings.d/*
do
    case $_login_warning in
        *.tmp) continue ;;
    esac
    if [ -f "$_login_warning" ] && [ ! -e "/run/login-warnings/${_login_warning##*/}" ]
    then
        printf '\033[38;5;208m%s: no result since boot (%s). Run: %s\033[0m\n' \
            "${_login_warning##*/}" \
            "$(date -d "@$(awk '/^btime/ { print $2 }' /proc/stat)" '+%Y-%m-%d %H:%M:%S %:z' 2>/dev/null)" \
            "$(head -n 1 "$_login_warning")"
    fi
done

for _login_warning in /run/login-warnings/*
do
    case $_login_warning in
        *.tmp.*) continue ;;
    esac
    if [ -f "$_login_warning" ] && [ -s "$_login_warning" ]
    then
        cat "$_login_warning"
    fi
done
unset _login_warning
