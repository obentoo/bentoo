# Copyright 1999-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

inherit check-reqs systemd tmpfiles

DESCRIPTION="Get up and running with large language models locally"
HOMEPAGE="https://ollama.com/"

# GitHub releases provide pre-built binaries for multiple architectures
SRC_URI="
	amd64? (
		!rocm? ( https://github.com/ollama/ollama/releases/download/v${PV}/ollama-linux-amd64.tgz -> ${P}-amd64.tgz )
		rocm? ( https://github.com/ollama/ollama/releases/download/v${PV}/ollama-linux-amd64-rocm.tgz -> ${P}-rocm.tgz )
	)
	arm64? ( https://github.com/ollama/ollama/releases/download/v${PV}/ollama-linux-arm64.tgz -> ${P}-arm64.tgz )
"

LICENSE="MIT"
SLOT="0"
KEYWORDS="~amd64 ~arm64"
IUSE="cuda rocm systemd"

# ROCm is only available on amd64
REQUIRED_USE="
	rocm? ( amd64 )
	cuda? ( amd64 )
"

# Binary redistribution is permitted under MIT license
# Strip is restricted because these are pre-built binaries
RESTRICT="mirror strip"

# Temporary directory for extraction
S="${WORKDIR}"

# Disk space check - Ollama models can be large
CHECKREQS_DISK_BUILD="4G"

# All files are pre-built binaries, skip QA checks
QA_PREBUILT="*"

# Runtime dependencies only - these are pre-built binaries
RDEPEND="
	acct-group/ollama
	acct-user/ollama
	cuda? ( dev-util/nvidia-cuda-toolkit )
	rocm? (
		dev-libs/rocm-opencl-runtime
		sci-libs/clblast
	)
"

DEPEND=""
BDEPEND="systemd? ( sys-apps/systemd )"

pkg_pretend() {
	check-reqs_pkg_pretend

	if use rocm; then
		ewarn ""
		ewarn "ROCm (AMD GPU) support is experimental and may not work on all hardware."
		ewarn "Supported AMD GPUs: Radeon RX 6000 series and newer, or Radeon VII."
		ewarn ""
		ewarn "If you encounter issues, please refer to:"
		ewarn "  https://rocm.docs.amd.com/projects/install-on-linux/en/latest/"
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
			unpack "${P}-rocm.tgz"
		else
			unpack "${P}-amd64.tgz"
		fi
	elif use arm64; then
		unpack "${P}-arm64.tgz"
	fi
}

src_prepare() {
	default
}

src_install() {
	# Install the main binary
	exeinto /opt/ollama/bin
	doexe bin/ollama

	# Install bundled libraries
	insinto /opt/ollama/lib
	doins -r lib/*

	# Create convenience symlink in standard PATH
	dosym -r /opt/ollama/bin/ollama /usr/bin/ollama

	# Install systemd service file
	if use systemd; then
		systemd_dounit "${FILESDIR}"/ollama.service
		dotmpfiles "${FILESDIR}"/ollama.conf
	fi

	# Install OpenRC init script
	newinitd "${FILESDIR}"/ollama.initd ollama
	newconfd "${FILESDIR}"/ollama.confd ollama

	# Create state directory for models and configuration
	keepdir /var/lib/ollama
	fowners ollama:ollama /var/lib/ollama
	fperms 0750 /var/lib/ollama

	# Create log directory
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
	elog "Ollama has been installed successfully!"
	elog ""
	elog "Quick Start Guide:"
	elog "=================="
	elog ""
	elog "1. Start the Ollama service:"

	if use systemd; then
		elog "   systemctl enable --now ollama"
	else
		elog "   rc-service ollama start"
		elog "   rc-update add ollama default"
	fi

	elog ""
	elog "2. Download and run a model:"
	elog "   ollama run llama3.2:3b"
	elog ""
	elog "3. Browse the model library:"
	elog "   https://ollama.com/library"
	elog ""

	if use cuda; then
		elog "NVIDIA CUDA Support:"
		elog "  - Ollama will automatically use NVIDIA GPUs"
		elog "  - Set CUDA_VISIBLE_DEVICES to control GPU selection"
		elog ""
	fi

	if use rocm; then
		elog "AMD ROCm Support:"
		elog "  - Set HSA_OVERRIDE_GFX_VERSION if needed for your GPU"
		elog "  - Example: HSA_OVERRIDE_GFX_VERSION=10.3.0 for Radeon RX 6000"
		elog ""
	fi

	elog "Privacy:"
	elog "  - Set OLLAMA_NO_CLOUD=1 to disable cloud models"
	elog ""
	elog "Configuration:"
	elog "  - Models: /var/lib/ollama"
	elog "  - Logs: /var/log/ollama"
	elog "  - API: http://localhost:11434"
	elog ""

	if [[ -z "${REPLACING_VERSIONS}" ]]; then
		elog "Add your user to the ollama group:"
		elog "  usermod -aG ollama YOUR_USERNAME"
		elog ""
	fi
}

pkg_postrm() {
	elog ""
	elog "Ollama has been removed."
	elog "Models and configuration in /var/lib/ollama were preserved."
	elog "To completely remove: rm -rf /var/lib/ollama"
	elog ""
}
