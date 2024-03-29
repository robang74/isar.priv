# This software is a part of ISAR.
# Copyright (C) 2020 Siemens AG
#
# Partial rework by Roberto A. Foglietta <roberto.foglietta@gmail.com>
#
# SPDX-License-Identifier: MIT

inherit repository

is_not_part_of_current_build() {
    local package="$( dpkg-deb --show --showformat '${Package}' "${1}" )"
    local arch="$( dpkg-deb --show --showformat '${Architecture}' "${1}" )"
    local version="$( dpkg-deb --show --showformat '${Version}' "${1}" )"
    # Since we are parsing all the debs in DEBDIR, we can to some extend
    # try to eliminate some debs that are not part of the current multiconfig
    # build using the below method.
    local output="$( grep -xhs ".* status installed ${package}:${arch} ${version}" \
            "${IMAGE_ROOTFS}"/var/log/dpkg.log \
            "${SCHROOT_HOST_DIR}"/var/log/dpkg.log \
            "${SCHROOT_TARGET_DIR}"/var/log/dpkg.log \
            "${SCHROOT_HOST_DIR}"/tmp/dpkg_common.log \
            "${SCHROOT_TARGET_DIR}"/tmp/dpkg_common.log \
            "${BUILDCHROOT_HOST_DIR}"/var/log/dpkg.log \
            "${BUILDCHROOT_TARGET_DIR}"/var/log/dpkg.log | head -1 )"

    [ -z "${output}" ]
}

debsrc_do_mounts() {
    sudo -s <<EOSUDO
    set -e
    mkdir -p "${1}/deb-src"
    mountpoint -q "${1}/deb-src" || \
    mount --bind "${DEBSRCDIR}" "${1}/deb-src"
EOSUDO
}

debsrc_undo_mounts() {
    sudo -s <<EOSUDO
    set -e
    mkdir -p "${1}/deb-src"
    mountpoint -q "${1}/deb-src" && \
    umount -l "${1}/deb-src"
    rm -rf "${1}/deb-src"
EOSUDO
}

debsrc_download() {
    export rootfs="$1"
    export rootfs_distro="$2"
    mkdir -p "${DEBSRCDIR}"/"${rootfs_distro}"

    debsrc_do_mounts "${rootfs}"

    ( flock 9
    set -e
    sudo find "${rootfs}/var/cache/apt/archives/" -maxdepth 1 -type f -iname '*\.deb' | while read package; do
        is_not_part_of_current_build "${package}" && continue
        # Get source package name if available, fallback to package name
        local src="$( dpkg-deb --field "${package}" Source | awk '{printf $1}' )"
        [ -z "$src" ] && src="$( dpkg-deb --field "${package}" Package )"
        # Get source package version if available, fallback to package version
        local version="$( dpkg-deb --field "${package}" Source |  awk '{gsub(/[()]/,""); printf $2}')"
        [ -z "$version" ] && version="$( dpkg-deb --field "${package}" Version )"
        # TODO: get back to the code below when debian bug #1004372 is fixed
        # local src="$( dpkg-deb --show --showformat '${source:Package}' "${package}" )"
        # local version="$( dpkg-deb --show --showformat '${source:Version}' "${package}" )"
        local dscname="$(echo ${src}_${version} | sed -e 's/_[0-9]\+:/_/')"
        local dscfile=$(find "${DEBSRCDIR}"/"${rootfs_distro}" -name "${dscname}.dsc")
        [ -n "$dscfile" ] && continue

        sudo -E chroot --userspec=$( id -u ):$( id -g ) ${rootfs} \
            sh -c ' mkdir -p "/deb-src/${1}/${2}" && cd "/deb-src/${1}/${2}" && apt-get -y --download-only \
                    --only-source source "$2"="$3" ' download-src "${rootfs_distro}" "${src}" "${version}"
    done
    ) 9>"${DEBSRCDIR}/${rootfs_distro}.lock"

    debsrc_undo_mounts "${rootfs}"
}

##### REWORK #####

deb_dl_dir_import() {
    nol="${3}"
    apc="${DEBDIR}/${2}"
    adn="${1}/var/cache/apt/archives/"
    bdn="${1}/var/lib/apt/lists/"
    bpc="${DEBDIR}/lists/${2}"
    mro=""
    test "$3" = "readonly" && mro="-r"
    export adn bdn apc bpc nol mro
    trap "sudo umount -l '${adn}'; sudo umount -l '${bdn}'" EXIT
    bbwarn "deb_dl_dir_import "$(sudo du -ms $apc | cut -f1)" Mb\n\t"\
        "apc: $apc\n\t adn: $adn\n\t bdn: ${bdn}\n\t bpc: ${bpc}"
    flock -Fs "${DEBDIR}".lock sudo -Es << 'EOSUDO'
        mkdir -p "${apc}" "${adn}"
        if ! mountpoint -q "${adn}"; then
            if ! mount ${mro} -o bind "${apc}" "${adn}"; then
                exit 1
            fi
        fi

        test "${nol}" = "nolists" && exit 0

        mkdir -p "${bdn}" "${bpc}"
        if ! mountpoint -q "${bdn}"; then
            if ! mount ${mro} -o bind "${bpc}" "${bdn}"; then
                exit 1
            fi
        fi
EOSUDO
}

deb_dl_dir_export() {
    set -e
    nol="${3}"
    apc="${DEBDIR}/${2}"
    adn="${1}/var/cache/apt/archives/"
    bdn="${1}/var/lib/apt/lists/"
    bpc="${DEBDIR}/lists/${2}"
    export adn bdn apc bpc nol
    bbwarn "deb_dl_dir_export "$(sudo du -ms $apc | cut -f1)" Mb\n\t apc: $apc\n\t adn: $adn"
    flock -F "${DEBDIR}".lock sudo -Es << 'EOSUDO'
        mountpoint -q "${adn}" && umount -l "${adn}"

        test "${nol}" = "nolists" && exit 0

        mountpoint -q "${bdn}" && umount -l "${bdn}"
EOSUDO
}

pigz_replaces_gzip() {
    set -e
    test -d "$1"
    cd $1
    if [ -e usr/bin/pigz ]; then
        bbwarn "pigz_replaces_gzip pigz found"
        for i in '' 'un'; do
            if [ -f usr/bin/${i}gzip ]; then
                sudo ln -Pf /usr/bin/${i}gzip usr/bin/${i}gzip.orig 2>/dev/null ||:
                sudo ln -sf ${i}pigz usr/bin/${i}gzip
            fi
        done
    else
        bbwarn "pigz_replaces_gzip pigz is missing"
        return 1
    fi
}
