# Copyright 2024-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

inherit acct-user

DESCRIPTION="A user for ollama"
ACCT_USER_ID=-1
ACCT_USER_HOME=/var/lib/ollama
ACCT_USER_HOME_PERMS=0750
ACCT_USER_GROUPS=( ollama )

KEYWORDS="~amd64 ~arm64"

IUSE="cuda"

acct-user_add_deps

RDEPEND+="
	cuda? (
		acct-group/video
	)
"

pkg_setup() {
	# sci-ml/ollama[cuda] needs the ollama user in the video group for GPU access
	if use cuda; then
		ACCT_USER_GROUPS+=( video )
	fi
}
