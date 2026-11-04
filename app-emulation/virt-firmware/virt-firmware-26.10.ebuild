# Copyright 2024-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

# Based on ::gentoo's 26.9 ebuild, bumped to 26.10; python3_15 added.
# 26.10's kernel-bootcfg-boot-successful.service now runs
# /usr/libexec/uki-boot-successful (new upstream wrapper preferring the rust
# mini-bootcfg), so that script is installed too; no dependency change.
# Drop this copy once ::gentoo has 26.10 with python3_15.
# BENTOO-DIVERGENCE: KEYWORDS - overlay baseline (~amd64 only) for a version ::gentoo does not carry.
# BENTOO-DIVERGENCE: IUSE - python3_15 added to PYTHON_COMPAT.
# BENTOO-DIVERGENCE: REQUIRED_USE - python3_15 added to PYTHON_COMPAT.
# BENTOO-DIVERGENCE: DEPEND - python3_15 added to PYTHON_COMPAT.
# BENTOO-DIVERGENCE: RDEPEND - python3_15 added to PYTHON_COMPAT.
# BENTOO-DIVERGENCE: BDEPEND - python3_15 added to PYTHON_COMPAT.
PYTHON_COMPAT=( python3_{11..15} )
DISTUTILS_USE_PEP517=setuptools

inherit distutils-r1 optfeature pypi systemd

DESCRIPTION="Tools for ovmf/armvirt firmware volumes"
HOMEPAGE="
	https://gitlab.com/kraxel/virt-firmware
	https://pypi.org/project/virt-firmware/
"

LICENSE="GPL-2"
SLOT="0"
KEYWORDS="~amd64"

RDEPEND="
	dev-python/cryptography[${PYTHON_USEDEP}]
	dev-python/pefile[${PYTHON_USEDEP}]
	dev-python/pyyaml[${PYTHON_USEDEP}]
	dev-python/requests[${PYTHON_USEDEP}]
"

# Need systemd-detect-virt
BDEPEND="
	test? (
		sys-apps/systemd
	)
"

distutils_enable_tests unittest

python_prepare_all() {
	# Requires crypt module removed in py3.13
	rm virt/qemutest/cloudinit.py || die
	sed -e '/from virt.qemutest.cloudinit import CloudInitISO/d' \
		-i tests/tests.py || die

	distutils-r1_python_prepare_all
}

python_test() {
	eunittest tests
}

python_install_all() {
	distutils-r1_python_install_all

	doman man/*.1

	doinitd "${FILESDIR}/kernel-bootcfg-boot-successful"
	systemd_dounit systemd/kernel-bootcfg-boot-successful.service
	# ExecStart= of the unit since 26.10; /bin/sh also exists on split-usr
	sed -i -e '1s:^#!/usr/bin/sh:#!/bin/sh:' systemd/uki-boot-successful || die
	exeinto /usr/libexec
	doexe systemd/uki-boot-successful

	# Use our own provided by sys-kernel/installkernel[efistub,systemd]
	#exeinto /usr/lib/kernel/install.d
	#doexe systemd/99-uki-uefi-setup.install
}

pkg_postinst() {
	optfeature "automatically updating UEFI configuration on each kernel installation or removal" \
		"sys-kernel/installkernel[systemd,efistub]"
}
