#!/bin/bash
#========================================================================================================================
# Description: Automatically Build the kernel for OpenWrt
# Copyright (C) 2021 https://github.com/ophub/build-armbian
#========================================================================================================================

make_path=${PWD}
tmp_path=${make_path}/reorganization
armbian_oldpath=${make_path}/build/output/images
armbian_dtbpath=https://github.com/ophub/amlogic-s9xxx-openwrt/trunk/amlogic-s9xxx/amlogic-dtb

die() {
    error "${1}" && exit 1
}

error() {
    echo -e " [ \033[1;31m Error \033[0m ] ${1}"
}

build_kernel() {

        armbianp1=${tmp_path}/p1
        boot=${tmp_path}/boot
        root=${tmp_path}/root
        mkdir -p ${armbianp1} ${boot}/dtb/amlogic ${root}/lib

    cd  ${tmp_path}
        echo "Start build kernel for amlogic-s9xxx-openwrt ..."

        echo "copy armbian to tmp folder ..."
        cp ${armbian_oldpath}/*.img . && sync
        armbian_old=$( ls *.img 2>/dev/null | head -n 1 )
        echo "armbian: ${armbian_old}"

        echo "mount armbian ..."
        loop_old=$(losetup -P -f --show "${armbian_old}")
        [ ${loop_old} ] || die "losetup ${armbian_old} failed."

        if ! mount ${loop_old}p1 ${armbianp1}; then
            die "mount ${loop_old}p1 failed!"
        fi
        sync

        echo "copy root files ..."
        cp -rf ${armbianp1}/lib/modules ${root}/lib >/dev/null 2>&1

        echo "copy boot files ..."
        [ -f ${armbianp1}/boot/config-* ] && cp -f ${armbianp1}/boot/config-* ${boot}/ || die "config* does not exist"
        [ -f ${armbianp1}/boot/initrd.img-* ] && cp -f ${armbianp1}/boot/initrd.img-* ${boot}/ || die "initrd.img* does not exist"
        [ -f ${armbianp1}/boot/System.map-* ] && cp -f ${armbianp1}/boot/System.map-* ${boot}/ || die "System.map* does not exist"
        [ -f ${armbianp1}/boot/uInitrd-* ] && cp -f ${armbianp1}/boot/uInitrd-* ${boot}/uInitrd || die "uInitrd* does not exist"
        [ -f ${armbianp1}/boot/vmlinuz-* ] && cp -f ${armbianp1}/boot/vmlinuz-* ${boot}/zImage || die "vmlinuz* does not exist"
        [ -d ${armbianp1}/boot/dtb-* ] && cp -rf ${armbianp1}/boot/dtb-*/amlogic ${boot}/dtb/ || die "dtb does not exist"

        echo "supplement dtb file from github.com ..."
        svn checkout ${armbian_dtbpath} ${boot}/dtb/amlogic >/dev/null 2>&1

    cd ${boot}/dtb/amlogic/
        echo "delete redundant folders under amlogic ..."
        rm -rf $(find . -type d) 2>/dev/null

    cd  ${root}/lib/modules
        echo "get version ..."
        armbian_version=$(ls .)
        kernel_version=$(echo ${armbian_version} | grep -oE '[1-9].[0-9]{1,2}.[0-9]+')
        echo "kernel_version: ${kernel_version}"

    cd  ${armbian_version}
        echo "make ln for *.ko ..."
        rm -f *.ko
        x=0
        find ./ -type f -name '*.ko' -exec ln -s {} ./ \;
        sync && sleep 3
        x=$( ls *.ko -l 2>/dev/null | grep "^l" | wc -l )
        echo "Have [ ${x} ] files make *.ko link"

    cd  ${tmp_path}
        echo "umount old armbian ..."
        umount -f ${armbianp1} 2>/dev/null
        losetup -d ${loop_old} 2>/dev/null
        mkdir ${kernel_version}

    cd  ${boot}
        echo "make kernel.tar.xz ..."
        tar -cf kernel.tar *
        xz -z kernel.tar
        mv -f kernel.tar.xz ../${kernel_version} && sync

    cd  ${root}
        echo "make modules.tar.xz ..."
        tar -cf modules.tar *
        xz -z modules.tar
        mv -f modules.tar.xz ../${kernel_version} && sync

    cd  ${make_path}
        echo "mv ${kernel_version} folder to ${armbian_oldpath}"
        mv -f ${tmp_path}/${kernel_version} ${armbian_oldpath}/ && sync

    cd ${armbian_oldpath}
        echo "kernel save path: ${armbian_oldpath}/${kernel_version}.tar.gz"
        tar -czf amlogic-s9xxx-openwrt-kernel-${kernel_version}.tar.gz ${kernel_version} && sync
        rm -rf ${kernel_version} && sync

    cd  ${make_path}
        echo "delete tmp folders ..."
        rm -rf ${tmp_path} && sync

    echo "build kernel complete ..."
}

build_kernel
wait

