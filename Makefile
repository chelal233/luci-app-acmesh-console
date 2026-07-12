include $(TOPDIR)/rules.mk

LUCI_TITLE:=acme.sh Console
LUCI_DEPENDS:=+luci-base +rpcd +rpcd-mod-file +rpcd-mod-uci +busybox +jsonfilter +openssl-util +ca-bundle +curl +tar +dropbearconvert +openssh-client-utils

PKG_NAME:=luci-app-acmesh-console
PKG_VERSION:=0.1.0
PKG_RELEASE:=1
PKG_LICENSE:=GPL-3.0-or-later

include ../../luci.mk

# call BuildPackage - OpenWrt buildroot signature
