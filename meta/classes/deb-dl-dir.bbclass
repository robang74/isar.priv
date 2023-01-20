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
    chmod -R a+xr "${rootfs}/var/cache/apt/archives/partial" 2>/dev/null ||:
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
            sh -c ' mkdir -p "/deb-src/${1}/${2}" && cd "/deb-src/${1}/${2}" && apt-get -y --download-only --only-source source "$2"="$3" ' download-src "${rootfs_distro}" "${src}" "${version}"
    done
    ) 9>"${DEBSRCDIR}/${rootfs_distro}.lock"

    debsrc_undo_mounts "${rootfs}"
}

##### ##### ##### RAF REWORK ##### ##### #####

dl_print_num_debs() {
    bbwarn "$1 ${3:+$3 }$(sudo ls -1 "$2"/*.deb 2>/dev/null | wc -l || echo 0) debian packages"
}

deb_dl_dir_link_copy() {
    nol="${3}"
    apc="${2}/var/cache/apt/archives/"
    adn="${1}/var/cache/apt/archives/"
    bdn="${1}/var/lib/apt/lists/"
    bpc="${2}/var/lib/apt/lists/"
    export adn bdn apc bpc nol
    dl_print_num_debs "deb_dl_dir_link_export" "${apc}" apc
    dl_print_num_debs "deb_dl_dir_link_export" "${adn}" adn
    flock "${DEBDIR}".lock -c 'sudo -Es << EOSUDO
        set -ex
        mkdir -p "${apc}"
        sudo find "${adn}" -maxdepth 1 -type f \
            -iname "\*.deb" -exec ln -Pf -t "${apc}" {} +

        test "${nol}" = "nolists" && exit 0

        mkdir -p "${bpc}"
        find "${bdn}" -maxdepth 1 -type f -not -name "lock" \
            -not -name "_isar-apt\*" -exec ln -Pf -t "${bpc}" {} +
EOSUDO'
}

deb_dl_dir_link_import() {
    nol="${3}"
    apc="${DEBDIR}/${2}"
    adn="${1}/var/cache/apt/archives/"
    bdn="${1}/var/lib/apt/lists/"
    bpc="${DEBDIR}/lists/${2}"
    newer="../.export.newer"
    export adn bdn apc bpc nol newer
    dl_print_num_debs "deb_dl_dir_link_import" "${apc}" apc
    dl_print_num_debs "deb_dl_dir_link_import" "${adn}" adn
    flock -s "${DEBDIR}".lock -c 'sudo -Es << EOSUDO
        set -ex
        mkdir -p "${adn}"
        test -d "${apc}" && \
            sudo find "${apc}" -maxdepth 1 -type f \
                -iname "\*.deb" -exec ln -Pf -t "${adn}" {} +
        touch "${adn}/${newer}"

        test "${nol}" = "nolists" && exit 0

        mkdir -p "${bdn}"
        test -d "${bpc}" && \
            find "${bpc}" -maxdepth 1 -type f -not -name "lock" \
                -not -name "_isar-apt\*" -exec ln -Pf -t "${bdn}" {} +
        touch "${bdn}/${newer}"
EOSUDO'
}

deb_dl_dir_link_export() {
    nol="${3}"
    apc="${DEBDIR}/${2}"
    adn="${1}/var/cache/apt/archives/"
    bdn="${1}/var/lib/apt/lists/"
    bpc="${DEBDIR}/lists/${2}"
    newer="../.export.newer"
    export adn bdn apc bpc nol newer
    dl_print_num_debs "deb_dl_dir_link_export" "${apc}" apc
    dl_print_num_debs "deb_dl_dir_link_export" "${adn}" adn
    flock "${DEBDIR}".lock -c 'sudo -Es << EOSUDO
        set -ex
        mkdir -p "${apc}"
        sudo find "${adn}" -maxdepth 1 -type f -iname "\*.deb" \
            -newer "${adn}/${newer}" -exec ln -Pf -t "${apc}" {} +

        test "${nol}" = "nolists" && exit 0

        mkdir -p "${bpc}"
        find "${bdn}" -maxdepth 1 -type f -not -name "lock" \
            -not -name "_isar-apt\*" -newer "${bdn}/${newer}" \
                -exec ln -Pf -t "${bpc}" {} +
EOSUDO'
}

deb_dl_dir_bind_import() {
    nol="${3}"
    apc="${DEBDIR}/${2}"
    adn="${1}/var/cache/apt/archives/"
    bdn="${1}/var/lib/apt/lists/"
    bpc="${DEBDIR}/lists/${2}"
    newer="../.export.newer"
    export adn bdn apc bpc nol newer
    dl_print_num_debs "deb_dl_dir_bind_import" "${apc}" apc
    dl_print_num_debs "deb_dl_dir_bind_import" "${adn}" adn
    flock -s "${DEBDIR}".lock -c 'sudo -Es << EOSUDO
        set -e
        mkdir -p "${adn}" "${apc}/partial"
        mount -o bind "${apc}" "${adn}"

        test "${nol}" = "nolists" && exit 0

        mkdir -p "${bdn}"
        test -d "${bpc}" && \
            find "${bpc}" -maxdepth 1 -type f -not -name "lock" -not -name \
                "_isar-apt\*" -exec ln -Pf -t "${bdn}" {} +
        touch "${bdn}/${newer}"
EOSUDO' || exit 1
    bbwarn "deb_dl_dir_bind_import mounts: $(mount | grep "/apt/" | wc -l || echo 0)"
}

deb_dl_dir_bind_export() {
    nol="${3}"
    apc="${DEBDIR}/${2}"
    adn="${1}/var/cache/apt/archives/"
    bdn="${1}/var/lib/apt/lists/"
    bpc="${DEBDIR}/lists/${2}"
    newer="../.export.newer"
    export adn bdn apc bpc nol newer
    dl_print_num_debs "deb_dl_dir_bind_export" "${apc}" apc
    dl_print_num_debs "deb_dl_dir_bind_export" "${adn}" adn
    flock "${DEBDIR}".lock -c 'sudo -Es << EOSUDO
        set -e
        umount -l "${adn}"

        test "${nol}" = "nolists" && exit 0

        mkdir -p "${bpc}"
        find "${bdn}" -maxdepth 1 -type f -not -name "lock" -not -name \
            "_isar-apt\*" -newer "${bdn}/${newer}" -exec \
                ln -Pf -t "${bpc}" {} +
        true
EOSUDO' || exit 1
    bbwarn "deb_dl_dir_bind_export mounts: $(mount | grep "/apt/" | wc -l || echo 0)"
}

deb_dl_dir_import() {
    if [ "$(basename $1)" = "upper" ]; then
        deb_dl_dir_link_import "$@"
    else
        deb_dl_dir_bind_import "$@"
    fi
}

deb_dl_dir_export() {
    if [ "$(basename $1)" = "upper" ]; then
        deb_dl_dir_link_export "$@"
    else
        deb_dl_dir_bind_export "$@"
    fi
}
