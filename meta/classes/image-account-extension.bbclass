# This software is a part of ISAR.
# Copyright (C) Siemens AG, 2019
#
# SPDX-License-Identifier: MIT
#
# This class extends the image.bbclass for creating user accounts and groups.

USERS ??= ""

#USERS += "root"
#USER_root[password] = "" # Encrypted password, or clear-text when [flags] = "clear-text-password"
#USER_root[expire] = ""
#USER_root[inactive] = ""
#USER_root[uid] = ""
#USER_root[gid] = "" # If first character is a number: gid, otherwise groupname
#USER_root[comment] = "The ultimate root user"
#USER_root[home] = "/home/root"
#USER_root[shell] = "/bin/sh"
#USER_root[groups] = "audio video"
#USER_root[flags] = "no-create-home create-home system allow-empty-password clear-text-password force-passwd-change"

GROUPS ??= ""

#GROUPS += "root"
#GROUP_root[gid] = ""
#GROUP_root[flags] = "system"

def gen_accounts_array(d, listname, entryname, flags, verb_flags=None):
    from itertools import chain

    entries = (d.getVar(listname, True) or "").split()
    return " ".join(
        ":".join(
            chain(
                (entry,),
                (
                    (",".join(
                        (
                            d.getVarFlag(entryname + "_" + entry, flag, True) or ""
                        ).split()
                    ) if flag not in (verb_flags or []) else (
                        d.getVarFlag(entryname + "_" + entry, flag, True) or ""
                    )).replace(":","=")
                    for flag in flags
                ),
            )
        )
        for entry in entries
    )

# List of space separated entries, where each entry has the format:
# username:encryptedpassword:expiredate:inactivenumber:userid:groupid:comment:homedir:shell:group1,group2:flag1,flag2
IMAGE_ACCOUNTS_USERS =+ "${@gen_accounts_array(d, 'USERS', 'USER', ['password',  'expire', 'inactive', 'uid', 'gid', 'comment', 'home', 'shell', 'groups', 'flags'], ['password', 'comment', 'home', 'shell'])}"

# List of space separated entries, where each entry has the format:
# groupname:groupid:flag1,flag2
IMAGE_ACCOUNTS_GROUPS =+ "${@gen_accounts_array(d, 'GROUPS', 'GROUP', ['gid', 'flags'])}"

do_rootfs_install[vardeps] += "${IMAGE_ACCOUNTS_GROUPS} ${IMAGE_ACCOUNTS_USERS}"

ROOTFS_POSTPROCESS_COMMAND += "image_postprocess_accounts"
image_postprocess_accounts() {
    # Create groups
    # Add space to the end of the list:
    list='${@" ".join(d.getVar('IMAGE_ACCOUNTS_GROUPS', True).split())} '
    while true; do
        # Pop first group entry:
        list_rest="${list#*:*:* }"
        entry="${list%%${list_rest}}"
        list="${list_rest}"

        if [ -z "${entry}" ]; then
            break
        fi

        # Add colon to the end of the entry and remove trailing space:
        entry="${entry% }:"

        # Decode entries:
        name="${entry%%:*}"
        entry="${entry#${name}:}"

        gid="${entry%%:*}"
        entry="${entry#${gid}:}"

        flags="${entry%%:*}"
        entry="${entry#${flags}:}"

        flags=",${flags}," # Needed for searching for substrings

        # Check if user already exists:
        if grep -q "^${name}:" '${ROOTFSDIR}/etc/group'; then
            exists="y"
        else
            exists="n"
        fi

        # Create arguments:
        set -- # clear arguments

        if [ -n "$gid" ]; then
            set -- "$@" --gid "$gid"
        fi

        if [ "n" = "$exists" ]; then
            if [ "${flags}" != "${flags%*,system,*}" ]; then
                set -- "$@" --system
            fi
        fi

        # Create or modify groups:
        if [ "y" = "$exists" ]; then
            if [ -z "$@" ]; then
                echo "Do not execute groupmod (no changes)."
            else
                echo "Execute groupmod with \"$@\" for \"$name\""
                sudo -E chroot '${ROOTFSDIR}' \
                    /usr/sbin/groupmod "$@" "$name"
            fi
        else
            echo "Execute groupadd with \"$@\" for \"$name\""
            sudo -E chroot '${ROOTFSDIR}' \
                /usr/sbin/groupadd "$@" "$name"
        fi
    done

    # Create users
    list='${@" ".join(d.getVar('IMAGE_ACCOUNTS_USERS', True).split())} '
    while true; do
        # Pop first user entry:
        list_rest="${list#*:*:*:*:*:*:*:*:*:*:* }"
        entry="${list%%${list_rest}}"
        list="${list_rest}"

        if [ -z "${entry}" ]; then
            break
        fi

        # Add colon to the end of the entry and remove trailing space:
        entry="${entry% }:"

        # Decode entries:
        name="${entry%%:*}"
        entry="${entry#${name}:}"

        password="${entry%%:*}"
        entry="${entry#${password}:}"

        expire="${entry%%:*}"
        entry="${entry#${expire}:}"

        inactive="${entry%%:*}"
        entry="${entry#${inactive}:}"

        uid="${entry%%:*}"
        entry="${entry#${uid}:}"

        gid="${entry%%:*}"
        entry="${entry#${gid}:}"

        comment="${entry%%:*}"
        entry="${entry#${comment}:}"

        home="${entry%%:*}"
        entry="${entry#${home}:}"

        shell="${entry%%:*}"
        entry="${entry#${shell}:}"

        groups="${entry%%:*}"
        entry="${entry#${groups}:}"

        flags="${entry%%:*}"
        entry="${entry#${flags}:}"

        flags=",${flags}," # Needed for searching for substrings

        # Check if user already exists:
        if grep -q "^${name}:" '${ROOTFSDIR}/etc/passwd'; then
            exists="y"
        else
            exists="n"
        fi

        # Create arguments:
        set -- # clear arguments

        if [ -n "$expire" ]; then
            set -- "$@" --expiredate "$expire"
        fi

        if [ -n "$inactive" ]; then
            set -- "$@" --inactive "$inactive"
        fi

        if [ -n "$uid" ]; then
            set -- "$@" --uid "$uid"
        fi

        if [ -n "$gid" ]; then
            set -- "$@" --gid "$gid"
        fi

        if [ -n "$comment" ]; then
            set -- "$@" --comment "$comment"
        fi

        if [ -n "$home" ]; then
            if [ "y" = "$exists" ]; then
                set -- "$@" --home "$home" --move-home
            else
                set -- "$@" --home-dir "$home"
            fi
        fi

        if [ -n "$shell" ]; then
            set -- "$@" --shell "$shell"
        fi

        if [ -n "$groups" ]; then
            set -- "$@" --groups "$groups"
        fi

        if [ "n" = "$exists" ]; then
            if [ "${flags}" != "${flags%*,system,*}" ]; then
                set -- "$@" --system
            fi
            if [ "${flags}" != "${flags%*,no-create-home,*}" ]; then
                set -- "$@" --no-create-home
            else
                if [ "${flags}" != "${flags%*,create-home,*}" ]; then
                    set -- "$@" --create-home
                fi
            fi
        fi

        # Create or modify users:
        if [ "y" = "$exists" ]; then
            if [ -z "$@" ]; then
                echo "Do not execute usermod (no changes)."
            else
                echo "Execute usermod with \"$@\" for \"$name\""
                sudo -E chroot '${ROOTFSDIR}' \
                    /usr/sbin/usermod "$@" "$name"
            fi
        else
            echo "Execute useradd with \"$@\" for \"$name\""
            sudo -E chroot '${ROOTFSDIR}' \
                /usr/sbin/useradd "$@" "$name"
        fi

        # Set password:
        if [ -n "$password" -o "${flags}" != "${flags%*,allow-empty-password,*}" ]; then
            chpasswd_args="-e"
            if [ "${flags}" != "${flags%*,clear-text-password,*}" ]; then
                # chpasswd adds a random salt when running against a clear-text password.
                # For reproducible images, we manually generate the password and use the
                # SOURCE_DATE_EPOCH to generate the salt in a deterministic way.
                if [ -z "${SOURCE_DATE_EPOCH}"]; then
                    chpasswd_args=""
                else
                    salt="$(echo "${SOURCE_DATE_EPOCH}" | sha256sum -z | cut -c 1-15)"
                    password="$(openssl passwd -6 -salt $salt "$password")"
                fi
            fi
            printf '%s:%s' "$name" "$password" | sudo chroot '${ROOTFSDIR}' \
                /usr/sbin/chpasswd $chpasswd_args
        fi
        if [ "${flags}" != "${flags%*,force-passwd-change,*}" ]; then
            echo "Execute passwd to force password change on first boot for \"$name\""
            sudo -E chroot '${ROOTFSDIR}' \
                /usr/bin/passwd --expire "$name"
        fi
    done
}
