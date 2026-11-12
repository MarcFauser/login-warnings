#!/bin/sh
# /etc/profile.d/login-warnings.sh - sourced by /etc/profile in login shells.
#
# Shows the results of all enabled login warning checks in interactive shells, so they appear
# in every terminal window, including further windows on the same SSH connection (the login
# message itself is shown only once per connection). Each result names the time of its check;
# a registered check without a result is reported too, because an empty display would look
# exactly like an all-clear (login-warnings show).
#
# Non-interactive shells print nothing, so scripts and file transfers are not disturbed.

case $- in
    *i*) ;;
    *) return 0 ;;
esac

if [ -x /usr/local/sbin/login-warnings ]
then
    /usr/local/sbin/login-warnings show
fi
