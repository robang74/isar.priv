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

IMAGER_SCHROOT_SESSION_ID = "isar-imager-${SCHROOT_USER}-${PN}-${MACHINE}-${ISAR_BUILD_UUID}"

SSTATETASKS += "do_install_imager_deps"
SSTATECREATEFUNCS += "install_imager_deps_sstate_prepare"
SSTATEPOSTINSTFUNCS += "install_imager_deps_sstate_finalize"

install_imager_deps_sstate_prepare() {
    echo $PWD | grep -qe "install_imager_deps$" || return 0
    bbwarn "sstate_prepare\n\t pwd: $PWD\n\t pkg: ${SSTATE_PKG}\n\t zip:"\
        $(du -ms "${SCHROOT_OVERLAY_DIR}/upper.tar.zstd")
    mkdir -p $(dirname "${SSTATE_PKG}")
    cp -f "${SCHROOT_OVERLAY_DIR}/upper.tar.zstd" "${SSTATE_PKG}"
}

install_imager_deps_sstate_finalize() {
    echo $PWD | grep -qe "install_imager_deps$" || return 0
    bbwarn "sstate_finalize on $PWD\n\t found:"\
        $(du -ms ${SSTATE_PKG} 2>/dev/null ||:)
}

do_install_imager_deps_setscene[dirs] = "${SCHROOT_OVERLAY_DIR}"
python do_install_imager_deps_setscene() {
    rfsd = d.getVar("ROOTFSDIR", True) or bb.fatal("ROOTFSDIR is not defined")
    bb.warn("do_install_imager_deps_setscene\n\t rootfs: %s" % rfsd)
    try:
        sstate_setscene(d)
    except:
        return 0
}
addtask do_install_imager_deps_setscene before do_install_imager_deps after do_deploy_deb

#CLEANFUNCS = "clean_deploy"
#clean_deploy() {
#    rm -f "${DEPLOY_ISAR_BOOTSTRAP}"
#}

do_install_imager_deps[depends] = "${SCHROOT_DEP} isar-apt:do_cache_config"
do_install_imager_deps[deptask] = "do_deploy_deb"
do_install_imager_deps[lockfiles] += "${REPO_ISAR_DIR}/isar.lock"
do_install_imager_deps[network] = "${TASK_USE_NETWORK_AND_SUDO}"
do_install_imager_deps() {
    bbwarn "starts on ${SCHROOT_OVERLAY_DIR}\n\t rootfsdir: ${ROOTFSDIR}\n\t workdir: ${WORKDIR}"
    if [ -z "${@d.getVar("IMAGER_INSTALL", True).strip()}" ]; then
        sudo -E chroot ${SCHROOT_DIR} /usr/bin/apt-get -y clean
        return 0
    fi

    schroot -r -c ${session_id} "$@"

    set -e
if true; then
#   ( cd "${DEBDIR}/${distro}"
#       md5sum --quiet -c "${SSTATE_PKG}.md5sum" ||\
#           rm -f ${SCHROOT_OVERLAY_DIR}/upper.tar.zstd )
    if [ -e ${SCHROOT_OVERLAY_DIR}/upper.tar.zstd ]; then
        ( cd ${SCHROOT_OVERLAY_DIR}
          sudo unzstd ${ZSTD_OPTS} upper.tar.zstd -qfo upper.tar )
        bbwarn "upper found zip: "$(du -ms ${SCHROOT_OVERLAY_DIR}/upper.tar.zstd)
        bbwarn "upper found tar: "$(du -ms ${SCHROOT_OVERLAY_DIR}/upper.tar)
    else
        deb_dl_dir_import ${SCHROOT_DIR} ${distro}
        sudo rm -f ${SCHROOT_OVERLAY_DIR}/upper.tar
        export XZ_THREADS="${@d.getVar("XZ_THREADS", True).strip()}"
        bbwarn "do_install_imager_deps xz: ${XZ_THREADS}, overlay: ${SCHROOT_OVERLAY_DIR}\n\t" \
            "schroot: ${SCHROOT_DIR}"
        E="${@ isar_export_proxies(d)}"
    fi
fi
    schroot -r -c ${IMAGER_SCHROOT_SESSION_ID} -d / -u root -- sh -c ' \
        set -e
        cd ${SCHROOT_OVERLAY_DIR}
        if [ -e upper.tar ]; then
            trap "rm -f upper.tar" EXIT
            tar --strip-components=1 --same-owner -C / -xpSf upper.tar
        else
            apt-get -y update \
                -o Dir::Etc::SourceList="sources.list.d/isar-apt.list" \
                -o Dir::Etc::SourceParts="-" \
                -o APT::Get::List-Cleanup="0"
            export XZ_OPT="-T ${XZ_THREADS}"
            rm -rf /usr/share/man /usr/share/doc
            apt-get -o Debug::pkgProblemResolver=yes --no-install-recommends \
                --allow-unauthenticated --allow-downgrades -y install \
                --reinstall ${IMAGER_INSTALL}
        fi
'

if true; then
    if [ ! -e ${SCHROOT_OVERLAY_DIR}/upper.tar.zstd ]; then
        deb_dl_dir_export ${SCHROOT_DIR} ${distro}
        schroot -r -c ${IMAGER_SCHROOT_SESSION_ID} -d / -u root -- sh -c 'apt-get -y clean'
        sudo -E chroot ${SCHROOT_DIR} /usr/bin/apt-get -y clean

        overlaydir="${SCHROOT_OVERLAY_DIR}/${IMAGER_SCHROOT_SESSION_ID}"
        sudo tar --one-file-system ${ROOTFS_TAR_OPTS} -C ${overlaydir} \
                --exclude="usr/share/doc/" --exclude="usr/share/man" \
                -f ${SCHROOT_OVERLAY_DIR}/upper.tar.zstd upper
#       ( cd "${DEBDIR}/${distro}"; md5sum ${IMAGER_INSTALL} > "${SSTATE_PKG}.md5sum" )
#       sstate_create_package
        bbwarn "upper create dir: "$(sudo du -ms ${overlaydir}/upper)
        bbwarn "upper create tar: "$(du -ms ${SCHROOT_OVERLAY_DIR}/upper.tar.zstd)
    fi
fi
    sudo chown $(id -u):$(id -g) "${WORKDIR}"

    bbwarn "ends on ${SCHROOT_DIR} ${distro}"
}
addtask install_imager_deps before do_image_tools after do_start_imager_session

SCHROOT_MOUNTS = "${WORKDIR}:${PP_WORK} ${IMAGE_ROOTFS}:${PP_ROOTFS} ${DEPLOY_DIR_IMAGE}:${PP_DEPLOY}"

do_start_imager_session[dirs] = "${WORKDIR} ${IMAGE_ROOTFS} ${DEPLOY_DIR_IMAGE}"
do_start_imager_session[depends] = "${SCHROOT_DEP} isar-apt:do_cache_config"
do_start_imager_session[nostamp] = "1"
do_start_imager_session[network] = "${TASK_USE_SUDO}"
python do_start_imager_session() {
    import subprocess
    attempts=0
    while attempts < 2:
        attempts+=1
        bb.build.exec_func("schroot_create_configs", d)
        bb.build.exec_func("insert_mounts", d)
        sbuild_chroot = d.getVar("SBUILD_CHROOT", True)
        session_id = d.getVar("IMAGER_SCHROOT_SESSION_ID", True)
        try:
            bb.debug(2, "Opening schroot session %s" % sbuild_chroot)
            id = subprocess.run("schroot -d / -b -c %s -n %s -- printenv -0 SCHROOT_ALIAS_NAME"
                % (sbuild_chroot, session_id), shell=True, check=True)
            attempts=2
        except subprocess.CalledProcessError as err:
            try:
                bb.debug(2, "Reusing schroot session %s" % sbuild_chroot)
                id = subprocess.run("schroot -d / -r -c %s -- printenv -0 SCHROOT_ALIAS_NAME"
                    % session_id, shell=True, check=True)
            except subprocess.CalledProcessError as err:
                bb.debug(2, "Closing schroot session %s (%s)" % (sbuild_chroot, session_id))
                bb.build.exec_func("stop_schroot_session", d)
        if 'id' in locals():
            d.setVar("SBUILD_CHROOT", id)
}
addtask start_imager_session before do_stop_imager_session after do_rootfs_finalize

do_stop_imager_session[depends] = "${SCHROOT_DEP}"
do_stop_imager_session[nostamp] = "1"
do_stop_imager_session[network] = "${TASK_USE_SUDO}"
python do_stop_imager_session() {
    bb.build.exec_func("stop_schroot_session", d)
}
addtask stop_imager_session before do_deploy after do_image

imager_run() {
    imager_cleanup() {
        if id="$(schroot -d / -r -c ${IMAGER_SCHROOT_SESSION_ID} -- printenv -0 SCHROOT_ALIAS_NAME)"; then
            schroot -e -c ${IMAGER_SCHROOT_SESSION_ID}
            remove_mounts $id
            schroot_delete_configs $id
        fi
    }
    trap 'exit 1' INT HUP QUIT TERM ALRM USR1
    trap 'imager_cleanup' EXIT
    schroot -r -c ${IMAGER_SCHROOT_SESSION_ID} "$@"
}
