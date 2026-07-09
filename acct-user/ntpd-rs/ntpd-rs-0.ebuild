# Copyright 1999-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

inherit acct-user

DESCRIPTION="User for the ntpd-rs NTP daemon"

SLOT="0"
KEYWORDS="~amd64 ~arm64"

ACCT_USER_ID=466
ACCT_USER_GROUPS=( ntpd-rs )
ACCT_USER_HOME=/dev/null
ACCT_USER_SHELL=/sbin/nologin

acct-user_add_deps
