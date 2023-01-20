# This software is a part of ISAR.
# Copyright (C) Siemens AG, 2019
#
# SPDX-License-Identifier: MIT
#
# This class extends the image.bbclass for setting locales and purging unneeded
# ones.

LOCALE_GEN ?= "en_US.UTF-8 UTF-8\n\
               en_US ISO-8859-1\n"
LOCALE_DEFAULT ?= "en_US.UTF-8"

def get_locale_gen(d, sep='\n'):
    locale_gen = d.getVar("LOCALE_GEN", True) or ""
    return sep.join(sorted(set(i.strip()
                               for i in locale_gen.split('\\n')
                               if i.strip())))

def get_nopurge(d):
    locale_gen = d.getVar("LOCALE_GEN", True) or ""
    return '\n'.join(sorted(set(i.strip()
                                for j in locale_gen.split('\\n')
                                if j.strip()
                                for i in (j.split()[0].split("_")[0],
                                          j.split()[0].split(".")[0],
                                          j.split()[0]))))

#ROOTFS_INSTALL_COMMAND_BEFORE_EXPORT += "image_install_localepurge_download"
image_install_localepurge_download[weight] = "40"
image_install_localepurge_download() {
    sudo -E chroot '${ROOTFSDIR}' \
        /usr/bin/apt-get ${ROOTFS_APT_ARGS} --download-only localepurge
}

ROOTFS_INSTALL_COMMAND_BEFORE_EXPORT += "image_install_localepurge_install"
image_install_localepurge_install[weight] = "350"
image_install_localepurge_install() {

    bbwarn "image_install_localepurge_install 2 deb: $(ls -1 ${ROOTFSDIR}/var/cache/apt/archives/*.deb 2>/dev/null | wc -l ||:)"

    # Generate locale and localepurge configuration:
    cat<<__EOF__ > ${WORKDIR}/locale.gen
${@get_locale_gen(d)}
__EOF__
    cat<<__EOF__ > ${WORKDIR}/locale.debconf
locales     locales/locales_to_be_generated    multiselect ${@get_locale_gen(d, ', ')}
locales     locales/default_environment_locale select      ${LOCALE_DEFAULT}
__EOF__
    cat<<__EOF__ > ${WORKDIR}/locale.default
LANG=${LOCALE_DEFAULT}
__EOF__
    cat<<__EOF__ > ${WORKDIR}/locale.nopurge
#USE_DPKG
MANDELETE
DONTBOTHERNEWLOCALE
#SHOWFREEDSPACE
#QUICKNDIRTYCALC
#VERBOSE
${@get_nopurge(d)}
__EOF__

    # Install configuration into image:
    sudo -E -s <<'EOSUDO'
        set -e
        localepurge_state='i'
        if chroot '${ROOTFSDIR}' dpkg -s localepurge 2>/dev/null >&2
        then
#           echo 'localepurge was installed (leaving it installed later)'
            echo i >localepurge.state
        else
#           echo 'localepurge was not installed (removing it later)'
            chroot '${ROOTFSDIR}' apt-get ${ROOTFS_APT_ARGS} localepurge
            echo p >localepurge.state
        fi

        cat '${WORKDIR}/locale.gen' >> '${ROOTFSDIR}/etc/locale.gen'
        cat '${WORKDIR}/locale.default' > '${ROOTFSDIR}/etc/default/locale'
        cat '${WORKDIR}/locale.nopurge' > '${ROOTFSDIR}/etc/locale.nopurge'
        cat '${WORKDIR}/locale.debconf' > '${ROOTFSDIR}/tmp/locale.debconf'

        # Enter image and trigger locales config and localepurge:
        chroot '${ROOTFSDIR}' /bin/sh <<'EOSH'
            set -e

#           echo 'running locale debconf-set-selections'
            debconf-set-selections /tmp/locale.debconf
            rm -f '/tmp/locale.debconf'

            SYSTEMD_VERSION=$(dpkg-query \
                --showformat='${source:Upstream-Version}' \
                --show systemd || echo "0" )

            if dpkg --compare-versions "$SYSTEMD_VERSION" "ge" "251"; then
                ln -s /etc/default/locale /etc/locale.conf
            fi

#           echo 'reconfigure locales'
            dpkg-reconfigure -f noninteractive locales

#           echo 'running localepurge'
#           localepurge
EOSH
EOSUDO

    bbwarn "image_install_localepurge_install 2 deb: $(ls -1 ${ROOTFSDIR}/var/cache/apt/archives/*.deb 2>/dev/null | wc -l ||:)"
}

ROOTFS_INSTALL_COMMAND += "image_install_localepurge_execute"
image_install_localepurge_execute[weight] = "350"
image_install_localepurge_execute() {
        set -e
        sudo chroot '${ROOTFSDIR}' localepurge

        if [ "$(cat localepurge.state)" == 'p' ]
        then
#           echo removing localepurge...
            sudo chroot '${ROOTFSDIR}' apt-get purge --yes localepurge
            sudo chroot '${ROOTFSDIR}' apt-get autoremove --purge --yes
        fi
        sudo rm -f localepurge.state
}
