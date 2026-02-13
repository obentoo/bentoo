# Copyright 1999-2025 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

inherit bash-completion-r1 desktop unpacker xdg

DESCRIPTION="AI IDE that helps you do your best work by turning ideas into production code"
HOMEPAGE="https://kiro.dev/"
SRC_URI="https://prod.download.desktop.kiro.dev/releases/stable/linux-x64/signed/${PV}/deb/${PN}-ide-${PV}-stable-linux-x64.deb -> ${P}.deb"

LICENSE="MIT"
SLOT="0"
KEYWORDS="~amd64"
IUSE="wayland"

RESTRICT="mirror strip bindist"

RDEPEND="
	>=app-accessibility/at-spi2-core-2.5.3
	app-crypt/libsecret
	>=dev-libs/expat-2.1_beta3
	>=dev-libs/glib-2.37.3:2
	>=dev-libs/nspr-4.9
	>=dev-libs/nss-3.26
	>=media-libs/alsa-lib-1.0.17
	>=media-libs/mesa-17.1.0[gbm(+)]
	>=net-misc/curl-7.0.0
	>=net-print/cups-1.6.0
	>=sys-apps/dbus-1.9.14
	>=sys-apps/util-linux-2.25
	>=x11-libs/cairo-1.6.0
	>=x11-libs/gtk+-3.9.10:3[wayland?]
	>=x11-libs/libdrm-2.4.75
	>=x11-libs/libX11-1.4.99.1
	>=x11-libs/libxcb-1.9.2
	>=x11-libs/libXcomposite-0.4.4
	>=x11-libs/libXdamage-1.1
	x11-libs/libXext
	x11-libs/libXfixes
	>=x11-libs/libxkbcommon-0.5.0
	>=x11-libs/libxkbfile-1.1.0
	x11-libs/libXrandr
	>=x11-libs/pango-1.14.0
	>=x11-misc/xdg-utils-1.0.2
	wayland? ( dev-libs/wayland )
	media-libs/vulkan-loader
"

# QA overrides for Electron binaries
QA_PREBUILT="
	opt/kiro/kiro
	opt/kiro/chrome_crashpad_handler
	opt/kiro/chrome-sandbox
	opt/kiro/lib*.so*
"

S="${WORKDIR}"

src_unpack() {
	unpack_deb ${A}
}

src_prepare() {
	default
	
	# Debug: Show package structure
	einfo "=== PACKAGE STRUCTURE DEBUG ==="
	einfo "Desktop files found:"
	find . -name "*.desktop" -type f || true
	
	if [[ -f usr/share/applications/kiro.desktop ]]; then
		einfo "Original kiro.desktop content:"
		cat usr/share/applications/kiro.desktop
	fi
	
	einfo "Icon files found:"
	find . -name "*.png" -o -name "*.svg" -o -name "*.ico" | head -20 || true
	einfo "=============================="
	
	# Configure chrome-sandbox permissions
	if [[ -f usr/share/kiro/chrome-sandbox ]]; then
		chmod 4755 usr/share/kiro/chrome-sandbox || die "Failed to set chrome-sandbox permissions"
	fi
	
	# Remove Debian files
	rm -rf DEBIAN/ || die "Failed to remove Debian files"
	
	# Remove cross-platform binaries to eliminate QA warnings
	einfo "Cleaning up unnecessary cross-platform binaries..."
	
	local files_removed=0
	
	# Remove ARM64/aarch64 binaries
	while IFS= read -r -d '' file; do
		rm -f "${file}" && ((files_removed++))
	done < <(find usr/share/kiro -path "*/arm64/*" -type f -print0 2>/dev/null)
	
	while IFS= read -r -d '' file; do
		rm -f "${file}" && ((files_removed++))
	done < <(find usr/share/kiro -path "*/aarch64/*" -type f -print0 2>/dev/null)
	
	while IFS= read -r -d '' file; do
		rm -f "${file}" && ((files_removed++))
	done < <(find usr/share/kiro -name "*arm64*" -type f -print0 2>/dev/null)
	
	# Remove other platform binaries
	while IFS= read -r -d '' file; do
		rm -f "${file}" && ((files_removed++))
	done < <(find usr/share/kiro -path "*/darwin/*" -o -path "*/win32/*" -o -name "*.dll" -o -name "*.dylib" -type f -print0 2>/dev/null)
	
	# Clean up empty directories
	find usr/share/kiro -type d -empty -delete 2>/dev/null || true
	
	einfo "Removed ${files_removed} unnecessary cross-platform files"
	
	# Verify main executable exists
	[[ -f usr/share/kiro/kiro ]] || die "Main Kiro executable not found after cleanup!"
}

src_install() {
	# Install application to /opt/kiro
	insinto /opt/kiro
	doins -r usr/share/kiro/*
	
	# Fix permissions for executables
	fperms +x /opt/kiro/kiro
	fperms +x /opt/kiro/chrome_crashpad_handler
	fperms 4755 /opt/kiro/chrome-sandbox
	
	# Fix permissions for shared libraries
	local lib
	for lib in usr/share/kiro/lib*.so*; do
		if [[ -f "${lib}" ]]; then
			local basename_lib="${lib##*/}"
			fperms +x "/opt/kiro/${basename_lib}"
		fi
	done
	
	# Additional approach for libraries using find in destination
	find "${D}/opt/kiro" -name "*.so*" -type f -print0 | while IFS= read -r -d '' so_file; do
		local rel_path="${so_file#${D}}"
		fperms +x "${rel_path}"
	done
	
	# Wrapper script with enhanced error handling
	exeinto /usr/bin
	newexe - kiro <<-'EOF'
		#!/bin/bash
		# Kiro IDE wrapper script
		
		set -e
		
		export ELECTRON_IS_DEV=0
		export ELECTRON_FORCE_IS_PACKAGED=true
		
		declare -a KIRO_ARGS
		
		KIRO_ARGS=(
			--no-sandbox
			--disable-gpu-sandbox
			--disable-software-rasterizer
			--enable-features=VaapiVideoDecoder
			--disable-dev-shm-usage
			--disable-background-timer-throttling
		)
		
		# Wayland support detection
		if [[ -n "${WAYLAND_DISPLAY}" ]] && command -v wayland-scanner >/dev/null 2>&1; then
			KIRO_ARGS+=(
				--ozone-platform=wayland
				--enable-features=UseOzonePlatform
			)
		fi
		
		# Verify installation
		if [[ ! -x /opt/kiro/kiro ]]; then
			echo "Error: Kiro executable not found or not executable" >&2
			exit 1
		fi
		
		exec /opt/kiro/kiro "${KIRO_ARGS[@]}" "$@"
	EOF
	
	# Icons - comprehensive installation following Cursor pattern
	einfo "Installing icons..."
	
	# Install all available icon structures
	if [[ -d usr/share/icons ]]; then
		einfo "Installing icon theme structure from usr/share/icons"
		insinto /usr/share
		doins -r usr/share/icons
	fi
	
	# Install pixmaps
	if [[ -d usr/share/pixmaps ]]; then
		einfo "Installing pixmap icons from usr/share/pixmaps"
		insinto /usr/share/pixmaps
		doins usr/share/pixmaps/*
	fi
	
	# Create specific icon entries for the application
	local icon_name="kiro"
	local icon_installed=false
	
	# Try different icon sources
	if [[ -f usr/share/pixmaps/code-oss.png ]]; then
		einfo "Installing main icon from pixmaps/code-oss.png"
		newicon usr/share/pixmaps/code-oss.png "${icon_name}.png"
		icon_installed=true
		
		# Also install to hicolor theme in multiple sizes
		local sizes=(16 22 24 32 48 64 128 256)
		for size in "${sizes[@]}"; do
			newicon -s "${size}" usr/share/pixmaps/code-oss.png "${icon_name}.png"
		done
	fi
	
	# Debug: Show what icons were installed
	einfo "Icon installation summary:"
	einfo "  Target icon name: ${icon_name}"
	einfo "  Icon installed: ${icon_installed}"
	
	# Desktop entry - completely rewrite to ensure correct paths
	if [[ -f usr/share/applications/kiro.desktop ]]; then
		einfo "Processing desktop file..."
		
		# Show original content
		einfo "Original desktop file:"
		cat usr/share/applications/kiro.desktop
		
		# Instead of sed, create a new desktop file from scratch to ensure correctness
		cat > kiro-fixed.desktop <<-EOF
			[Desktop Entry]
			Version=1.0
			Type=Application
			Name=Kiro IDE
			Comment=AI IDE that helps you do your best work by turning ideas into production code
			Exec=/opt/kiro/kiro %F
			Icon=${icon_name}
			Categories=Development;IDE;TextEditor;
			MimeType=text/plain;inode/directory;
			StartupWMClass=kiro
			StartupNotify=true
			Terminal=false
		EOF
		
		# If there are additional fields in the original, try to preserve them
		if grep -q "^Keywords=" usr/share/applications/kiro.desktop; then
			local keywords
			keywords=$(grep "^Keywords=" usr/share/applications/kiro.desktop | head -1)
			echo "${keywords}" >> kiro-fixed.desktop
		fi
		
		if grep -q "^GenericName=" usr/share/applications/kiro.desktop; then
			local generic_name
			generic_name=$(grep "^GenericName=" usr/share/applications/kiro.desktop | head -1)
			echo "${generic_name}" >> kiro-fixed.desktop
		fi
		
		# Show corrected content
		einfo "Corrected desktop file:"
		cat kiro-fixed.desktop
		
		domenu kiro-fixed.desktop
		einfo "Desktop file installed successfully"
	else
		ewarn "No desktop file found at usr/share/applications/kiro.desktop"
		
		# Create minimal desktop file if none exists
		cat > kiro-minimal.desktop <<-EOF
			[Desktop Entry]
			Version=1.0
			Type=Application
			Name=Kiro IDE
			Comment=AI IDE for development
			Exec=/opt/kiro/kiro %F
			Icon=${icon_name}
			Categories=Development;IDE;TextEditor;
			StartupWMClass=kiro
			StartupNotify=true
			Terminal=false
		EOF
		
		domenu kiro-minimal.desktop
		einfo "Created minimal desktop file"
	fi
	
	# URL handler - also completely rewrite if it exists
	if [[ -f usr/share/applications/kiro-url-handler.desktop ]]; then
		einfo "Processing URL handler desktop file..."
		
		cat > kiro-url-handler-fixed.desktop <<-EOF
			[Desktop Entry]
			Version=1.0
			Type=Application
			Name=Kiro IDE URL Handler
			Comment=Handle Kiro IDE URLs
			Exec=/opt/kiro/kiro --open-url %U
			Icon=${icon_name}
			Categories=Development;IDE;
			NoDisplay=true
			StartupNotify=true
			Terminal=false
			MimeType=x-scheme-handler/kiro;
		EOF
		
		domenu kiro-url-handler-fixed.desktop
		einfo "URL handler desktop file installed"
	fi
	
	# MIME types
	if [[ -f usr/share/mime/packages/kiro-workspace.xml ]]; then
		insinto /usr/share/mime/packages
		doins usr/share/mime/packages/kiro-workspace.xml
	fi
	
	# AppData
	if [[ -f usr/share/appdata/kiro.appdata.xml ]]; then
		insinto /usr/share/metainfo
		newins usr/share/appdata/kiro.appdata.xml dev.kiro.kiro.appdata.xml
	fi
	
	# Shell completions
	if [[ -f usr/share/bash-completion/completions/kiro ]]; then
		dobashcomp usr/share/bash-completion/completions/kiro
	fi
	
	if [[ -f usr/share/zsh/vendor-completions/_kiro ]]; then
		insinto /usr/share/zsh/site-functions
		doins usr/share/zsh/vendor-completions/_kiro
	fi
}

pkg_postinst() {
	xdg_pkg_postinst
	
	# Verify installation
	if [[ ! -x "${EROOT}/opt/kiro/kiro" ]]; then
		eerror "Kiro executable was not installed correctly!"
		eerror "Please check the installation and file a bug report."
		die "Installation verification failed"
	fi
	
	elog "Kiro IDE ${PV} (build ${BUILD_ID}) successfully installed!"
	elog ""
	elog "Installation verified:"
	elog "  Executable: ${EROOT}/opt/kiro/kiro"
	elog "  Wrapper: ${EROOT}/usr/bin/kiro"
	elog "  Desktop file: ${EROOT}/usr/share/applications/kiro-fixed.desktop"
	elog ""
	elog "If Kiro doesn't appear in your application menu:"
	elog "  1. Update desktop database: update-desktop-database"
	elog "  2. Update icon cache: gtk-update-icon-cache -f -t /usr/share/icons/hicolor"
	elog "  3. Restart your desktop environment or log out/in"
	elog ""
	elog "You can also launch Kiro manually:"
	elog "  Direct: /opt/kiro/kiro"
	elog "  Via wrapper: kiro (if wrapper script exists)"
	elog ""
	elog "This version has been optimized for amd64 systems with"
	elog "unnecessary cross-platform binaries removed."
	elog ""
	elog "To optimize your experience:"
	elog "  • Make sure you have a stable connection for AI features"
	elog "  • Install updated drivers for better GPU performance"
	elog ""
	elog "Configuration: ~/.config/kiro/"
	elog "Documentation: https://kiro.dev/"
	
	if ! groups "${USER}" 2>/dev/null | grep -q video; then
		ewarn "User is not in the 'video' group."
		ewarn "Run: usermod -a -G video \${USER}"
	fi
}

pkg_postrm() {
	xdg_pkg_postrm
}