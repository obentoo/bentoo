# Copyright 1999-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

inherit acct-user

DESCRIPTION="User for the lemonade local LLM server"

SLOT="0"
KEYWORDS="~amd64 ~arm64"

# No reserved UID in the Gentoo GID/UID assignment table for lemonade,
# so let the system pick the next free one.
ACCT_USER_ID=-1
ACCT_USER_GROUPS=( lemonade )
ACCT_USER_HOME=/var/lib/lemonade
ACCT_USER_HOME_PERMS=0750
ACCT_USER_SHELL=/sbin/nologin

acct-user_add_deps
