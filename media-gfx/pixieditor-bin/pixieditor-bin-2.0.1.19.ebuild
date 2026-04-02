# Copyright 2024-2025 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

inherit desktop unpacker xdg

MY_PN="${PN%-bin}"
MY_P="${MY_PN}-${PV}"

DESCRIPTION="All-in-one solution for 2D image editing with pixel art focus (binary package)"
HOMEPAGE="https://pixieditor.net"
SRC_URI="https://github.com/PixiEditor/PixiEditor/releases/download/${PV}/PixiEditor-${PV}-amd64-linux.deb"

LICENSE="LGPL-3"
SLOT="0"
KEYWORDS="~amd64"
IUSE="vulkan opengl"

# Dependencies baseadas EXATAMENTE no arquivo control
RDEPEND="
	x11-libs/libX11
	x11-libs/libICE
	x11-libs/libSM
	media-libs/fontconfig
	dev-libs/icu
"

BDEPEND="
	app-arch/zstd
"

RESTRICT="mirror strip"

S="${WORKDIR}"

src_unpack() {
	unpack_deb ${A}
}

src_prepare() {
	default
	
	# Verificar se as bibliotecas principais existem
	local lib_dir="usr/lib/pixieditor"
	
	if [[ ! -f "${lib_dir}/PixiEditor" ]]; then
		die "Main executable PixiEditor not found in package"
	fi
	
	if [[ ! -f "${lib_dir}/libSkiaSharp.so" ]]; then
		die "Required native library libSkiaSharp.so not found"
	fi
	
	# Verificar se é realmente amd64
	local exe_arch=$(file "${lib_dir}/PixiEditor" | grep -o "x86-64\|ELF 64-bit")
	if [[ -z "${exe_arch}" ]]; then
		die "Executable is not 64-bit ELF"
	fi
}

src_install() {
	# Instalar tudo em /opt/pixieditor preservando estrutura
	insinto /opt/pixieditor
	doins -r usr/lib/pixieditor/*
	
	# Tornar executável principal executável
	fperms +x /opt/pixieditor/PixiEditor
	
	# Tornar bibliotecas nativas executáveis
	local native_libs=(
		libHarfBuzzSharp.so
		libSkiaSharp.so
		libSystem.Globalization.Native.so
		libSystem.IO.Compression.Native.so
		libSystem.Native.so
		libSystem.Net.Security.Native.so
		libSystem.Security.Cryptography.Native.OpenSsl.so
		libclrgc.so
		libclrjit.so
		libcoreclr.so
		libcoreclrtraceptprovider.so
		libhostfxr.so
		libhostpolicy.so
		libmscordaccore.so
		libmscordbi.so
		libwasmtime.so
	)
	
	for lib in "${native_libs[@]}"; do
		if [[ -f "${ED}/opt/pixieditor/${lib}" ]]; then
			fperms +x "/opt/pixieditor/${lib}"
		fi
	done
	
	# Tornar tools executáveis se existirem
	if [[ -f "${ED}/opt/pixieditor/createdump" ]]; then
		fperms +x /opt/pixieditor/createdump
	fi
	
	if [[ -f "${ED}/opt/pixieditor/PixiEditor.UpdateInstaller" ]]; then
		fperms +x /opt/pixieditor/PixiEditor.UpdateInstaller
	fi
	
	if [[ -f "${ED}/opt/pixieditor/ThirdParty/Linux/ffmpeg/ffmpeg" ]]; then
		fperms +x /opt/pixieditor/ThirdParty/Linux/ffmpeg/ffmpeg
	fi
	
	# Criar wrapper script simples
	cat > "${T}/${MY_PN}" << 'EOF'
#!/bin/bash
# PixiEditor wrapper script for Gentoo

# Set library path to prioritize bundled libraries
export LD_LIBRARY_PATH="/opt/pixieditor:${LD_LIBRARY_PATH}"

# Performance optimizations
export DOTNET_TieredCompilation=1
export DOTNET_ReadyToRun=1
export DOTNET_gcServer=1
export DOTNET_gcConcurrent=1

# Execute PixiEditor from its directory
cd /opt/pixieditor || exit 1
exec ./PixiEditor "$@"
EOF
	
	exeinto /usr/bin
	doexe "${T}/${MY_PN}"
	
	# Desktop integration
	domenu usr/share/applications/PixiEditor.desktop
	
	# Icons - seguir estrutura do pacote
	local icon_sizes=(16 32 128 256 512)
	for size in "${icon_sizes[@]}"; do
		if [[ -f "usr/share/icons/hicolor/${size}x${size}/apps/pixieditor.png" ]]; then
			newicon -s ${size} "usr/share/icons/hicolor/${size}x${size}/apps/pixieditor.png" pixieditor.png
		fi
	done
	
	# SVG icon
	if [[ -f "usr/share/icons/hicolor/scalable/apps/pixieditor.svg" ]]; then
		newicon -s scalable usr/share/icons/hicolor/scalable/apps/pixieditor.svg pixieditor.svg
	fi
	
	# Documentation
	if [[ -f usr/lib/pixieditor/LICENSE ]]; then
		dodoc usr/lib/pixieditor/LICENSE
	fi
	
	if [[ -d "usr/lib/pixieditor/Third Party Licenses" ]]; then
		insinto /usr/share/doc/${PF}
		doins -r "usr/lib/pixieditor/Third Party Licenses"
	fi
}

pkg_postinst() {
	xdg_pkg_postinst
	
	elog "PixiEditor has been installed to /opt/pixieditor"
	elog "Launch with: ${MY_PN}"
	elog ""
	elog "This is a self-contained .NET application that includes"
	elog "all required .NET runtime components."
	elog ""
	
	if use vulkan; then
		elog "Vulkan support requested. Install:"
		elog "  emerge media-libs/vulkan-loader"
		elog "Test with: vulkaninfo"
	fi
	
	if use opengl; then
		elog "OpenGL support requested. Ensure graphics drivers are installed."
		elog "Test with: glxinfo | grep 'OpenGL version'"
	fi
	
	elog "For optimal performance:"
	elog "- Use SSD storage for project files"
	elog "- Ensure adequate RAM (4GB+ recommended)"
	elog "- Consider hardware acceleration"
	elog ""
	elog "First run may take longer due to initialization."
}

pkg_postrm() {
	xdg_pkg_postrm
}