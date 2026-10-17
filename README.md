# repackage-internxt-drive-rpm-as-an-ebuild

<img width="630" height="583" alt="Screenshot-2026-10-17_12-30" src="https://github.com/user-attachments/assets/95c7224c-385a-4154-a604-13339f80a603" />
<img width="347" height="414" alt="Screenshot-2026-10-17_12-29" src="https://github.com/user-attachments/assets/b53ff499-f08d-4a07-bef2-775164c1cc0e" />
<img width="614" height="579" alt="Screenshot-2026-10-17_12-37" src="https://github.com/user-attachments/assets/e641a960-073c-424c-9418-1ae46832a9cd" />




Packaging upstream binary RPM releases on Gentoo provides an efficient way to install Electron-based desktop clients while maintaining full package tracking via Portage. Because prebuilt RPM archives are assembled against upstream enterprise distributions, native binary components (such as FUSE mounting helpers, antivirus engines, and desktop integration scripts) often require specific ABI compatibility symlinks, permission adjustments, and system libraries to function reliably on Gentoo.

Below is the complete technical guide and documentation for creating, placing, and maintaining the `net-misc/internxt-drive-2.6.2` ebuild in a local Portage repository.

### 1. Architecture & Packaging Overview

Internxt Drive is composed of three interconnected execution layers that the ebuild must account for:

- **Electron / Chromium Runtime:** Precompiled dynamic binaries that extract to `/opt/Internxt`. Binary stripping must be prohibited (`RESTRICT="strip"`, `QA_PREBUILT="*"`) to prevent corrupting the internal Node.js runtime and V8 snapshot checksums.
- **Integrated Antivirus (ClamAV):** Internxt bundles private ClamAV binaries (`clamd` and `freshclam`) inside `/opt/Internxt/resources/clamAV/`. These binaries link dynamically against the older `libxml2.so.2` ABI. Because modern Gentoo installs `libxml2` with SONAME `libxml2.so.16`, the ebuild injects a targeted ABI compatibility symlink inside the private library path rather than modifying system-wide `/usr/lib64`.
- **Virtual Drive (FUSE Subsystem):** Filesystem mounting relies on a Go-based helper (`/opt/Internxt/resources/dist/fuse-daemon`) communicating with the Electron main process via a UNIX domain socket. The daemon requires explicit `0755` executable permissions, access to `/dev/fuse`, and a SUID-enabled `fusermount` binary.
- **Desktop & Protocol Handlers:** The application registers an `x-scheme-handler/internxt` MIME type, hardcoding an expectation for `internxt-appimage.desktop`. A compatibility symlink in `/usr/share/applications/` prevents startup warnings, and `xdg.eclass` handles icon cache propagation for KDE Plasma and GTK desktop menus.

### 2. Local Overlay Setup

If a local repository does not already exist, initialize the standard directory layout:

1. **Configure repository definition:**

   Bash

   ```
   mkdir -p /etc/portage/repos.conf
   cat << 'EOF' > /etc/portage/repos.conf/local.conf
   [local]
   location = /var/db/repos/local
   masters = gentoo
   auto-sync = no
   EOF
   ```

2. **Initialize metadata and package directory:**

   Bash

   ```
   mkdir -p /var/db/repos/local/{metadata,profiles,net-misc/internxt-drive}
   echo "local" > /var/db/repos/local/profiles/repo_name
   echo "masters = gentoo" > /var/db/repos/local/metadata/layout.conf
   ```

3. **Create package metadata (`/var/db/repos/local/net-misc/internxt-drive/metadata.xml`):**

   XML

   ```
   <?xml version="1.0" encoding="UTF-8"?>
   <!DOCTYPE pkgmetadata SYSTEM "https://www.gentoo.org/dtd/metadata.dtd">
   <pkgmetadata>
   	<maintainer type="person">
   		<description>Local package maintainer</description>
   	</maintainer>
   	<upstream>
   		<remote-id type="github">internxt/drive-desktop-linux</remote-id>
   	</upstream>
   </pkgmetadata>
   ```

### 3. The Complete Ebuild

Save this file as `/var/db/repos/local/net-misc/internxt-drive/internxt-drive-2.6.2.ebuild`:

Bash

```
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
```

### 4. Implementation Details & Phase Hooks Explained

- **`rpm.eclass` Unpacking:** Portage transparently converts the `.rpm` archive into a tarball and extracts it into `${WORKDIR}` (`${S}`).
- **`dosym /usr/lib64/libxml2.so.16 .../libxml2.so.2`:** Satisfies the older dynamic link expected by `libclamav.so.12` without needing an unmaintained system library slot.
- **`fperms 0755 .../fuse-daemon`:** Prevents silent failures of the virtual filesystem mount when the user enables local mounting.
- **`dosym internxt.desktop .../internxt-appimage.desktop`:** Resolves the upstream hardcoded `xdg-mime default internxt-appimage.desktop x-scheme-handler/internxt` invocation.
- **`xdg_pkg_postinst`:** Rebuilds the desktop file MIME database and runs `gtk-update-icon-cache`, ensuring application launchers like KDE Kickoff display the official 256x256 app icon immediately upon emergence.

### 5. Manifest Generation & Installation

1. **Generate cryptographic digest:**

   Bash

   ```
   cd /var/db/repos/local/net-misc/internxt-drive
   ebuild internxt-drive-2.6.2.ebuild manifest
   ```

   *Verification:* A `Manifest` file containing the BLAKE2B and SHA512 hashes for `internxt-drive-2.6.2.x86_64.rpm` is generated.

2. **Emerge the package:**

   Bash

   ```
   emerge --ask net-misc/internxt-drive
   ```

3. **Verify Host FUSE Permissions (One-time system setup):** Ensure user-space mounting privileges are active on the host:

   Bash

   ```
   sudo chmod 4755 /usr/bin/fusermount /usr/bin/fusermount3
   sudo gpasswd -a $USER fuse
   ```

   *(Log out and back in to your desktop session if your user was just added to the `fuse` group).*
