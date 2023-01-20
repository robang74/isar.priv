# This software is a part of ISAR.
# Copyright (C) 2015-2018 ilbers GmbH

inherit dpkg-base

ISAR_CROSS_COMPILE ?= "0"

PACKAGE_ARCH ?= "${DISTRO_ARCH}"

DPKG_PREBUILD_ENV_FILE="${WORKDIR}/dpkg_prebuild.env"

# bitbake variables that should be passed into sbuild env
# Note: must not have any logical influence on the generated package
SBUILD_PASSTHROUGH_ADDITIONS ?= ""

def expand_sbuild_pt_additions(d):
    cmds = ''
    for var in d.getVar('SBUILD_PASSTHROUGH_ADDITIONS', True).split():
        varval = d.getVar(var, True)
        if varval != None:
            cmds += 'sbuild_export ' + var + ' "' + varval + '"\n'
    return cmds

do_prepare_build_append() {
    env > ${DPKG_PREBUILD_ENV_FILE}
}

DPKG_SBUILD_EXTRA_ARGS ?= ""

# Build package from sources using build script
dpkg_runbuild[vardepsexclude] += "${SBUILD_PASSTHROUGH_ADDITIONS}"
dpkg_runbuild() {
    E="${@ isar_export_proxies(d)}"
    E="${@ isar_export_ccache(d)}"
    export DEB_BUILD_OPTIONS="${@ isar_deb_build_options(d)}"
    export PARALLEL_MAKE="${PARALLEL_MAKE}"

    rm -f ${SBUILD_CONFIG}

    env | while read -r line; do
        # Filter the same lines
        grep -q "^${line}" ${DPKG_PREBUILD_ENV_FILE} && continue
        # Filter some standard variables
        echo ${line} | grep -q "^HOME=" && continue
        echo ${line} | grep -q "^PWD=" && continue

        var=$(echo "${line}" | cut -d '=' -f1)
        value=$(echo "${line}" | cut -d '=' -f2-)
        sbuild_export $var "$value"

        # Don't warn some variables
        [ "${var}" = "PARALLEL_MAKE" ] && continue
        [ "${var}" = "CCACHE_DIR" ] && continue
        [ "${var}" = "CCACHE_DEBUGDIR" ] && continue
        [ "${var}" = "CCACHE_DEBUG" ] && continue
        [ "${var}" = "CCACHE_DISABLE" ] && continue
        [ "${var}" = "PATH_PREPEND" ] && continue
        [ "${var}" = "DEB_BUILD_OPTIONS" ] && continue

        [ "${var}" = "http_proxy" ] && continue
        [ "${var}" = "HTTP_PROXY" ] && continue
        [ "${var}" = "https_proxy" ] && continue
        [ "${var}" = "HTTPS_PROXY" ] && continue
        [ "${var}" = "ftp_proxy" ] && continue
        [ "${var}" = "FTP_PROXY" ] && continue
        [ "${var}" = "no_proxy" ] && continue
        [ "${var}" = "NO_PROXY" ] && continue

        bbwarn "Export of '${line}' detected, please migrate to templates"
    done

    distro="${BASE_DISTRO}-${BASE_DISTRO_CODENAME}"
    if [ ${ISAR_CROSS_COMPILE} -eq 1 ]; then
        distro="${HOST_BASE_DISTRO}-${BASE_DISTRO_CODENAME}"
    fi

    deb_dir="/var/cache/apt/archives"
    ext_root="${PP}/rootfs"
    ext_deb_dir="${ext_root}${deb_dir}"

    profiles="${@ isar_deb_build_profiles(d)}"
    if [ ! -z "$profiles" ]; then
        profiles=$(echo --profiles="$profiles" | sed -e 's/ \+/,/g')
    fi

    export SBUILD_CONFIG="${SBUILD_CONFIG}"

    for envvar in http_proxy HTTP_PROXY https_proxy HTTPS_PROXY \
        ftp_proxy FTP_PROXY no_proxy NO_PROXY; do
        sbuild_add_env_filter "$envvar"
    done
    ${@ expand_sbuild_pt_additions(d)}

    echo '$apt_keep_downloaded_packages = 1;' >> ${SBUILD_CONFIG}
    bbwarn "after import 2"

    # Create a .dsc file from source directory to use it with sbuild
    DEB_SOURCE_NAME=$(dpkg-parsechangelog --show-field Source --file ${WORKDIR}/${PPS}/debian/changelog)
    sudo find ${WORKDIR} -name "${DEB_SOURCE_NAME}*.dsc" -type f -delete
    bbwarn "after import 3"
    sh -c "cd ${WORKDIR}; dpkg-source -q -b ${PPS}"
    DSC_FILE=$(sudo find ${WORKDIR} -name "${DEB_SOURCE_NAME}*.dsc" -type f -print)

    bbwarn "after import 4"
    if [ ${USE_CCACHE} -eq 1 ]; then
        deb_dl_dir_import "${WORKDIR}/rootfs" "${distro}"
        schroot_configure_ccache
    else
        deb_dl_dir_import "${WORKDIR}/rootfs" "${distro}" nolists
    fi
    bbwarn "after import 1"

    rootfs_delete_but_not_archives() {
        set -e
        local archives="${WORKDIR}/rootfs/var/cache/apt/archives"
        if mountpoint -q "${archives}"; then
            sudo chmod -R a+r "${archives}"/partial
            sudo mv $(dirname $archives) $(mktemp -dp ${WORKDIR} apt.XXXX)
            return $?
        fi
        return 0
    }

    bbwarn "before sbuild"
    sbuild -A -n -c ${SBUILD_CHROOT} --extra-repository="${ISAR_APT_REPO}" \
        --host=${PACKAGE_ARCH} --build=${SBUILD_HOST_ARCH} ${profiles} \
        --no-run-lintian --no-run-piuparts --no-run-autopkgtest --resolve-alternatives \
        --no-apt-update \
        --chroot-setup-commands="echo \"Package: *\nPin: release n=${DEBDISTRONAME}\nPin-Priority: 1000\" > /etc/apt/preferences.d/isar-apt" \
        --chroot-setup-commands="echo \"APT::Get::allow-downgrades 1;\" > /etc/apt/apt.conf.d/50isar-apt" \
        --chroot-setup-commands="rm -f /var/log/dpkg.log" \
        --chroot-setup-commands="mount -o bind ${ext_deb_dir} ${deb_dir}" \
        --finished-build-commands="umount -l ${deb_dir}" \
        --finished-build-commands="rm -f ${deb_dir}/sbuild-build-depends-main-dummy_*.deb" \
        --finished-build-commands="cp /var/log/dpkg.log ${ext_root}/dpkg_partial.log" \
        --debbuildopts="--source-option=-I" ${DPKG_SBUILD_EXTRA_ARGS} \
        --build-dir=${WORKDIR} --dist="isar" ${DSC_FILE}
    bbwarn "after sbuild"

    sbuild_dpkg_log_export "${WORKDIR}/rootfs/dpkg_partial.log"
    if [ ${USE_CCACHE} -eq 1 ]; then
        deb_dl_dir_export "${WORKDIR}/rootfs" "${distro}"
    else
        deb_dl_dir_export "${WORKDIR}/rootfs" "${distro}" nolists
    fi
    rootfs_delete_but_not_archives
}
