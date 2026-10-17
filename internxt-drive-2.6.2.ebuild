# Copyright 2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

inherit desktop rpm xdg

DESCRIPTION="Cloud storage desktop client for Internxt Drive"
HOMEPAGE="https://internxt.com/"
SRC_URI="https://github.com/internxt/drive-desktop-linux/releases/download/${PV}/internxt-${PV}.x86_64.rpm -> ${P}.x86_64.rpm"

S="${WORKDIR}"

LICENSE="GPL-3"
SLOT="0"
KEYWORDS="~amd64"
RESTRICT="strip mirror"

RDEPEND="
	app-accessibility/at-spi2-core:2
	dev-libs/glib:2
	dev-libs/libxml2
	dev-libs/nspr
	dev-libs/nss
	media-libs/alsa-lib
	media-libs/mesa[gbm(+)]
	net-misc/curl
	net-print/cups
	sys-apps/dbus
	sys-fs/fuse:0
	sys-fs/fuse:3
	x11-libs/cairo
	x11-libs/libX11
	x11-libs/libXcomposite
	x11-libs/libXdamage
	x11-libs/libXext
	x11-libs/libXfixes
	x11-libs/libXrandr
	x11-libs/libdrm
	x11-libs/libxcb
	x11-libs/libxkbcommon
	x11-libs/pango
"
BDEPEND="app-arch/rpm2targz"

QA_PREBUILT="*"

src_install() {
	# Copy unpacked filesystem hierarchy (/opt, /usr, etc.) into ED
	local dir
	for dir in opt usr; do
		if [[ -d "${S}/${dir}" ]]; then
			cp -a "${S}/${dir}" "${ED}/" || die "Failed to install ${dir}"
		fi
	done

	# Explicitly install the bundled 256x256 icon from the RPM
	local rpm_icon="${S}/usr/share/icons/hicolor/256x256/apps/internxt.png"
	if [[ -f "${rpm_icon}" ]]; then
		newicon -s 256 "${rpm_icon}" internxt.png
	fi

	# Ensure the desktop file references 'internxt' (matches internxt.png)
	if [[ -f "${ED}/usr/share/applications/internxt.desktop" ]]; then
		sed -i 's|^Icon=.*|Icon=internxt|' "${ED}/usr/share/applications/internxt.desktop" || die
	fi

	# Provide libxml2.so.2 ABI compatibility for bundled ClamAV
	if [[ -d "${ED}/opt/Internxt/resources/clamAV/lib" ]]; then
		dosym /usr/lib64/libxml2.so.16 /opt/Internxt/resources/clamAV/lib/libxml2.so.2
	fi

	# Ensure execute permissions on fuse-daemon
	if [[ -f "${ED}/opt/Internxt/resources/dist/fuse-daemon" ]]; then
		fperms 0755 /opt/Internxt/resources/dist/fuse-daemon
	fi

	# Fix xdg scheme handler target desktop name expected by upstream
	if [[ -f "${ED}/usr/share/applications/internxt.desktop" && ! -f "${ED}/usr/share/applications/internxt-appimage.desktop" ]]; then
		dosym internxt.desktop /usr/share/applications/internxt-appimage.desktop
	fi

	# Ensure main binary has execute permissions and PATH availability
	local bin_path
	for bin_path in "${ED}"/opt/[Ii]nternxt*/internxt; do
		if [[ -f "${bin_path}" ]]; then
			fperms 0755 "${bin_path#${ED}}"
			if [[ ! -f "${ED}/usr/bin/internxt" ]]; then
				dosym "${bin_path#${ED}}" /usr/bin/internxt
			fi
			break
		fi
	done
}

pkg_postinst() {
	xdg_pkg_postinst
}

pkg_postrm() {
	xdg_pkg_postrm
}

