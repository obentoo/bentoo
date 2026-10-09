# Copyright 1999-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

inherit check-reqs systemd tmpfiles

DESCRIPTION="Get up and running with large language models locally"
HOMEPAGE="https://ollama.com/"

MY_PV="${PV/_rc/-rc}"
MY_P="${PN}-${MY_PV}"

SRC_URI="
	amd64? (
		!rocm? ( https://github.com/ollama/ollama/releases/download/v${MY_PV}/ollama-linux-amd64.tar.zst -> ${MY_P}-amd64.tar.zst )
		rocm? ( https://github.com/ollama/ollama/releases/download/v${MY_PV}/ollama-linux-amd64-rocm.tar.zst -> ${MY_P}-rocm.tar.zst )
	)
	arm64? ( https://github.com/ollama/ollama/releases/download/v${MY_PV}/ollama-linux-arm64.tar.zst -> ${MY_P}-arm64.tar.zst )
"

LICENSE="MIT"
SLOT="0"
KEYWORDS="~amd64 ~arm64"
IUSE="cuda rocm systemd"

REQUIRED_USE="
	rocm? ( amd64 )
	cuda? ( amd64 )
"

RESTRICT="mirror strip"

S="${WORKDIR}"

CHECKREQS_DISK_BUILD="4G"

QA_PREBUILT="*"

# The ONLY half of the blocker against sci-ml/ollama, and it has to stay that
# way. Both provide /usr/bin/ollama, /etc/init.d/ollama, /etc/conf.d/ollama and
# the systemd unit -- same program, two ways of getting it.
#
# This used to read "the other half of the pair", following
# sci-libs/onnxruntime{,-bin} and sci-ml/lemonade{,-bin}, but the symmetry was
# never real: neither this overlay's sci-ml/ollama nor ::gentoo's ever declared
# the reverse atom. Since 2026-09-22 the source ebuild is gone from here for
# good (fourth removal -- see .autoupdate/packages.toml), so the package this
# blocks is sci-ml/ollama::gentoo, which cannot be made to block back. A "!!"
# in one direction is enough to keep both off the same system; do not read the
# missing counterpart as an omission to fix.
#
# acct-user/ollama is unversioned on purpose. It used to read
# >=acct-user/ollama-3, pointing at an override this overlay carried until
# 5cacee117 dropped it in favour of ::gentoo's. ::gentoo ships
# acct-user/ollama-0, so that atom became unsatisfiable the moment the override
# left -- "there are no ebuilds to satisfy >=acct-user/ollama-3[cuda?]" -- and
# this package has been uninstallable since. ::gentoo's version carries the
# same IUSE=cuda and the same video-group handling, so nothing is lost by
# depending on it unversioned.
#
# Keep these notes ABOVE the assignment. RDEPEND is a dependency spec, not
# bash: a '#' inside the string is parsed as an atom and invalidates the
# package's metadata for everyone who syncs. sci-ml/stable-diffusion-cpp spent
# twenty days masked that way, from the same mistake in REQUIRED_USE.
RDEPEND="
	!!sci-ml/ollama
	acct-group/ollama
	acct-user/ollama[cuda?]
	amd64? (
		cuda? ( dev-util/nvidia-cuda-toolkit )
		rocm? (
			dev-libs/rocm-opencl-runtime
			sci-libs/clblast
		)
	)
"

BDEPEND="systemd? ( sys-apps/systemd )"

pkg_pretend() {
	check-reqs_pkg_pretend

	if use rocm; then
		ewarn ""
		ewarn "ROCm (AMD GPU) support is experimental and may not work on all hardware."
		ewarn "Supported AMD GPUs: Radeon RX 6000 series and newer, or Radeon VII."
		ewarn ""
	fi

	if use cuda; then
		ewarn ""
		ewarn "CUDA (NVIDIA GPU) support requires compatible NVIDIA drivers."
		ewarn "Minimum compute capability: 6.0 (Pascal architecture and newer)."
		ewarn ""
	fi
}

pkg_setup() {
	check-reqs_pkg_setup
}

src_unpack() {
	if use amd64; then
		if use rocm; then
			unpack "${MY_P}-rocm.tar.zst"
		else
			unpack "${MY_P}-amd64.tar.zst"
		fi
	elif use arm64; then
		unpack "${MY_P}-arm64.tar.zst"
	fi
}

src_prepare() {
	default
}

src_install() {
	exeinto /opt/ollama/bin
	doexe bin/ollama

	insinto /opt/ollama/lib
	insopts -m0755
	doins -r lib/*
insopts -m0644

	dosym -r /opt/ollama/bin/ollama /usr/bin/ollama

	if use systemd; then
		systemd_dounit "${FILESDIR}"/ollama.service
		dotmpfiles "${FILESDIR}"/ollama.conf
	fi

	newinitd "${FILESDIR}"/ollama.initd ollama
	newconfd "${FILESDIR}"/ollama.confd ollama

	keepdir /var/lib/ollama
	fowners ollama:ollama /var/lib/ollama
	fperms 0750 /var/lib/ollama

	keepdir /var/log/ollama
	fowners ollama:ollama /var/log/ollama
	fperms 0750 /var/log/ollama
}

pkg_preinst() {
	if [[ -d "${EROOT}"/var/lib/ollama ]]; then
		einfo "Preserving existing Ollama data in /var/lib/ollama"
	fi
}

pkg_postinst() {
	if use systemd; then
		tmpfiles_process ollama.conf
	fi

	elog ""
	elog "Quick Start:"
	elog ""

	if use systemd; then
		elog "  systemctl enable --now ollama"
	else
		elog "  rc-service ollama start"
		elog "  rc-update add ollama default"
	fi

	elog ""
	elog "  ollama run llama3.2:3b"
	elog "  https://ollama.com/library"
	elog ""

	if use cuda; then
		elog "CUDA: Ollama will automatically use NVIDIA GPUs."
		elog ""
	fi

	if use rocm; then
		elog "ROCm: Set HSA_OVERRIDE_GFX_VERSION if needed for your GPU."
		elog ""
	fi

	if [[ -z "${REPLACING_VERSIONS}" ]]; then
		elog "Add your user to the ollama group:"
		elog "  usermod -aG ollama YOUR_USERNAME"
		elog ""
	fi
}

pkg_postrm() {
	elog "Models in /var/lib/ollama were preserved."
	elog "To completely remove: rm -rf /var/lib/ollama"
}
