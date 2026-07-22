include $(TOPDIR)/rules.mk

LUCI_TITLE:=acme.sh Console
LUCI_DEPENDS:=+luci-base +rpcd +rpcd-mod-file +busybox +jsonfilter +openssl-util +ca-bundle +curl +tar +dropbearconvert +openssh-client-utils

PKG_NAME:=luci-app-acmesh-console
PKG_VERSION:=0.1.0
PKG_RELEASE:=1
PKG_LICENSE:=GPL-3.0-or-later
PKG_FILE_MODES:=/etc/init.d/acmesh-console:root:root:0755 \
	/etc/uci-defaults/99-acmesh-console-cleanup:root:root:0755 \
	/usr/libexec/acmesh-console/acmeshctl:root:root:0755 \
	/usr/libexec/acmesh-console/hooks/acmesh-console-ssh.sh:root:root:0755 \
	/usr/libexec/acmesh-console/rpc-read:root:root:0755 \
	/usr/libexec/acmesh-console/rpc-write:root:root:0755

# Windows/DrvFS checkouts report every source entry as 0777. APK packaging
# preserves those modes and does not consume PKG_FILE_MODES, so normalize the
# prepared LuCI tree through luci.mk's per-application prepare hook.
define Build/Prepare/luci-app-acmesh-console
	find $(PKG_BUILD_DIR) -type d -exec chmod 0755 {} +
	find $(PKG_BUILD_DIR) -type f -exec chmod 0644 {} +
	chmod 0755 \
		$(PKG_BUILD_DIR)/root/etc/init.d/acmesh-console \
		$(PKG_BUILD_DIR)/root/etc/uci-defaults/99-acmesh-console-cleanup \
		$(PKG_BUILD_DIR)/root/usr/libexec/acmesh-console/acmeshctl \
		$(PKG_BUILD_DIR)/root/usr/libexec/acmesh-console/hooks/acmesh-console-ssh.sh \
		$(PKG_BUILD_DIR)/root/usr/libexec/acmesh-console/rpc-read \
		$(PKG_BUILD_DIR)/root/usr/libexec/acmesh-console/rpc-write
endef

define Package/luci-app-acmesh-console/conffiles
/etc/config/acmesh-console
/etc/acmesh-console/config.json
/etc/acmesh-console/instance-id
/etc/acmesh-console/authorizations.json
/etc/acmesh-console/ssh/id_ed25519
/etc/acmesh-console/ssh/id_ed25519.pub
/etc/acmesh-console/ssh/known_hosts
endef

include $(TOPDIR)/feeds/luci/luci.mk
