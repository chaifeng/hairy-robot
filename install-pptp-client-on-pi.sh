#!/bin/bash
[[ "$INSTALL_TRACE" ]] && set -x
set -eo pipefail

if [[ "$(id -u)" != 0 ]]; then
    sudo INSTALL_TRACE=$INSTALL_TRACE \
         PPTP_SERVER=$PPTP_SERVER \
         PPTP_USERNAME=$PPTP_USERNAME \
         PPTP_PASSWORD=$PPTP_PASSWORD \
         "$0" "$@"
    exit 0
fi

show_help() {
    cat <<EOF
export PPTP_SERVER=youvpnhost.com
export PPTP_USERNAME=YourVpnUsername
export PPTP_PASSWORD=YourVpnPassword
EOF
    exit 1
}

restore-orig() {
    if [[ -f "$1.orig" ]]; then
        diff "$1.orig" "$1" >/dev/null || cp -f "$1.orig" "$1"
    else
        rm -f "$1"
    fi
}

make-backup() {
    if [[ -f "$1" ]]; then
        cp -n "$1" "$1.orig"
        cp -n "$1" "$1~$TIMESTAMP"
    fi
    restore-orig "$1"
}

append-to() {
    test -n "$1"
    make-backup "$1"
    cat >> "$1"
}

overwrite-to() {
    test -n "$1"
    restore-orig "$1"
    cat > "$1"
}

VPNPIRC=$HOME/.vpnpirc

update-vpnpirc() {
    cat > $VPNPIRC <<EOF
# $(date '+%F %T')
export PPTP_SERVER=$PPTP_SERVER
export PPTP_USERNAME=$PPTP_USERNAME
export PPTP_PASSWORD=$PPTP_PASSWORD
export PPTP_TUNNEL=$PPTP_TUNNEL
export PPTP_REMOTENAME=$PPTP_REMOTENAME
export PI_WIFI_SSID=$PI_WIFI_SSID
export PI_WIFI_PASS=$PI_WIFI_PASS
EOF
}

load-vpnpirc() {
    if [[ -f $VPNPIRC ]]; then
        source $VPNPIRC
    fi
}

#  ___________
# < It starts >
#  -----------
#         \   ^__^
#          \  (oo)\_______
#             (__)\       )\/\
#                 ||----w |
#                 ||     ||
#

load-vpnpirc

test -z "$PPTP_SERVER"   && show_help
test -z "$PPTP_USERNAME" && show_help
test -z "$PPTP_PASSWORD" && show_help

PPTP_TUNNEL=${PPTP_TUNNEL:-vpnpi}
PPTP_REMOTENAME=${PPTP_REMOTENAME:-pptpd}
PI_WIFI_SSID=${PI_WIFI_SSID:-0dd3-Pi}
PI_WIFI_PASS=${PI_WIFI_PASS:-w31c0m320dd3}
TIMESTAMP=$(date '+%Y%m%d-%Hh%Mm%Ss')

PPTP_PEER=/etc/ppp/peers/$PPTP_TUNNEL
if [[ -f $PPTP_PEER ]]; then
    poff $PPTP_TUNNEL >/dev/null || true
    sleep 3
fi

update-vpnpirc

make-backup /etc/locale.gen
sed -i '/zh_CN.UTF-8/czh_CN.UTF-8 UTF-8' /etc/locale.gen
locale-gen

apt-get update
apt-get -y upgrade
apt-get install -y pptp-linux dnsmasq byobu dnsutils hostapd haveged

touch /var/log/ppp-ipupdown.log

append-to /etc/ppp/chap-secrets >/dev/null <<EOF
$PPTP_USERNAME     $PPTP_REMOTENAME    $PPTP_PASSWORD     *
EOF

overwrite-to $PPTP_PEER <<EOF
pty "pptp $PPTP_SERVER --nolaunchpppd"
name $PPTP_USERNAME
remotename $PPTP_REMOTENAME
require-mppe-128
file /etc/ppp/options.pptp
ipparam $PPTP_TUNNEL
persist
EOF

# debug
# pon $PPTP_TUNNEL debug dump logfd 2 nodetach

#ORIG_GW_IP=$(netstat -rn | grep ^0.0.0.0 | awk '{print $2}')
#VPN_SERVER_IP=$(netstat -rn | fgrep ppp0 | grep -v ^0.0.0.0 | awk '{print $1}')

#route add -host $PPTP_SERVER_IP gw $ORIG_GW_IP dev eth0
#route del default gw $ORIG_GW_IP
#route add default gw $VPN_SERVER_IP

# static dns server with dhcp
append-to /etc/dhcp/dhclient.conf <<EOF
supersede domain-name-servers 127.0.0.1;
EOF

overwrite-to /etc/resolv.dnsmasq <<EOF
nameserver 8.8.8.8
nameserver 8.8.4.4
EOF

overwrite-to /etc/dnsmasq.d/resolv <<EOF
resolv-file=/etc/resolv.dnsmasq
EOF

## TODO autostart ppp
#make-backup /etc/network/interfaces

PPTP_UP_SCRIPT=/etc/ppp/ip-up.d/00-$PPTP_TUNNEL
PPTP_DOWN_SCRIPT=/etc/ppp/ip-down.d/00-$PPTP_TUNNEL

overwrite-to $PPTP_UP_SCRIPT <<EOF
#!/bin/sh
# pppd ip-up script for all-to-tunnel routing
# This script is called with the following arguments:
#    Arg  Name                          Example
#    $1   Interface name                ppp0
#    $2   The tty                       ttyS1
#    $3   The link speed                38400
#    $4   Local IP number               12.34.56.78
#    $5   Peer  IP number               12.34.56.99
#    $6   Optional "ipparam" value      foo

set -e

# name of primary network interface (before tunnel)
PRIMARY_IFACE=eth0

# address of tunnel server
SERVER=$PPTP_SERVER

# provided by pppd: string to identify connection aka ipparam option
CONNECTION=\$6
test -z "\${CONNECTION}" && CONNECTION=\${PPP_IPPARAM}

# provided by pppd: interface name
TUNNEL_IFACE=\$1
test -z "\${TUNNEL_IFACE}" && TUNNEL_IFACE=\${PPP_IFACE}

# if we are being called as part of the tunnel startup
if [ "\${CONNECTION}" = "${PPTP_TUNNEL}" ] ; then
    set +e

    ## direct tunnelled packets to the tunnel server
    #route add -host \${SERVER} dev \${PRIMARY_IFACE}

    # direct all other packets into the tunnel
    route del default \${PRIMARY_IFACE}
    route add default dev \${TUNNEL_IFACE}
fi
EOF

overwrite-to $PPTP_DOWN_SCRIPT <<EOF
#!/bin/sh
# pppd ip-down script for all-to-tunnel routing
# This script is called with the following arguments:
#    Arg  Name                          Example
#    $1   Interface name                ppp0
#    $2   The tty                       ttyS1
#    $3   The link speed                38400
#    $4   Local IP number               12.34.56.78
#    $5   Peer  IP number               12.34.56.99
#    $6   Optional "ipparam" value      foo

set -e

# name of primary network interface (before tunnel)
PRIMARY_IFACE=eth0

# address of tunnel server
SERVER=$PPTP_SERVER

# provided by pppd: string to identify connection aka ipparam option
CONNECTION=\$6
test -z "\${CONNECTION}" && CONNECTION=\${PPP_IPPARAM}

# provided by pppd: interface name
TUNNEL_IFACE=\$1
test -z "\${TUNNEL_IFACE}" && TUNNEL_IFACE=\${PPP_IFACE}

# if we are being called as part of the tunnel startup
if [ "\${CONNECTION}" = "${PPTP_TUNNEL}" ] ; then
    set +e

    # direct packets back to the original interface
    route del default \${TUNNEL_IFACE}
    route add default dev \${PRIMARY_IFACE}
fi
EOF

chmod +x $PPTP_UP_SCRIPT $PPTP_DOWN_SCRIPT

for F in add-china-routes del-china-routes; do
    curl --silent -Lk https://github.com/chaifeng/hairy-robot/raw/master/$F > $F
done

cp -f {add,del}-china-routes /usr/bin/
chmod +x /usr/bin/{add,del}-china-routes

overwrite-to /etc/profile.d/sbin <<EOF
export PATH=\$PATH:/sbin:/usr/sbin
EOF
chmod +x /etc/profile.d/sbin

overwrite-to /usr/sbin/start-vpn <<EOF
sudo pon $PPTP_TUNNEL updetach
EOF

overwrite-to /usr/sbin/start-vpn-debug <<EOF
sudo pon $PPTP_TUNNEL debug dump logfd 2 nodetach
EOF

overwrite-to /usr/sbin/stop-vpn <<EOF
sudo poff $PPTP_TUNNEL
EOF

chmod +x /usr/sbin/{start,stop}-vpn /usr/sbin/start-vpn-debug

overwrite-to /etc/resolv.conf <<EOF
nameserver 8.8.8.8
nameserver 8.8.4.4
EOF

#################### hostapd

make-backup /etc/network/interfaces
overwrite-to /etc/network/interfaces <<EOF
auto lo

iface lo inet loopback
iface eth0 inet dhcp

auto wlan0
iface wlan0 inet static
address 10.72.74.1
netmask 255.255.255.0
EOF

overwrite-to /etc/hostapd/hostapd.conf <<EOF
interface=wlan0
driver=nl80211
ssid=$PI_WIFI_SSID
hw_mode=g
channel=3
wpa=1
wpa_passphrase=$PI_WIFI_PASS
wpa_key_mgmt=WPA-PSK
wpa_pairwise=TKIP CCMP
wpa_ptk_rekey=600
macaddr_acl=0
EOF

overwrite-to /etc/dnsmasq.d/${PPTP_TUNNEL}_dhcp <<EOF
bind-interfaces
expand-hosts
no-dhcp-interface=eth0
dhcp-range=10.72.74.64,10.72.74.89,12h
dhcp-option=option:router,10.72.74.1
EOF

make-backup /etc/rc.local
sed -i -e '/exit 0/d' /etc/rc.local
append-to /etc/rc.local <<EOF

start-vpn

echo 1 > /proc/sys/net/ipv4/ip_forward
iptables -t nat -A POSTROUTING -o ppp0 -j MASQUERADE
iptables -A FORWARD -i eth0 -o ppp0 -m state --state RELATED,ESTABLISHED -j ACCEPT
iptables -A FORWARD -i wlan0 -o ppp0 -j ACCEPT

hostapd -B /etc/hostapd/hostapd.conf

exit 0
EOF

############################

append-to /etc/motd <<EOF

            ^__^
            (oo)\\_______
            (__)\\       )\\/\\
                ||----w |
                ||     ||

Start VPN         : start-vpn
Stop VPN          : stop-vpn
Add China routes  : add-china-routes
Del China routes  : del-china-routes
Show route tables : ip route show

Wi-Fi:
    SSID : $PI_WIFI_SSID
    PASS : $PI_WIFI_PASS

EOF

echo "Done."
echo "Rebooting your Raspberry Pi ..."
reboot
