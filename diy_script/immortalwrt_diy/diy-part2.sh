#!/bin/bash
#
# Copyright (c) 2019-2025 SmallProgram <https://github.com/smallprogram>
#
# This is free software, licensed under the MIT License.
# See /LICENSE for more information.
#
# https://github.com/smallprogram/OpenWrtAction
# File name: diy-part2.sh
# Description: OpenWrt DIY script part 2 (After Update feeds)
#

# Add patches
if [ "$GITHUB_ACTIONS" = "true" ] && [ -n "$GITHUB_RUN_ID" ] && [ -n "$GITHUB_WORKFLOW" ]; then
    PATCHES_SRC_DIR="$GITHUB_WORKSPACE"
else
    PATCHES_SRC_DIR="../OpenWrtAction"
fi


#------------------------------------------------------移植包------------------------------------------------------------
# rm -rf temp_resp
# git clone -b master --single-branch https://github.com/openwrt/packages.git temp_resp/openwrt_packages

# # =========================================================
# # Golang/Rust 强制覆盖 (直接操作 feeds 目录)
# # 确保这段代码在 ./scripts/feeds update -a 之后执行
# # =========================================================
# echo "清理旧版 Golang 和 Rust..."
# # 1. 删除 feeds 里的原生目录
# rm -rf feeds/packages/lang/golang
# rm -rf feeds/packages/lang/rust

# # 2. 如果之前执行过 feeds install，必须清理掉残留的软链接，防止指向空目录
# rm -rf package/feeds/packages/golang
# rm -rf package/feeds/packages/rust

# echo "注入最新版 Golang 和 Rust..."
# # 3. 将新代码直接放入 feeds 目录，伪装成原生 feed 包
# cp -a temp_resp/openwrt_packages/lang/golang feeds/packages/lang/
# cp -a temp_resp/openwrt_packages/lang/rust feeds/packages/lang/

# # =========================================================
# # 恢复上游时间戳 (避免不必要的重新编译)
# # =========================================================
# GOLANG_TIME=$(cd temp_resp/openwrt_packages && git log -1 --format=%cd --date=unix -- lang/golang)
# RUST_TIME=$(cd temp_resp/openwrt_packages && git log -1 --format=%cd --date=unix -- lang/rust)

# if [ -n "$GOLANG_TIME" ]; then
#     find feeds/packages/lang/golang -exec touch -m -d @"$GOLANG_TIME" {} +
# else
#     echo "⚠️ 警告: 无法提取 Golang 的上游时间戳，将使用拷贝时的时间"
# fi

# if [ -n "$RUST_TIME" ]; then
#     find feeds/packages/lang/rust -exec touch -m -d @"$RUST_TIME" {} +
# else
#     echo "⚠️ 警告: 无法提取 Rust 的上游时间戳，将使用拷贝时的时间"
# fi
# rm -rf temp_resp

#-------------------------------------------------------end 移植包--------------------------------------------------------


#-----------------------------------------------修改脚本------------------------------------------------------------

# rm built-in argon theme and config
rm -rf ./feeds/luci/themes/luci-theme-argon
rm -rf ./feeds/luci/themes/luci-theme-argon-mod
rm -rf ./feeds/luci/applications/luci-app-argon-config
rm -rf ./package/feeds/luci/luci-theme-argon
rm -rf ./package/feeds/luci/luci-theme-argon-mod
rm -rf ./package/feeds/luci/luci-app-argon-config
rm -rf ./package/lean/luci-theme-argon
rm -rf ./package/lean/luci-app-argon-config
rm -rf ./package/custom_packages/luci-theme-argon
rm -rf ./package/custom_packages/luci-app-argon-config

# rm appfilter
rm -rf ./feeds/packages/net/open-app-filter

# rm built-in daed/luci-app-daed/luci-app-daede (使用 kenzok8/openwrt-daede 替代)
rm -rf ./feeds/packages/net/daed
rm -rf ./feeds/packages/net/dae
rm -rf ./feeds/luci/applications/luci-app-daed
rm -rf ./feeds/luci/applications/luci-app-daede
rm -rf ./package/feeds/packages/daed
rm -rf ./package/feeds/packages/dae
rm -rf ./package/feeds/luci/luci-app-daed
rm -rf ./package/feeds/luci/luci-app-daede

# rm built-in luci-app-tailscale-community (使用 Tokisaki-Galaxy 最新版替代)
rm -rf ./feeds/luci/applications/luci-app-tailscale-community
rm -rf ./package/feeds/luci/luci-app-tailscale-community
rm -rf ./feeds/packages/net/luci-app-tailscale-community
rm -rf ./package/feeds/packages/luci-app-tailscale-community

# Modify default IP
sed -i 's/192.168.1.1/192.168.1.253/g' package/base-files/files/bin/config_generate

# fixed rust host build download llvm in ci error
for rust_mk in feeds/packages/lang/rust/Makefile package/feeds/packages/rust/Makefile package/custom_overrides/rust/Makefile; do
    [ -f "$rust_mk" ] && sed -i 's/--set=llvm\.download-ci-llvm=true/--set=llvm.download-ci-llvm=false/' "$rust_mk"
done

# inject download package
mkdir -p dl
cp -r $PATCHES_SRC_DIR/library/* ./dl/


# --- Modify SSH Configuration (Dropbear -> 2222, OpenSSH -> 22) ---

# 1. 确保 files 目录存在 (在 OpenWrt 源码根目录下)
mkdir -p files/etc/uci-defaults

# 2. 生成首次启动脚本
cat << 'EOF' > files/etc/uci-defaults/99-custom-ssh-config
#!/bin/sh

# --- 1. 停止服务 ---
# 先停掉 Dropbear，确保它彻底释放 22 端口
# (在首次启动脚本中执行这步是安全的，不会导致用户掉线，因为此时还没人登录)
/etc/init.d/dropbear stop
/etc/init.d/sshd stop 2>/dev/null  # 加上这句以防万一 sshd 已经尝试自启

# --- 2. 配置 Dropbear (UCI) ---
# 将 Dropbear 端口移至 2222
uci set dropbear.@dropbear[0].Port='2222'
uci commit dropbear

# --- 3. 配置 OpenSSH (sshd_config) ---
SSHD_CONFIG="/etc/ssh/sshd_config"
if [ -f "$SSHD_CONFIG" ]; then
    # 允许 Root 登录
    sed -i 's/^#*PermitRootLogin.*/PermitRootLogin yes/' "$SSHD_CONFIG"
    # 显式指定端口 22
    sed -i 's/^#*Port.*/Port 22/' "$SSHD_CONFIG"
fi

# --- 4. 同步密钥 (可选) ---
# mkdir -p /root/.ssh
# if [ ! -L /root/.ssh/authorized_keys ]; then
#     [ -f /root/.ssh/authorized_keys ] && mv /root/.ssh/authorized_keys /root/.ssh/authorized_keys.bak
#     ln -s /etc/dropbear/authorized_keys /root/.ssh/authorized_keys
# fi

# --- 5. 按顺序启动服务 ---

# 第一步：启动 Dropbear
# 此时配置已生效，它会乖乖去占 2222，绝对不会碰 22
/etc/init.d/dropbear start

# 第二步：启动 OpenSSH
# 此时 22 端口绝对是空闲的，OpenSSH 可以顺利接管
/etc/init.d/sshd enable
/etc/init.d/sshd start

exit 0
EOF

# 3. 赋予脚本执行权限
chmod +x files/etc/uci-defaults/99-custom-ssh-config

# --- End Modify SSH Configuration ---

# --- 自定义网口与 DHCP 配置 (R2S: LAN=eth0, WAN=eth1, 禁用LAN口DHCP; 360V6: 禁用LAN口DHCP) ---
cat << 'NETEOF' > files/etc/uci-defaults/98-custom-r2s-network
#!/bin/sh

board_name=$(cat /tmp/sysinfo/board_name 2>/dev/null)
case "$board_name" in
friendlyarm,nanopi-r2s|friendlyarm,nanopi-r2s-plus)
    # 适配 DSA / 现代 OpenWrt (device 语法)
    uci set network.lan.device='eth0' 2>/dev/null || true
    uci set network.wan.device='eth1' 2>/dev/null || true
    uci set network.wan6.device='eth1' 2>/dev/null || true

    # 适配 传统 OpenWrt / LEDE (ifname 语法)
    uci set network.lan.ifname='eth0' 2>/dev/null || true
    uci set network.wan.ifname='eth1' 2>/dev/null || true
    uci set network.wan6.ifname='eth1' 2>/dev/null || true

    uci commit network

    # LAN 口默认禁用 DHCP 服务
    uci set dhcp.lan.ignore='1' 2>/dev/null || true
    uci commit dhcp
    ;;
qihoo,360v6|qihoo,360-v6|*360v6*|*360-v6*)
    # 360V6 LAN 口默认禁用 DHCP 服务
    uci set dhcp.lan.ignore='1' 2>/dev/null || true
    uci commit dhcp
    ;;
esac

exit 0
NETEOF
chmod +x files/etc/uci-defaults/98-custom-r2s-network

#------------------------------------------------end 修改脚本-------------------------------------------------------


echo "DIY2 is complate!"
