# This software is a part of ISAR.
# Copyright (C) 2018 Siemens AG
#
# SPDX-License-Identifier: MIT

ISAR_CROSS_COMPILE ??= "0"

# Choose the correct buildchroot: host or target
python __anonymous() {
    mode = d.getVar('ISAR_CROSS_COMPILE', True)
    distro_arch = d.getVar('DISTRO_ARCH')
    if mode == "0" or d.getVar('HOST_ARCH') ==  distro_arch:
        dep = "buildchroot-target:do_build"
        rootfs = d.getVar('BUILDCHROOT_TARGET_DIR', False)
    else:
        dep = "buildchroot-host:do_build"
        rootfs = d.getVar('BUILDCHROOT_HOST_DIR', False)

    d.setVar('BUILDCHROOT_DEP', dep)
    d.setVar('BUILDCHROOT_DIR', rootfs)
}

MOUNT_LOCKFILE = "${BUILDCHROOT_DIR}.lock"

buildchroot_do_mounts() {
    if [ "${USE_CCACHE}" = "1" ]; then
        mkdir -p ${CCACHE_DIR}/debug
    fi

    sudo -s <<'EOSUDO'
        ( flock 9
        set -e

        mkdir -p '${BUILDCHROOT_DIR}/isar-apt'
        mountpoint -q '${BUILDCHROOT_DIR}/isar-apt' ||
            mount --bind '${REPO_ISAR_DIR}/${DISTRO}' '${BUILDCHROOT_DIR}/isar-apt'
        mkdir -p '${BUILDCHROOT_DIR}/downloads'
        mountpoint -q '${BUILDCHROOT_DIR}/downloads' ||
            mount --bind '${DL_DIR}' '${BUILDCHROOT_DIR}/downloads'
        if [ "${USE_CCACHE}" = "1" ]; then
            mkdir -p '${BUILDCHROOT_DIR}/ccache'
            mountpoint -q '${BUILDCHROOT_DIR}/ccache' ||
                mount --bind '${CCACHE_DIR}' '${BUILDCHROOT_DIR}/ccache'
        fi
        mkdir -p '${BUILDCHROOT_DIR}/dev/shm' '${BUILDCHROOT_DIR}/dev/pts'
        mountpoint -q '${BUILDCHROOT_DIR}/dev' ||
            ( mount -o bind,private /dev '${BUILDCHROOT_DIR}/dev' &&
              mount -t tmpfs none '${BUILDCHROOT_DIR}/dev/shm' &&
              mount --bind /dev/pts '${BUILDCHROOT_DIR}/dev/pts' )
        mkdir -p '${BUILDCHROOT_DIR}/proc'
        mountpoint -q '${BUILDCHROOT_DIR}/proc' ||
            mount -t proc none '${BUILDCHROOT_DIR}/proc'
        mkdir -p '${BUILDCHROOT_DIR}/sys'
        mountpoint -q '${BUILDCHROOT_DIR}/sys' ||
            mount --rbind /sys '${BUILDCHROOT_DIR}/sys'
        mount --make-rslave '${BUILDCHROOT_DIR}/sys'

        # Mount base-apt if 'ISAR_USE_CACHED_BASE_REPO' is set
        if [ "${@repr(bb.utils.to_boolean(d.getVar('ISAR_USE_CACHED_BASE_REPO')))}" = 'True' ]
        then
            mkdir -p '${BUILDCHROOT_DIR}/base-apt'
            mountpoint -q '${BUILDCHROOT_DIR}/base-apt' || \
                mount --bind '${REPO_BASE_DIR}' '${BUILDCHROOT_DIR}/base-apt'
        fi

        # Refresh or remove /etc/resolv.conf at this chance
        if [ "${@repr(bb.utils.to_boolean(d.getVar('BB_NO_NETWORK')))}" = 'True' ]
        then
            rm -rf '${BUILDCHROOT_DIR}/etc/resolv.conf'
        else
            cp -L /etc/resolv.conf '${BUILDCHROOT_DIR}/etc'
        fi

        ) 9>'${MOUNT_LOCKFILE}'
EOSUDO
}
