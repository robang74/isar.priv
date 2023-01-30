# This software is a part of ISAR.
# Copyright (C) Siemens AG, 2019
#
# SPDX-License-Identifier: MIT
#
# This file extends the image.bbclass to supply tools for futher imager functions

inherit sbuild

IMAGER_INSTALL ??= ""
IMAGER_BUILD_DEPS ??= ""
DEPENDS += "${IMAGER_BUILD_DEPS}"

SCHROOT_MOUNTS = "${WORKDIR}:${PP_WORK} ${IMAGE_ROOTFS}:${PP_ROOTFS} ${DEPLOY_DIR_IMAGE}:${PP_DEPLOY}"
SCHROOT_MOUNTS += "${REPO_ISAR_DIR}/${DISTRO}:/isar-apt"

imager_run() {
    schroot_create_configs
    insert_mounts

    local_install="${@(d.getVar("INSTALL_%s" % d.getVar("BB_CURRENTTASK"), True) or '').strip()}"

    session_id=$(schroot -q -b -c ${SBUILD_CHROOT})
    echo "Started session: ${session_id}"

    # setting up error handler
    imager_cleanup() {
        set +e
        schroot -q -f -e -c ${session_id} > /dev/null 2>&1
        remove_mounts > /dev/null 2>&1
        schroot_delete_configs > /dev/null 2>&1
    }
    trap 'exit 1' INT HUP QUIT TERM ALRM USR1
    trap 'imager_cleanup' EXIT

    if [ -n "${local_install}" ]; then
        echo "Installing imager deps: ${local_install}"

        distro="${BASE_DISTRO}-${BASE_DISTRO_CODENAME}"
        if [ ${ISAR_CROSS_COMPILE} -eq 1 ]; then
            distro="${HOST_BASE_DISTRO}-${BASE_DISTRO_CODENAME}"
        fi

        # prepare isar-apt
        schroot -r -c ${session_id} -d / -u root -- sh -c " \
            mkdir -p '/etc/apt/sources.list.d'
            echo 'deb [trusted=yes] file:///isar-apt ${DEBDISTRONAME} main' > \
                '/etc/apt/sources.list.d/isar-apt.list'

            mkdir -p '/etc/apt/preferences.d'
            cat << EOF > '/etc/apt/preferences.d/isar-apt'
Package: *
Pin: release n=${DEBDISTRONAME}
Pin-Priority: 1000
EOF"

        E="${@ isar_export_proxies(d)}"
        deb_dl_dir_import ${SCHROOT_DIR} ${distro}
        schroot -r -c ${session_id} -d / -u root -- sh -c " \
            apt-get update \
                -o Dir::Etc::SourceList='sources.list.d/isar-apt.list' \
                -o Dir::Etc::SourceParts='-' \
                -o APT::Get::List-Cleanup='0'
            apt-get -o Debug::pkgProblemResolver=yes --no-install-recommends -y \
                --allow-unauthenticated --allow-downgrades --download-only install \
                ${local_install}"

        deb_dl_dir_export ${SCHROOT_DIR} ${distro}
        schroot -r -c ${session_id} -d / -u root -- sh -c " \
            apt-get -o Debug::pkgProblemResolver=yes --no-install-recommends -y \
                --allow-unauthenticated --allow-downgrades install \
                ${local_install}"
    fi

    schroot -r -c ${session_id} "$@"

    schroot -e -c ${session_id}

    schroot_delete_configs

    E="${@ isar_export_proxies(d)}"
    deb_dl_dir_import ${BUILDCHROOT_DIR} ${distro}
    sudo -E chroot ${BUILDCHROOT_DIR} sh -c ' \
        apt-get update \
            -o Dir::Etc::SourceList="sources.list.d/isar-apt.list" \
            -o Dir::Etc::SourceParts="-" \
            -o APT::Get::List-Cleanup="0"
        apt-get -o Debug::pkgProblemResolver=yes --no-install-recommends -y \
            --allow-unauthenticated --allow-downgrades --download-only install \
            --reinstall ${IMAGER_INSTALL}'

    deb_dl_dir_export ${BUILDCHROOT_DIR} ${distro}
    sudo -E chroot ${BUILDCHROOT_DIR} sh -c ' \
        apt-get -o Debug::pkgProblemResolver=yes --no-install-recommends -y \
            --allow-unauthenticated --allow-downgrades install \
            --reinstall ${IMAGER_INSTALL}'
}
