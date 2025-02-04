#!/bin/bash

# called by dracut
check() {
    require_binaries ip sed awk grep pgrep tr expr || return 1

    require_any_binary arping arping2 wicked || return 1
    require_any_binary dhclient wicked || return 1

    return 255
}

# called by dracut
depends() {
    echo bash
    return 0
}

# called by dracut
installkernel() {
    return 0
}

# called by dracut
install() {
    local _arch

    #Adding default link
    if dracut_module_included "systemd"; then
        inst_multiple -o "${systemdutildir}/network/99-default.link"
        [[ $hostonly ]] && inst_multiple -H -o "${systemdsystemconfdir}/network/*.link"
    fi

    inst_multiple ip sed awk grep pgrep tr expr
    inst -o dhclient

    inst_multiple -o arping arping2
    if command -v arping > /dev/null; then
        strstr "$(arping 2>&1)" "ARPing 2" && mv "$initdir/bin/arping" "$initdir/bin/arping2"
    fi
    inst_multiple -o wicked
    inst_multiple -o ping ping6
    inst_multiple -o teamd teamdctl teamnl
    inst_simple /etc/libnl/classid
    inst_script "$moddir/ifup.sh" "/sbin/ifup"
    inst_script "$moddir/dhcp-multi.sh" "/sbin/dhcp-multi.sh"
    inst_script "$moddir/dhclient-script.sh" "/sbin/dhclient-script"
    inst_simple -H "/etc/dhclient.conf"
    cat "$moddir/dhclient.conf" >> "${initdir}/etc/dhclient.conf"
    inst_hook pre-udev 60 "$moddir/net-genrules.sh"
    inst_hook cmdline 92 "$moddir/parse-ibft.sh"
    inst_hook cmdline 95 "$moddir/parse-vlan.sh"
    inst_hook cmdline 96 "$moddir/parse-bond.sh"
    inst_hook cmdline 96 "$moddir/parse-team.sh"
    inst_hook cmdline 97 "$moddir/parse-bridge.sh"
    inst_hook cmdline 98 "$moddir/parse-ip-opts.sh"
    inst_hook cmdline 99 "$moddir/parse-ifname.sh"
    inst_hook cleanup 10 "$moddir/kill-dhclient.sh"

    # SUSE specific files
    for f in \
        /etc/sysconfig/network/ifcfg-* \
        /etc/sysconfig/network/ifroute-* \
        /etc/sysconfig/network/routes \
        /var/lib/wicked/duid.xml \
        /var/lib/wicked/iaid.xml; do
        [ -e "$f" ] && inst_simple "$f"
    done

    # install all config files for teaming
    unset TEAM_MASTER
    unset TEAM_CONFIG
    unset TEAM_PORT_CONFIG
    unset HWADDR
    unset SUBCHANNELS
    for i in /etc/sysconfig/network-scripts/ifcfg-*; do
        [ -e "$i" ] || continue
        case "$i" in
            *~ | *.bak | *.orig | *.rpmnew | *.rpmorig | *.rpmsave)
                continue
                ;;
        esac
        (
            # shellcheck disable=SC1090
            . "$i"
            if ! [ "${ONBOOT}" = "no" -o "${ONBOOT}" = "NO" ] \
                && [ -n "${TEAM_MASTER}${TEAM_CONFIG}${TEAM_PORT_CONFIG}" ]; then
                if [ -n "$TEAM_CONFIG" ] && [ -n "$DEVICE" ]; then
                    mkdir -p "$initdir"/etc/teamd
                    printf -- "%s" "$TEAM_CONFIG" > "$initdir/etc/teamd/${DEVICE}.conf"
                elif [ -n "$TEAM_PORT_CONFIG" ]; then
                    inst_simple "$i"

                    HWADDR="$(echo "$HWADDR" | sed 'y/ABCDEF/abcdef/')"
                    if [ -n "$HWADDR" ]; then
                        ln_r "$i" "/etc/sysconfig/network-scripts/mac-${HWADDR}.conf"
                    fi

                    SUBCHANNELS="$(echo "$SUBCHANNELS" | sed 'y/ABCDEF/abcdef/')"
                    if [ -n "$SUBCHANNELS" ]; then
                        ln_r "$i" "/etc/sysconfig/network-scripts/ccw-${SUBCHANNELS}.conf"
                    fi
                fi
            fi
        )
    done

    _arch=${DRACUT_ARCH:-$(uname -m)}

    inst_libdir_file {"tls/$_arch/",tls/,"$_arch/",}"libnss_dns.so.*" \
        {"tls/$_arch/",tls/,"$_arch/",}"libnss_mdns4_minimal.so.*"

    dracut_need_initqueue
}
