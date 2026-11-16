# Copyright 1999-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

inherit systemd unpacker

# Upstream names the package, its doc directory and the CLI "jotta-cli"; only
# the Portage package carries the -bin suffix.
MY_PN="${PN%-bin}"

DESCRIPTION="Jottacloud command-line client and its jottad backup/sync daemon"
HOMEPAGE="
	https://www.jottacloud.com/
	https://docs.jottacloud.com/en/articles/1436855-jottacloud-cli-for-linux-debian-packages
"
# Upstream's APT repository (suite "debian", component "main"), the one its
# Debian install guide points at. The pool filename is already versioned, but
# it is renamed anyway so the distfile carries the Portage package name.
SRC_URI="
	https://repo.jotta.cloud/debian/pool/main/j/${MY_PN}/${MY_PN}_${PV}_amd64.deb
		-> ${P}-amd64.deb
"
S="${WORKDIR}"

# Jotta's own code. The two upstream statements disagree: the .deb's
# usr/share/doc/jotta-cli/copyright says "3-Clause BSD" for every file, but
# that file is visibly templated from Keybase's packaging (its only other
# stanza credits run_jottad to "2015, Keybase") and carries no license text,
# no source is published anywhere, and the AUR PKGBUILD maintained by the
# "Jottacloud Packaging Team" itself declares license=('custom: Copyright
# Jotta AS'). The restrictive reading is taken until Jotta publishes terms
# that say otherwise.
LICENSE="all-rights-reserved"
# usr/bin/run_jottad: the one file credited to Keybase, whose original
# run_keybase is BSD-3.
LICENSE+=" BSD"
# Both ELF files are static Go (CGO_ENABLED=0), so every module they were
# built from is linked in. Read with `go version -m` on the 0.17.176206
# binaries (87 module paths, replacements included) and resolved per
# repository: Apache-2.0 (cobra, prometheus, grpc, genproto, go-systemd,
# go-ini, go-units, panicparse), BSD (Go runtime, golang.org/x/*, protobuf,
# modernc.org/sqlite+libc, pflag, fsnotify, uuid, ...), BSD-2
# (gorilla/websocket, pkg/errors, pkg/browser, blackfriday), ISC (go-spew,
# gopass, thumbhash), MIT (the rest: charmbracelet, sentry-go, bbolt,
# lumberjack, testify, ...). gopkg.in/yaml.v3 is MIT AND Apache-2.0, both
# already listed. The git.jotta.us/* modules are Jotta's own and fall under
# the first line.
LICENSE+=" Apache-2.0 BSD-2 ISC MIT"
SLOT="0"
KEYWORDS="-* ~amd64"
IUSE="systemd"

# bindist/mirror: all-rights-reserved grants no redistribution right, so
# neither a binary package nor a mirror copy may be made. strip: upstream
# already linked with -s -w, and a Go binary we cannot rebuild must not be
# rewritten by portage.
RESTRICT="bindist mirror strip"

# The .deb's data member is data.tar.zst. unpacker.eclass decompresses it, but
# only derives BDEPEND from the SRC_URI suffix (.deb), so zstd is named here.
BDEPEND="app-arch/zstd"

# No shared libraries: both ELF files have no dynamic section at all (readelf
# -d), GOOS=linux GOARCH=amd64 GOAMD64=v1, so nothing glibc- or musl-specific
# is needed either.
#
# app-misc/ca-certificates: a pure-Go TLS stack reads the platform trust
# store (/etc/ssl/certs) and every request goes to Jottacloud over HTTPS.
# sys-process/psmisc: run_jottad stops a running daemon with `killall jottad`
# and, without it, would start a second one over the same data directory.
RDEPEND="
	app-misc/ca-certificates
	sys-process/psmisc
"

QA_PREBUILT="
	usr/bin/jotta-cli
	usr/bin/jottad
"

src_unpack() {
	unpacker_src_unpack
}

src_prepare() {
	default

	# Portage compresses docs itself; a pre-gzipped one would be compressed
	# twice.
	gunzip usr/share/doc/${MY_PN}/changelog.gz || die
}

src_install() {
	# The payload installs only into /usr/bin, so it goes where the .deb puts
	# it rather than under /opt.
	#
	# migrate_jottad_settings is shipped too, as upstream does: it moves a
	# pre-0.11 system-slice data dir (/var/lib/jottad) to ~/.jottad, which a
	# host migrated from Debian may still carry. It calls `systemctl --user`
	# and `sudo` unconditionally.
	dobin usr/bin/{jotta-cli,jottad,run_jottad,migrate_jottad_settings}

	dodoc usr/share/doc/${MY_PN}/{changelog,copyright}

	# User scope only: upstream runs jottad per user, never system-wide (the
	# system-slice layout was retired in 0.11). The OpenRC script is
	# installed UNCONDITIONALLY -- it costs a systemd user nothing, and it is
	# the only way to run the daemon on a host without systemd. newinitd has
	# no user-scope variant, so it goes in as a plain executable, following
	# sys-apps/xdg-desktop-portal and sci-ml/lemonade-bin.
	exeinto /etc/user/init.d
	newexe "${FILESDIR}"/jottad-user.initd jottad

	# The unit is installed explicitly rather than by copying the .deb's
	# usr/lib tree, so the install is visible in the ebuild text
	# (scripts/check-openrc-coverage.sh reads nothing else).
	if use systemd; then
		systemd_douserunit usr/lib/systemd/user/jottad.service
	fi
}

pkg_postinst() {
	elog "jottad runs once per user, in that user's session, with its data in"
	elog "~/.jottad. Enable it for each user that should run it:"
	elog
	elog "  OpenRC:  rc-update --user add jottad default"
	elog "           rc-service --user jottad start"
	elog "  systemd: run_jottad   (enables and restarts jottad.service)"
	elog
	elog "run_jottad is upstream's helper and assumes systemd. On OpenRC use the"
	elog "commands above instead: JOTTAD_SYSTEMD=0 run_jottad only backgrounds an"
	elog "unsupervised jottad."
	elog
	elog "A user service starts with that user's session, not at boot. Under"
	elog "systemd, 'loginctl enable-linger <user>' keeps one running from boot."
	elog
	elog "Then log in with: jotta-cli login"
}
