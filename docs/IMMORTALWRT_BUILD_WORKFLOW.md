# ImmortalWrt 25.12 x86-64 自编译工作流

本文档用于在 Windows + WSL2 环境中完成以下三类工作：

1. 使用官方 SDK 单独编译 `luci-app-acmesh-console` APK；
2. 使用官方 ImageBuilder，把本项目及现有第三方插件组合进 x86-64、ext4 镜像；
3. 从 ImmortalWrt 源码完整编译 x86-64 固件。

文档默认环境与本项目最终发布验证一致：

- Windows 仓库：`E:\git\lua-app-acme`
- 现有配置仓库：`E:\git\ImmortalWrt-ImageBuilder`
- WSL：Ubuntu 26.04，普通用户 `pc`
- ImmortalWrt：`25.12.0`
- 目标：`x86/64`
- 文件系统：`ext4`
- 根分区：`300 MiB`
- 测试路由器：`10.0.0.227`，`root`，空密码

> 所有构建目录必须放在 WSL 的 ext4 文件系统（例如 `/home/pc`），不要放在 `/mnt/c` 或 `/mnt/e`。Windows 仓库只作为只读源码输入和最终产物输出。

## 1. 路线选择

| 目标 | 使用工具 | 推荐场景 |
|---|---|---|
| 只生成本项目 APK | 官方 SDK | 日常开发、快速安装到已有路由器 |
| 生成带插件的固件 | 官方 SDK + ImageBuilder | 最稳定、最快、推荐的日常固件路线 |
| 修改内核或基础系统 | 完整 ImmortalWrt 源码树 | 内核补丁、目标平台或基础包需要重编 |

不要混用不同版本、不同 target 或不同内核 ABI 的 SDK、ImageBuilder、APK 和 kmod。`25.12.0/x86/64` 的产物只能进入同一基线。

## 2. WSL 一次性准备

在 PowerShell 中进入 WSL：

```powershell
wsl.exe -d Ubuntu-26.04
```

在 WSL 中确认环境：

```sh
set -eu
cat /etc/os-release
uname -m
test "$(uname -m)" = x86_64
test "$(stat -f -c %T "$HOME")" = ext2/ext3 || test "$(stat -f -c %T "$HOME")" = ext4
```

安装依赖：

```sh
sudo apt update
sudo apt install -y \
  ack antlr3 asciidoc autoconf automake autopoint binutils bison \
  build-essential bzip2 ccache clang cmake cpio curl device-tree-compiler \
  flex gawk gettext gcc-multilib g++-multilib git gperf help2man \
  libelf-dev libglib2.0-dev libgmp-dev libmpc-dev libmpfr-dev \
  libncurses-dev libpython3-dev libreadline-dev libssl-dev libtool \
  libyaml-dev lld llvm make ninja-build patch pkgconf python3 \
  python3-pip python3-ply python3-docutils python3-pyelftools \
  qemu-utils rsync scons squashfs-tools subversion swig texinfo \
  unzip wget xmlto xxd zlib1g-dev zstd ca-certificates openssl file
```

构建时移除 WindowsApps 等 Windows PATH。每次打开新的构建终端都执行：

```sh
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
hash -r
```

禁止使用 `sudo make`。SDK、ImageBuilder 和完整源码都必须由普通 WSL 用户编译。

## 3. 创建一次隔离构建任务

以下变量供 SDK 和 ImageBuilder 路线共同使用。整段复制到同一个 WSL 终端：

```sh
set -eu
set -o pipefail
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

VERSION=25.12.0
TARGET=x86/64
TARGET_DIR=x86/64
ROOTFS_PARTSIZE=300
RUN_ID="$(date +%Y%m%d-%H%M%S)"
RUN_ROOT="$HOME/immortalwrt-build/$RUN_ID"
DOWNLOADS="$RUN_ROOT/downloads"
WORK="$RUN_ROOT/work"
LOGS="$RUN_ROOT/logs"
ARTIFACTS="$RUN_ROOT/artifacts"

WINDOWS_APP=/mnt/e/git/lua-app-acme
WINDOWS_IMAGE_CONFIG=/mnt/e/git/ImmortalWrt-ImageBuilder
WINDOWS_OUTPUT=/mnt/e/acmesh-build-output/$RUN_ID

BASE_URL="https://downloads.immortalwrt.org/releases/$VERSION/targets/$TARGET_DIR"
SDK_ARCHIVE="immortalwrt-sdk-25.12.0-x86-64_gcc-14.3.0_musl.Linux-x86_64.tar.zst"
IB_ARCHIVE="immortalwrt-imagebuilder-25.12.0-x86-64.Linux-x86_64.tar.zst"
SDK_SHA256=c228059aa1e58c3b3ae58ce8dcc7549fd08379d8e231daf80fcca15b677564cb
IB_SHA256=c6c112f79c235300441aeeea113cfab3809e1b55c1b91b38c4b51b927cc5fe66

mkdir -p "$DOWNLOADS" "$WORK" "$LOGS" "$ARTIFACTS" "$WINDOWS_OUTPUT"
git -C "$WINDOWS_APP" rev-parse HEAD | tee "$LOGS/lua-app-acme-commit.txt"
git -C "$WINDOWS_APP" status --short | tee "$LOGS/lua-app-acme-status.txt"
printf 'RUN_ROOT=%s\n' "$RUN_ROOT"
```

每个 `RUN_ID` 使用新目录，不删除或覆盖以前的构建，也不修改两个 Windows Git 工作树。

## 4. 下载并校验官方 SDK 与 ImageBuilder

```sh
set -eu
curl -fL "$BASE_URL/$SDK_ARCHIVE" -o "$DOWNLOADS/$SDK_ARCHIVE"
curl -fL "$BASE_URL/$IB_ARCHIVE" -o "$DOWNLOADS/$IB_ARCHIVE"

printf '%s  %s\n' "$SDK_SHA256" "$DOWNLOADS/$SDK_ARCHIVE" | sha256sum -c -
printf '%s  %s\n' "$IB_SHA256" "$DOWNLOADS/$IB_ARCHIVE" | sha256sum -c -

tar --use-compress-program=unzstd -xf "$DOWNLOADS/$SDK_ARCHIVE" -C "$WORK"
tar --use-compress-program=unzstd -xf "$DOWNLOADS/$IB_ARCHIVE" -C "$WORK"

SDK="$(find "$WORK" -mindepth 1 -maxdepth 1 -type d -name 'immortalwrt-sdk-*' -print -quit)"
IMAGEBUILDER="$(find "$WORK" -mindepth 1 -maxdepth 1 -type d -name 'immortalwrt-imagebuilder-*' -print -quit)"
test -n "$SDK" && test -n "$IMAGEBUILDER"
printf 'SDK=%s\nIMAGEBUILDER=%s\n' "$SDK" "$IMAGEBUILDER"
```

升级到其他版本时，必须从对应官方 target 目录重新取得归档名和 SHA256，不能只改 `VERSION` 后继续使用上面的固定哈希。

## 5. 使用 SDK 编译本项目 APK

### 5.1 更新官方 feeds 并注入源码

```sh
set -eu
set -o pipefail
cd "$SDK"
./scripts/feeds update -a 2>&1 | tee "$LOGS/sdk-feeds-update.log"

APP_DST="$SDK/feeds/luci/applications/luci-app-acmesh-console"
mkdir -p "$APP_DST"
rsync -a --delete \
  --exclude=.git --exclude=.agents --exclude=.codex \
  "$WINDOWS_APP/" "$APP_DST/"

./scripts/feeds install -a 2>&1 | tee "$LOGS/sdk-feeds-install.log"
```

源码来自 DrvFS 时通常会呈现为 `0777`。本项目的 `Makefile` 已使用 `Build/Prepare/luci-app-acmesh-console` 把目录归一化为 `0755`、普通文件归一化为 `0644`，并只给六个入口保留 `0755`。不要删除这个构建门禁。

### 5.2 选择并编译包

```sh
set -eu
set -o pipefail
cd "$SDK"

grep -Ev '^(# )?CONFIG_PACKAGE_(luci-app-acmesh-console|luci-i18n-acmesh-console-zh-cn)(=| is not set)' \
  .config 2>/dev/null > .config.next || true
mv .config.next .config 2>/dev/null || true
printf '%s\n' \
  'CONFIG_PACKAGE_luci-app-acmesh-console=m' \
  'CONFIG_PACKAGE_luci-i18n-acmesh-console-zh-cn=m' >> .config

make defconfig
find bin/packages/x86_64/luci -maxdepth 1 -type f \
  \( -name 'luci-app-acmesh-console-*.apk' -o -name 'luci-i18n-acmesh-console-zh-cn-*.apk' \) \
  -delete 2>/dev/null || true
make package/feeds/luci/luci-app-acmesh-console/clean V=sc -j1 \
  > "$LOGS/sdk-package-clean.log" 2>&1
make package/feeds/luci/luci-app-acmesh-console/compile V=sc -j1 \
  > "$LOGS/sdk-package-build.log" 2>&1

APK="$(find "$SDK/bin/packages/x86_64/luci" -maxdepth 1 -type f \
  -name 'luci-app-acmesh-console-*.apk' -print -quit)"
I18N_APK="$(find "$SDK/bin/packages/x86_64/luci" -maxdepth 1 -type f \
  -name 'luci-i18n-acmesh-console-zh-cn-*.apk' -print -quit)"
test -s "$APK"
test -s "$I18N_APK"
sha256sum "$APK" "$I18N_APK" | tee "$LOGS/sdk-package-sha256.txt"
```

这里故意使用 `clean`、`-j1` 和完整日志，不使用快速或跳步构建。

### 5.3 APK 权限和依赖门禁

```sh
set -eu
cd "$SDK"
ADB_DUMP="$LOGS/sdk-apk-adbdump.txt"
APK_AUDIT_ROOT="$WORK/apk-audit"
rm -rf "$APK_AUDIT_ROOT"
mkdir -p "$APK_AUDIT_ROOT"
./staging_dir/host/bin/apk adbdump "$APK" > "$ADB_DUMP"
./staging_dir/host/bin/apk --allow-untrusted extract --no-chown \
  --destination "$APK_AUDIT_ROOT" "$APK"

assert_mode() {
  expected="$1"
  path="$2"
  actual="$(stat -c '%a' "$APK_AUDIT_ROOT/$path")"
  test "$actual" = "$expected" || {
    printf 'ERROR: %s mode is %s, expected %s\n' \
      "$path" "$actual" "$expected" >&2
    exit 1
  }
}

assert_mode 755 etc/init.d/acmesh-console
assert_mode 755 etc/uci-defaults/99-acmesh-console-cleanup
assert_mode 755 usr/libexec/acmesh-console/acmeshctl
assert_mode 755 usr/libexec/acmesh-console/rpc-read
assert_mode 755 usr/libexec/acmesh-console/rpc-write
assert_mode 755 usr/libexec/acmesh-console/hooks/acmesh-console-ssh.sh

for source_path in "$WINDOWS_APP"/root/usr/libexec/acmesh-console/lib/*.sh; do
  relative_path="${source_path#"$WINDOWS_APP/root/"}"
  assert_mode 644 "$relative_path"
done

if find "$APK_AUDIT_ROOT" -type d ! -perm 0755 -print -quit | grep -q .; then
  echo 'ERROR: APK contains a directory whose mode is not 0755' >&2
  exit 1
fi

if find "$APK_AUDIT_ROOT" -type f ! -perm 0644 \
  ! -path "$APK_AUDIT_ROOT/etc/init.d/acmesh-console" \
  ! -path "$APK_AUDIT_ROOT/etc/uci-defaults/99-acmesh-console-cleanup" \
  ! -path "$APK_AUDIT_ROOT/usr/libexec/acmesh-console/acmeshctl" \
  ! -path "$APK_AUDIT_ROOT/usr/libexec/acmesh-console/rpc-read" \
  ! -path "$APK_AUDIT_ROOT/usr/libexec/acmesh-console/rpc-write" \
  ! -path "$APK_AUDIT_ROOT/usr/libexec/acmesh-console/hooks/acmesh-console-ssh.sh" \
  -print -quit | grep -q .; then
  echo 'ERROR: APK contains a non-entry file whose mode is not 0644' >&2
  exit 1
fi

if find "$APK_AUDIT_ROOT" -perm -0777 -print -quit | grep -q .; then
  echo 'ERROR: APK contains mode 0777' >&2
  exit 1
fi

grep -F 'rpcd-mod-file' "$ADB_DUMP" >/dev/null
grep -F 'openssh-client-utils' "$ADB_DUMP" >/dev/null
! grep -F 'rpcd-mod-uci' "$ADB_DUMP"

cp -a "$APK" "$I18N_APK" "$ARTIFACTS/"
```

预期结果：

- `acmeshctl`、`rpc-read`、`rpc-write`、init、uci-defaults cleanup、SSH hook 为 `0755`；
- `authorization.sh`、`config.sh`、`deploy.sh`、`deploy-worker.sh` 等库文件为 `0644`；
- APK 中没有任何 `0777`。

## 6. 准备现有第三方 APK 组合

当前 `E:\git\ImmortalWrt-ImageBuilder\shell\apk-custom-packages.sh` 启用的组合是：

- `luci-app-partexp` 和中文包；
- `geoview`、`xray-core`、`sing-box`、`hysteria`；
- `luci-app-passwall2` 和中文包；
- `kmod-nft-socket`、`kmod-nft-tproxy`；
- `luci-i18n-wol-zh-cn`。

推荐固定第三方仓库提交，先审计再升级：

```sh
set -eu
set -o pipefail
THIRD_PARTY_COMMIT=6acdc32c800e0667576a2dabc29ba847c5be1aae
THIRD_PARTY="$WORK/wukongdaily-apk"

git clone https://github.com/wukongdaily/apk.git "$THIRD_PARTY"
git -C "$THIRD_PARTY" checkout --detach "$THIRD_PARTY_COMMIT"
test "$(git -C "$THIRD_PARTY" rev-parse HEAD)" = "$THIRD_PARTY_COMMIT"

cd "$IMAGEBUILDER"
mkdir -p extra-packages
cp -a "$THIRD_PARTY/run/x86/." extra-packages/
cp "$WINDOWS_IMAGE_CONFIG/shell/apk-prepare-packages.sh" ./apk-prepare-packages.sh
sh ./apk-prepare-packages.sh | tee "$LOGS/imagebuilder-third-party-prepare.log"

# 本项目必须最后复制，因为 prepare 脚本会重建 packages/。
cp -a "$APK" "$I18N_APK" packages/

for pattern in \
  'luci-app-acmesh-console-*.apk' \
  'luci-app-partexp-*.apk' \
  'luci-app-passwall2-*.apk' \
  'geoview-*.apk' 'xray-core-*.apk' 'sing-box-*.apk' 'hysteria-*.apk'
do
  find packages -maxdepth 1 -name "$pattern" -print -quit | grep . >/dev/null || {
    echo "ERROR: missing local package: $pattern" >&2
    exit 1
  }
done
```

不要直接跟随第三方仓库 `latest`。升级提交后应重新执行 APK 清单检查、ImageBuilder manifest、路由器测试和独立复审。

## 7. 使用 ImageBuilder 生成 x86-64 ext4 镜像

### 7.1 定义包列表

下面的列表与本次验证通过的 25.12.0 镜像一致：

```sh
PACKAGES="luci-app-acmesh-console luci-i18n-acmesh-console-zh-cn curl \
luci-i18n-firewall-zh-cn luci-theme-argon luci-app-argon-config \
luci-i18n-argon-config-zh-cn luci-i18n-package-manager-zh-cn \
luci-i18n-ttyd-zh-cn irqbalance luci-i18n-irqbalance-zh-cn \
e2fsprogs luci-app-wol luci-i18n-wol-zh-cn iftop tcpdump \
luci-app-attendedsysupgrade luci-i18n-attendedsysupgrade-zh-cn \
kmod-tcp-bbr kmod-nft-offload bash ethtool lm-sensors resize2fs \
ddns-go luci-app-ddns-go luci-i18n-ddns-go-zh-cn \
kmod-button-hotplug kmod-e1000e kmod-fs-f2fs kmod-i40e kmod-igb \
kmod-igbvf kmod-igc kmod-ixgbe kmod-ixgbevf kmod-r8101 kmod-r8125 \
kmod-r8126 kmod-r8168 kmod-usb-hid kmod-usb-net kmod-usb-net-asix \
kmod-usb-net-asix-ax88179 kmod-usb-net-rtl8150 \
kmod-usb-net-rtl8152-vendor kmod-fs-vfat kmod-tg3 kmod-tun kmod-vmxnet3 \
luci-app-partexp luci-i18n-partexp-zh-cn geoview xray-core sing-box \
hysteria kmod-nft-socket kmod-nft-tproxy luci-app-passwall2 \
luci-i18n-passwall2-zh-cn"
```

### 7.2 可选复制自定义 files overlay

默认不自动加入 Windows 仓库的 `files/`，避免把旧网络配置、密钥或设备身份烧进镜像。确认内容安全后执行：

```sh
FILES_DIR="$WORK/image-files"
mkdir -p "$FILES_DIR"
rsync -a --delete "$WINDOWS_IMAGE_CONFIG/files/" "$FILES_DIR/"

# 必须人工确认没有私钥、token、密码、authorizations.json 或 known_hosts。
find "$FILES_DIR" -type f -print | sort
```

如果不需要 overlay，后续命令去掉 `FILES="$FILES_DIR"` 即可。

### 7.3 生成 manifest 和镜像

```sh
set -eu
set -o pipefail
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
cd "$IMAGEBUILDER"

make manifest PROFILE=generic PACKAGES="$PACKAGES" \
  > "$LOGS/imagebuilder-manifest.log" 2>&1

for package in \
  luci-app-acmesh-console luci-i18n-acmesh-console-zh-cn \
  luci-app-partexp luci-app-passwall2 hysteria sing-box xray-core
do
  grep -E "^${package}[[:space:]]" "$LOGS/imagebuilder-manifest.log" >/dev/null || {
    echo "ERROR: package missing from manifest: $package" >&2
    exit 1
  }
done

make image PROFILE=generic PACKAGES="$PACKAGES" \
  ROOTFS_PARTSIZE="$ROOTFS_PARTSIZE" \
  > "$LOGS/imagebuilder-build.log" 2>&1
```

如需 overlay，最后一条命令改为：

```sh
make image PROFILE=generic PACKAGES="$PACKAGES" \
  FILES="$FILES_DIR" ROOTFS_PARTSIZE="$ROOTFS_PARTSIZE" \
  > "$LOGS/imagebuilder-build.log" 2>&1
```

### 7.4 镜像门禁和归档

```sh
set -eu
set -o pipefail
TARGET_OUT="$IMAGEBUILDER/bin/targets/x86/64"
cd "$TARGET_OUT"

sha256sum -c sha256sums
EFI_IMAGE="immortalwrt-$VERSION-x86-64-generic-ext4-combined-efi.img.gz"
BIOS_IMAGE="immortalwrt-$VERSION-x86-64-generic-ext4-combined.img.gz"
gzip -t "$EFI_IMAGE"
gzip -t "$BIOS_IMAGE"

grep -E '^(luci-app-acmesh-console|luci-app-partexp|luci-app-passwall2|hysteria|sing-box|xray-core) ' \
  "immortalwrt-$VERSION-x86-64-generic.manifest"

cp -a . "$ARTIFACTS/imagebuilder-target/"
cp -a "$LOGS" "$ARTIFACTS/logs"

cd "$ARTIFACTS"
find . -type f ! -name ARTIFACTS.sha256 -print0 \
  | sort -z \
  | xargs -0 sha256sum > ARTIFACTS.sha256

rsync -a "$ARTIFACTS/" "$WINDOWS_OUTPUT/"
printf 'Windows output: E:\\acmesh-build-output\\%s\n' "$RUN_ID"
```

UEFI 虚拟机使用 `generic-ext4-combined-efi.img.gz`；传统 BIOS 使用 `generic-ext4-combined.img.gz`。

## 8. 仅重新编译 APK

源码修改后，在原 SDK 中执行完整包 clean + compile：

```sh
set -eu
APP_DST="$SDK/feeds/luci/applications/luci-app-acmesh-console"
rsync -a --delete \
  --exclude=.git --exclude=.agents --exclude=.codex \
  "$WINDOWS_APP/" "$APP_DST/"

cd "$SDK"
make package/feeds/luci/luci-app-acmesh-console/clean V=sc -j1 \
  > "$LOGS/sdk-package-clean-rerun.log" 2>&1
make package/feeds/luci/luci-app-acmesh-console/compile V=sc -j1 \
  > "$LOGS/sdk-package-build-rerun.log" 2>&1
```

重新执行第 5.3 节的 APK 权限和依赖门禁。不要直接复用上一次 APK 的审计结果。

## 9. 固定测试路由器 SSH 主机密钥

首次连接前，在 WSL 中扫描候选密钥，但不要直接信任：

```sh
set -eu
ROUTER=10.0.0.227
ROUTER_KNOWN_HOSTS="$RUN_ROOT/router_known_hosts"
ROUTER_HOSTKEY_CANDIDATE="$RUN_ROOT/router_hostkey_candidate"

ssh-keyscan -T 5 -t ed25519 "$ROUTER" > "$ROUTER_HOSTKEY_CANDIDATE"
test -s "$ROUTER_HOSTKEY_CANDIDATE"
awk -v host="$ROUTER" '
  NF == 3 && $1 == host && $2 == "ssh-ed25519" && \
    $3 ~ /^[A-Za-z0-9+\/=]+$/ { valid++ }
  NF > 0 && $1 !~ /^#/ { records++ }
  END { exit !(valid == 1 && records == 1) }
' "$ROUTER_HOSTKEY_CANDIDATE"
ssh-keygen -lf "$ROUTER_HOSTKEY_CANDIDATE"
```

从虚拟机控制台直接执行 `dropbearkey -y -f /etc/dropbear/dropbear_ed25519_host_key`，将它显示的 SHA256 指纹与上一步逐字比对。只有一致时才固定候选密钥：

```sh
set -eu
cp "$ROUTER_HOSTKEY_CANDIDATE" "$ROUTER_KNOWN_HOSTS"
chmod 600 "$ROUTER_KNOWN_HOSTS"
```

如果路由器被重装，删除旧的候选文件并重新执行本节；不要用 `accept-new`、`StrictHostKeyChecking=no` 或删除固定密钥来绕过不匹配。

## 10. 安装 APK 到测试路由器

Dropbear 默认可能没有 SFTP server，因此使用 `scp -O`：

```sh
set -eu
set -o pipefail
ROUTER=10.0.0.227
test -s "$ROUTER_KNOWN_HOSTS"

scp -O -o StrictHostKeyChecking=yes \
  -o UserKnownHostsFile="$ROUTER_KNOWN_HOSTS" "$APK" \
  root@$ROUTER:/tmp/luci-app-acmesh-console.apk
scp -O -o StrictHostKeyChecking=yes \
  -o UserKnownHostsFile="$ROUTER_KNOWN_HOSTS" "$I18N_APK" \
  root@$ROUTER:/tmp/luci-i18n-acmesh-console-zh-cn.apk

ssh -o StrictHostKeyChecking=yes \
  -o UserKnownHostsFile="$ROUTER_KNOWN_HOSTS" root@$ROUTER '
  set -e
  apk add --allow-untrusted --force-overwrite \
    /tmp/luci-app-acmesh-console.apk \
    /tmp/luci-i18n-acmesh-console-zh-cn.apk
  /etc/init.d/rpcd restart
  /etc/init.d/uhttpd restart
  ls -l \
    /usr/libexec/acmesh-console/acmeshctl \
    /usr/libexec/acmesh-console/rpc-read \
    /usr/libexec/acmesh-console/rpc-write \
    /usr/libexec/acmesh-console/lib/authorization.sh \
    /usr/libexec/acmesh-console/lib/config.sh
'
```

同版本 APK 也会显示 `Replacing ... -> ...`，这是预期的强制替换安装。

## 11. 路由器完整测试

以下命令会替换测试路由器的 `/tmp/acmesh-release-tests`，只允许对可破坏的测试系统执行：

```sh
set -eu
set -o pipefail
ROUTER=10.0.0.227

tar -C "$WINDOWS_APP" \
  --exclude=.git --exclude=.agents --exclude=.codex \
  -cf - . \
| ssh -o StrictHostKeyChecking=yes \
    -o UserKnownHostsFile="$ROUTER_KNOWN_HOSTS" root@$ROUTER '
    set -e
    rm -rf /tmp/acmesh-release-tests
    mkdir -p /tmp/acmesh-release-tests
    tar -C /tmp/acmesh-release-tests -xf -
    cd /tmp/acmesh-release-tests
    sh tests/run_host_tests.sh
  ' \
| tee "$LOGS/router-host-tests.log"

grep -F 'all host tests passed' "$LOGS/router-host-tests.log"
```

安装后的最低运行审计：

```sh
ssh -o StrictHostKeyChecking=yes \
  -o UserKnownHostsFile="$ROUTER_KNOWN_HOSTS" root@10.0.0.227 '
  ubus call system board
  df -h /
  apk info -e \
    luci-app-acmesh-console luci-i18n-acmesh-console-zh-cn \
    luci-app-partexp luci-app-passwall2 hysteria sing-box xray-core
  ls -l \
    /usr/libexec/acmesh-console/acmeshctl \
    /usr/libexec/acmesh-console/rpc-read \
    /usr/libexec/acmesh-console/rpc-write \
    /usr/libexec/acmesh-console/lib/authorization.sh \
    /usr/libexec/acmesh-console/lib/config.sh \
    /usr/libexec/acmesh-console/lib/deploy-worker.sh
'
```

还必须在浏览器验证：

- **服务 → acme.sh 控制台 → 证书**；
- **操作**页面能载入账户、签发、部署和授权记录；
- **日志**页面能显示任务；
- 浏览器控制台没有 `PermissionError`、404、JavaScript error 或 warning。

## 12. 在可破坏测试路由器刷写镜像

下面是破坏性操作，会清除现有系统。只用于已确认可重建的测试虚拟机：

```sh
set -eu
set -o pipefail
ROUTER=10.0.0.227
IMAGE="$IMAGEBUILDER/bin/targets/x86/64/immortalwrt-$VERSION-x86-64-generic-ext4-combined-efi.img.gz"
LOCAL_SHA="$(sha256sum "$IMAGE" | awk '{print $1}')"

scp -O -o StrictHostKeyChecking=yes \
  -o UserKnownHostsFile="$ROUTER_KNOWN_HOSTS" \
  "$IMAGE" root@$ROUTER:/tmp/firmware.img.gz
REMOTE_SHA="$(ssh -o StrictHostKeyChecking=yes \
  -o UserKnownHostsFile="$ROUTER_KNOWN_HOSTS" root@$ROUTER \
  'sha256sum /tmp/firmware.img.gz' | awk '{print $1}')"
test "$LOCAL_SHA" = "$REMOTE_SHA"

ssh -o StrictHostKeyChecking=yes \
  -o UserKnownHostsFile="$ROUTER_KNOWN_HOSTS" root@$ROUTER \
  'sysupgrade -T /tmp/firmware.img.gz'

echo '校验通过。确认这是可破坏测试机后，再单独执行：'
echo "ssh -o StrictHostKeyChecking=yes -o UserKnownHostsFile=$ROUTER_KNOWN_HOSTS root@$ROUTER 'sysupgrade -n /tmp/firmware.img.gz'"
```

刷写命令故意不与校验命令放在同一条链中，避免路径或设备选错时立即破坏系统。

## 13. 从源码完整编译 ImmortalWrt

只有需要重编内核、基础系统或修改 target 时才使用本路线。预留至少 50 GiB 空间。

### 13.1 建立固定版本源码树

```sh
set -eu
set -o pipefail
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

FULL_RUN_ID="$(date +%Y%m%d-%H%M%S)"
FULL_ROOT="$HOME/immortalwrt-source-build/$FULL_RUN_ID"
SOURCE="$FULL_ROOT/immortalwrt"
FULL_LOGS="$FULL_ROOT/logs"
mkdir -p "$FULL_ROOT" "$FULL_LOGS"

git clone --branch v25.12.0 --single-branch --filter=blob:none \
  https://github.com/immortalwrt/immortalwrt.git "$SOURCE"
cd "$SOURCE"
git rev-parse HEAD | tee "$FULL_LOGS/source-commit.txt"

./scripts/feeds update -a 2>&1 | tee "$FULL_LOGS/feeds-update.log"

APP_DST="$SOURCE/feeds/luci/applications/luci-app-acmesh-console"
mkdir -p "$APP_DST"
rsync -a --delete \
  --exclude=.git --exclude=.agents --exclude=.codex \
  /mnt/e/git/lua-app-acme/ "$APP_DST/"

./scripts/feeds install -a 2>&1 | tee "$FULL_LOGS/feeds-install.log"
```

### 13.2 使用现有 x86-64 配置

```sh
set -eu
set -o pipefail
cd "$SOURCE"
cp /mnt/e/git/ImmortalWrt-ImageBuilder/x86-64/imm25.config .config

grep -Ev '^(# )?CONFIG_PACKAGE_(luci-app-acmesh-console|luci-i18n-acmesh-console-zh-cn)(=| is not set)' \
  .config > .config.next
mv .config.next .config

printf '%s\n' \
  'CONFIG_PACKAGE_luci-app-acmesh-console=y' \
  'CONFIG_PACKAGE_luci-i18n-acmesh-console-zh-cn=y' >> .config

make defconfig
grep -qx 'CONFIG_TARGET_x86=y' .config
grep -qx 'CONFIG_TARGET_x86_64=y' .config
grep -qx 'CONFIG_TARGET_ROOTFS_EXT4FS=y' .config
grep -qx 'CONFIG_TARGET_ROOTFS_PARTSIZE=300' .config
grep -qx 'CONFIG_PACKAGE_luci-app-acmesh-console=y' .config
grep -qx 'CONFIG_PACKAGE_luci-i18n-acmesh-console-zh-cn=y' .config
```

如果需要人工调整：

```sh
make menuconfig
```

至少确认：

- Target System：`x86`；
- Subtarget：`x86_64`；
- Target Images：`ext4`；
- Root filesystem partition size：`300 MiB` 或更大；
- `luci-app-acmesh-console` 与中文包已选中。

### 13.3 下载和编译

```sh
set -eu
set -o pipefail
cd "$SOURCE"

make download -j"$(nproc)" 2>&1 | tee "$FULL_LOGS/download.log"
SMALL_DOWNLOADS="$(find dl -type f -size -1024c -print)"
if test -n "$SMALL_DOWNLOADS"; then
  printf 'ERROR: incomplete downloads:\n%s\n' "$SMALL_DOWNLOADS" >&2
  exit 1
fi

if ! make -j"$(nproc)" 2>&1 | tee "$FULL_LOGS/build-parallel.log"; then
  echo '并行构建失败，使用单线程详细日志复现。' >&2
  make -j1 V=s 2>&1 | tee "$FULL_LOGS/build-single.log"
fi

cd bin/targets/x86/64
IMAGE=immortalwrt-25.12.0-x86-64-generic-ext4-combined-efi.img.gz
test -s "$IMAGE"
sha256sum -c sha256sums
grep -F " $IMAGE" sha256sums >/dev/null
gzip -t "$IMAGE"
```

完整源码树中的第三方插件应以源码 feed 方式加入。不要把其他发行版、其他 target 或其他 kernel ABI 的预编译 kmod APK 塞进源码构建。

## 14. 常见故障

### WSL2 提示未启用虚拟化

Windows `systeminfo` 必须显示“固件中已启用虚拟化：是”。更换 CPU 或重置 BIOS 后，Intel VT-x/AMD SVM 可能恢复为关闭。Windows 可选功能已经启用但 BIOS 虚拟化关闭时，重复安装 WSL 无效。

### `find: The relative path ... WindowsApps is included in PATH`

构建前执行：

```sh
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
hash -r
```

### APK 安装后文件变成 0777

原因通常是 DrvFS 源码权限被 APK 原样保留。确认构建日志实际执行：

```sh
grep -n 'find .*chmod 0644\|chmod 0755' "$LOGS/sdk-package-build.log"
```

并确认 `apk adbdump` 中不存在 `mode: 0777`。只在 `Makefile` 中写传统 `PKG_FILE_MODES` 不足以保证 25.12 APK 路径生效。

### `scp: /usr/libexec/sftp-server: not found`

使用旧 SCP 协议：

```sh
scp -O -o StrictHostKeyChecking=yes \
  -o UserKnownHostsFile="$ROUTER_KNOWN_HOSTS" \
  SOURCE root@10.0.0.227:/tmp/
```

### ImageBuilder 找不到第三方包

检查：

```sh
ls -1 "$IMAGEBUILDER/packages"
grep -E 'luci-app-(acmesh-console|partexp|passwall2)' "$LOGS/imagebuilder-manifest.log"
```

本地 APK 必须与 ImageBuilder 的版本、架构和 kernel ABI 匹配。

### 构建异常缓慢或结果不稳定

检查同一 SDK 是否有多个 make：

```sh
ps -eo pid,ppid,pgid,etime,args \
  | grep "$SDK" \
  | grep -E 'make|rsync' \
  | grep -v grep
```

禁止两个任务同时对同一个 SDK/ImageBuilder 目录执行 clean 或 compile。需要并发构建时必须复制成两个独立目录。

## 15. 发布前清单

- [ ] SDK、ImageBuilder、目标固件都是同一版本和 `x86/64`；
- [ ] 官方归档 SHA256 校验通过；
- [ ] 本项目来自预期 Git commit，工作树状态已记录；
- [ ] SDK 使用 clean、`-j1` 完整编译；
- [ ] APK 解包权限审计无 `0777`；
- [ ] 入口为 `0755`，库文件为 `0644`；
- [ ] ImageBuilder manifest 包含 console、partexp、passwall2 和代理核心；
- [ ] `sha256sum -c sha256sums` 和 `gzip -t` 通过；
- [ ] 从虚拟机控制台核对并固定了路由器 ed25519 主机密钥；
- [ ] 路由器完整测试以 `all host tests passed` 结束；
- [ ] 真实 LuCI 三个页面加载且控制台无错误；
- [ ] 真实 SSH 部署成功及 reload 失败回滚已验证；
- [ ] 独立只读安全复审无 P0/P1；
- [ ] APK、镜像、manifest、日志和 SHA256 清单已复制到 Windows 输出目录；
- [ ] 通过全部门禁后才允许合并 master 或刷写正式设备。

## 16. 权威来源

- ImmortalWrt 下载目录：<https://downloads.immortalwrt.org/releases/25.12.0/targets/x86/64/>
- ImmortalWrt 源码：<https://github.com/immortalwrt/immortalwrt>
- ACME 行为唯一权威：<https://github.com/acmesh-official/acme.sh>
