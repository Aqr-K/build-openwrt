#!/bin/bash
#========================================================================================================================
# https://github.com/ophub/amlogic-s9xxx-openwrt
# Description: Automatically Build OpenWrt
# Function: Diy script (After Update feeds, Modify the default IP, hostname, theme, add/remove software packages, etc.)
# Source code repository: https://github.com/openwrt/openwrt / Branch: main
#========================================================================================================================

# ------------------------------- Main source started -------------------------------
#
# Add the default password for the 'root' user（Change the empty password to 'password'）
sed -i 's/root:::0:99999:7:::/root:$1$V4UetPzk$CYXluq4wUazHjmCDBCqXF.::0:99999:7:::/g' package/base-files/files/etc/shadow

# Set etc/openwrt_release
sed -i "s|DISTRIB_REVISION='.*'|DISTRIB_REVISION='R$(date +%Y.%m.%d)'|g" package/base-files/files/etc/openwrt_release
echo "DISTRIB_SOURCECODE='official'" >>package/base-files/files/etc/openwrt_release

# Modify default IP（FROM 192.168.1.1 CHANGE TO 192.168.31.4）
# sed -i 's/192.168.1.1/192.168.31.4/g' package/base-files/files/bin/config_generate
#
# ------------------------------- Main source ends -------------------------------

# ------------------------------- Other started -------------------------------
#
# Add luci-app-amlogic
# svn co https://github.com/ophub/luci-app-amlogic/trunk/luci-app-amlogic package/luci-app-amlogic

# coolsnowwolf default software package replaced with Lienol related software package
# rm -rf feeds/packages/utils/{containerd,libnetwork,runc,tini}
# svn co https://github.com/Lienol/openwrt-packages/trunk/utils/{containerd,libnetwork,runc,tini} feeds/packages/utils

# Add third-party software packages (The entire repository)
# git clone https://github.com/libremesh/lime-packages.git package/lime-packages
# Add third-party software packages (Specify the package)
# svn co https://github.com/libremesh/lime-packages/trunk/packages/{shared-state-pirania,pirania-app,pirania} package/lime-packages/packages
# Add to compile options (Add related dependencies according to the requirements of the third-party software package Makefile)
# sed -i "/DEFAULT_PACKAGES/ s/$/ pirania-app pirania ip6tables-mod-nat ipset shared-state-pirania uhttpd-mod-lua/" target/linux/armvirt/Makefile

# Apply patch
# git apply ../config/patches/{0001*,0002*}.patch --directory=feeds/luci
#
# ------------------------------- Other ends -------------------------------

# 创建高度安全的自动扩容脚本
mkdir -p files/etc/init.d
cat << 'EOF' > files/etc/init.d/expand-rootfs
#!/bin/sh /etc/rc.common

START=99

start() {
    # 1. 检查标记文件，如果存在则说明已经扩容过，直接退出
    if [ -f /etc/config/.rootfs_expanded ]; then
        return 0
    fi

    # 2. 确认是否是 EMMC 设备 (MT5000 默认路径)
    DISK_DEV="/dev/mmcblk0"
    [ ! -b "$DISK_DEV" ] && return 0

    # 3. 找到 rootfs_data 或者当前的 overlay 分区号
    # MT5000 的 OpenWrt 固件通常最后一个分区是 rootfs_data
    PART_NUM=$(parted $DISK_DEV print | grep -E "rootfs_data|ext4" | tail -n1 | awk '{print $1}')
    [ -z "$PART_NUM" ] && return 0

    # 4. 核心安全检查：尝试在 /etc/config 建立测试文件
    # 如果系统是只读的，直接放弃重启，防止无限循环
    touch /etc/config/.expand_test || {
        logger -t "EXPAND" "Error: Filesystem is read-only. Aborting expand to prevent boot loop."
        return 0
    }
    rm /etc/config/.expand_test

    logger -t "EXPAND" "Starting RootFS Auto Expand on $DISK_DEV partition $PART_NUM..."

    # 5. 执行分区扩容 (100% 占满)
    # 使用 parted 扩容
    parted -s $DISK_DEV resizepart $PART_NUM 100%
    
    # 告知内核同步分区表
    sync
    # 部分旧内核不支持在挂载时动态读取分区表，这里必须要同步
    [ -x /usr/sbin/partprobe ] && partprobe $DISK_DEV

    # 6. 关键步骤：先创建永久标记文件并同步到磁盘
    touch /etc/config/.rootfs_expanded
    sync

    # 7. 最后一步：执行文件系统在线扩容 (ext4 支持在线扩容)
    # 这样即使不重启，空间其实已经变大了
    resize2fs ${DISK_DEV}p${PART_NUM}

    logger -t "EXPAND" "RootFS Expand successfully."
    
    # 8. 如果你使用的是 ext4，其实不需要 reboot 就能立刻生效
    # 但为了让所有系统服务重新计算可用空间，重启一次是最稳妥的
    # 我们加入一个延时，防止万一标记文件没存稳就重启了
    sleep 3
    reboot
}
EOF

chmod +x files/etc/init.d/expand-rootfs
