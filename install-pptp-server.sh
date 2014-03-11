#!/bin/bash
#    Install PPTP VPN server.
#
#    Tested with Digital Ocean Ubuntu 12.04 images.

set -e
[[ "$HAIRY_ROBOT_TRACE" ]] && set -x

VPN_USER=${VPN_USER:-$USER}
VPN_LOCAL_IP='10.77.87.1'

VPN_NETWORK=$(echo $VPN_LOCAL_IP | sed -e 's,\.[0-9]\+$,.0,')/24
VPN_REMOTE_IP="${VPN_LOCAL_IP}0-100"

if [[ $(id -u) -ne 0 ]]; then
  sudo VPN_USER=$USER HAIRY_ROBOT_TRACE=$HAIRY_ROBOT_TRACE "$0" "$@"
  exit 0
fi

echo "Input 'yes' to install and setup PPTP server: "
read; [[ 'yes' == "$REPLY" ]] || exit 2

BACKUP_SURFIX=$(date '+%Y%m%d-%Hh%Mm%Ss')

make-backup() {
    test -n "$1"
    if [[ -f "$1" ]]; then
        cp "$1" "$1~$BACKUP_SURFIX"
    fi
    if [[ -f "$1.orig" ]]; then
        cp "$1" "$1.orig"
    fi
}

apt-install() {
    test -n "$1"
    apt-get -y install $1 || {
        echo "Could not install $1"
        exit 1
    }
}

apt-install pptpd

make-backup /etc/rc.local

#ubuntu has exit 0 at the end of the file.
sed -i '/^exit 0/d' /etc/rc.local

cat >> /etc/rc.local << END
echo 1 > /proc/sys/net/ipv4/ip_forward
#control channel
iptables -I INPUT -p tcp --dport 1723 -j ACCEPT
#gre tunnel protocol
iptables -I INPUT  --protocol 47 -j ACCEPT

iptables -t nat -A POSTROUTING -s $VPN_NETWORK -d 0.0.0.0/0 -o eth0 -j MASQUERADE

#supposedly makes the vpn work better
iptables -I FORWARD -s $VPN_NETWORK -p tcp -m tcp --tcp-flags FIN,SYN,RST,ACK SYN -j TCPMSS --set-mss 1356

END
sh /etc/rc.local

#no liI10oO chars in password
P1=`cat /dev/urandom | tr -cd abcdefghjkmnpqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789 | head -c 3`
P2=`cat /dev/urandom | tr -cd abcdefghjkmnpqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789 | head -c 3`
P3=`cat /dev/urandom | tr -cd abcdefghjkmnpqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789 | head -c 3`
PASS="$P1-$P2-$P3"

make-backup /etc/ppp/chap-secrets

cat >/etc/ppp/chap-secrets <<END
# Secrets for authentication using CHAP
# client server secret IP addresses
$VPN_USER pptpd $PASS *
END

make-backup /etc/pptpd.conf

cat >/etc/pptpd.conf <<END
option /etc/ppp/options.pptpd
logwtmp
localip $VPN_LOCAL_IP
remoteip $VPN_REMOTE_IP
END

make-backup /etc/ppp/options.pptpd

cat >/etc/ppp/options.pptpd <<END
name pptpd
refuse-pap
refuse-chap
refuse-mschap
require-mschap-v2
require-mppe-128
ms-dns 8.8.8.8
ms-dns 8.8.4.4
proxyarp
lock
nobsdcomp
novj
novjccomp
nologfd
END

#find out external ip
IP=`wget -q -O - http://ipecho.net/plain`

if [ test -z "$IP" ]; then
  echo "============================================================"
  echo "  !!!  COULD NOT DETECT SERVER EXTERNAL IP ADDRESS  !!!"
else
  echo "============================================================"
  echo "Detected your server external ip address: $IP"
fi

echo   ""
echo   "VPN username = $VPN_USER   password = $PASS"
echo   "============================================================"
sleep 2

service pptpd restart

exit 0
