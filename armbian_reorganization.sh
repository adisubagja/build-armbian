#!/bin/bash

make_path=${PWD}
tmp_path=${make_path}/reorganization
armbian_oldpath=${make_path}/build/output/images

die() {
    error "${1}" && exit 1
}

error() {
    echo -e " [ \033[1;31m Error \033[0m ] ${1}"
}


if  [ ! -f ${armbian_oldpath}/*.img ]; then
    echo "No armbian found, ready to download from github.com"
    mkdir -p ${armbian_oldpath}

    if [ -z ${GITHUB_REPOSITORY} ]; then
       echo "GITHUB_REPOSITORY is null, Mandatory designation."
       GITHUB_REPOSITORY=ophub/build-armbian
    fi

    echo "Download from github.com REPOSITORY."
    curl -s "https://api.github.com/repos/${GITHUB_REPOSITORY}/releases" | grep -o "armbian_amlogic-.*/Armbian_.*\.img.gz" | head -n 1 > DOWNLOAD_URL
    echo "DOWNLOAD_URL: $(cat DOWNLOAD_URL)"
    [ -s DOWNLOAD_URL ] && wget -q -P ${armbian_oldpath} https://github.com/${GITHUB_REPOSITORY}/releases/download/$(cat DOWNLOAD_URL)

    echo "gunzip Armbian."
    cd ${armbian_oldpath} && gunzip Armbian_*.img.gz && sync
fi


make_armbian() {

    cd ${make_path}

    armbian_newboot=${tmp_path}/boot
    armbian_newrootfs=${tmp_path}/rootfs
    mkdir -p ${armbian_newboot} ${armbian_newrootfs}

    echo "(1/3) Start make new armbian ..."
    kernel=$(cat ${armbian_oldpath}/*.txt 2>/dev/null | grep Kernel | head -n 1 | grep -oE '[1-9].[0-9]{1,2}.[0-9]+')
    armbian_new=${tmp_path}/armbian_reorganization_v${kernel}_$(date +"%Y.%m.%d.%H%M").img
    rm -f ${armbian_new}
    sync

    SKIP_MB=16
    BOOT_MB=256
    ROOT_MB=1024

    fallocate -l $((SKIP_MB + BOOT_MB + rootsize))M ${armbian_new}
    parted -s ${armbian_new} mklabel msdos 2>/dev/null
    parted -s ${armbian_new} mkpart primary fat32 $((SKIP_MB))M $((SKIP_MB + BOOT_MB -1))M 2>/dev/null
    parted -s ${armbian_new} mkpart primary ext4 $((SKIP_MB + BOOT_MB))M 100% 2>/dev/null

    echo "losetup new armbian ..."
    loop_new=$(losetup -P -f --show "${armbian_new}")
    [ ${loop_new} ] || die "losetup ${armbian_new} failed."
    
    mkfs.vfat -n "BOOT" ${loop_new}p1 >/dev/null 2>&1
    mke2fs -F -q -t ext4 -L "ROOTFS" -m 0 ${loop_new}p2 >/dev/null 2>&1

    echo "mount boot and rootfs ..."
    if ! mount ${loop_new}p1 ${armbian_newboot}; then
        die "mount ${loop_new}p1 failed!"
    fi

    if ! mount ${loop_new}p2 ${armbian_newrootfs}; then
        die "mount ${loop_new}p2 failed!"
    fi

    echo "(1/3) make complete ..."

}

extract_armbian() {

    cd ${tmp_path}
    echo "(2/3) Start extract old armbian ..."
    armbianp1=${tmp_path}/armbianold/p1
    mkdir -p ${armbianp1}

    cp ${armbian_oldpath}/*.img . && sync
    armbian_old=$( ls *.img 2>/dev/null | head -n 1 )
    echo "armbian_old: ${armbian_old}"

    echo "mount armbian ..."
    loop_old=$(losetup -P -f --show "${armbian_old}")
    [ ${loop_old} ] || die "losetup ${armbian_old} failed."

    if ! mount ${loop_old}p1 ${armbianp1}; then
        die "mount ${loop_old}p1 failed!"
    fi
    sync

    echo "copy boot files ..."
    [ -f ${armbianp1}/boot/config-* ] && cp -f ${armbianp1}/boot/config-* ${armbian_newboot}/ || die "(1/3) config* does not exist"
    [ -f ${armbianp1}/boot/initrd.img-* ] && cp -f ${armbianp1}/boot/initrd.img-* ${armbian_newboot}/ || die "(1/3) initrd.img* does not exist"
    [ -f ${armbianp1}/boot/System.map-* ] && cp -f ${armbianp1}/boot/System.map-* ${armbian_newboot}/ || die "(1/3) System.map* does not exist"
    [ -f ${armbianp1}/boot/uInitrd-* ] && cp -f ${armbianp1}/boot/uInitrd-* ${armbian_newboot}/uInitrd || die "(1/3) uInitrd* does not exist"
    [ -f ${armbianp1}/boot/vmlinuz-* ] && cp -f ${armbianp1}/boot/vmlinuz-* ${armbian_newboot}/zImage || die "(1/3) vmlinuz* does not exist"
    [ -d ${armbianp1}/boot/dtb-* ] && cp -rf ${armbianp1}/boot/dtb-*/amlogic ${armbian_newboot}/dtb/ || die "(1/3) dtb does not exist"

    echo "add uEnv.txt to boot ..."
    cat << EOF > ${armbian_newboot}/uEnv.txt
LINUX=/zImage
INITRD=/uInitrd

FDT=/dtb/amlogic/meson-gxl-s905d-phicomm-n1.dtb
APPEND=root=LABEL=ROOTFS rootflags=data=writeback rw console=ttyAML0,115200n8 console=tty0 no_console_suspend consoleblank=0 fsck.fix=yes fsck.repair=yes net.ifnames=0
EOF

    echo "copy root files ..."
    cp -rf ${armbianp1}/* ${armbian_newrootfs}/ >/dev/null 2>&1
    sync

    cd ${tmp_path}
    echo "umount old armbian and delete tmp folders ..."
    umount -f ${armbianp1} 2>/dev/null
    losetup -d ${loop_old} 2>/dev/null

    echo "(2/3) extract complete ..."
}

clear_mountdata() {

    cd ${make_path}
    echo "(3/3) umount new armbian ..."
    umount -f ${armbian_newboot} 2>/dev/null
    umount -f ${armbian_newrootfs} 2>/dev/null
    losetup -d ${loop_new} 2>/dev/null

    echo "delete tmp folders ..."
    mv -f ${tmp_path}/${armbian_new##*/} build/output/images/ && sync
    rm -rf ${tmp_path}

    echo "(3/3) all complete ..."

}

make_armbian
extract_armbian
clear_mountdata

wait
