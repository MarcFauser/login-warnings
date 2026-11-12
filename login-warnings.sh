#!/bin/sh
# /etc/profile.d/login-warnings.sh - sourced by /etc/profile in login shells.
#
# Prints every non-empty file in /run/login-warnings in interactive shells, so a warning
# appears in every terminal window, including further windows on the same SSH connection
# (the login message itself is shown only once per connection). Checks such as
# pg-collation-check write their warning there and remove it once everything is fine.
# Non-interactive shells print nothing, so scripts and file transfers are not disturbed.

case $- in
    *i*) ;;
    *) return 0 ;;
esac

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
