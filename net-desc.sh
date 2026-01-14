#!/bin/sh
#
# Show network configuration.
# CentOS/RH, minimal support for debian
#

VERSION="0.0.10, SPDsoft. Wed Jan 14 12:21:46 CET 2026"
DIST=http://webdiis.unizar.es/~spd/src/net/net-desc.sh
BIN=$HOME/usr/bin
PROGRAM=net-desc.sh
PATH=$PATH:/usr/local/bin

usage()
{
cat <<EOF
$PROGRAM -VIDhngm
    -V: version
    -I: internet version
    -D: download and install update
    -h: help
EOF
}

set -- `getopt VIDh "$@"`

if test $? != 0
then
	usage
	exit 1
fi

for i in "$@"
do
	case $i in
	-V) echo "$VERSION"; exit 0;;
	-I)
		DV=`lynx -source $DIST | awk -F'"' '/^VERSION/{print $2; exit;}'`
		if [ "_$DV" != "_$VERSION" ]
		then
			echo "#### Warning: Server version is  \"$DV\""
			echo "####          program version is \"$VERSION\""
			exit 1
		fi
		exit 0
		;;
	-D)
		lynx -source $DIST > /tmp/$PROGRAM.$$ ||\
		exit 1 && \
		mv /tmp/$PROGRAM.$$ $BIN/$PROGRAM
		chmod 755 $BIN/$PROGRAM
		#chown root $BIN/$PROGRAM
		#chgrp 0 $BIN/$PROGRAM
		exit 0
		;;

	-h)
		usage
		exit 0
		;;
	esac
done

if service NetworkManager status 2>/dev/null |\
	fgrep "active (running)" > /dev/null
then
	NM=: # Using Network Manager
	echo "##"
	echo "## Using Network Manager"
	echo "##"

else
	NM=false
fi

if type nmcli > /dev/null 2>&1
then
	:
else
	NM=false
	nmcli()
	{
		:
	}
fi

if type brctl > /dev/null 2>&1
then
	:
else
	brctl()
	{
		if [ "_$2" = "_" ]
		then
		nmcli \
		-t -f GENERAL.TYPE,GENERAL.DEVICE,BRIDGE.SLAVES device show \
		| awk -F: \
		'/GENERAL.TYPE:bridge/ {getline; getline br; printf("%s\n",$2)}'
		else
		BRDEV=$2
		nmcli -f GENERAL.DEVICE,GENERAL.TYPE,BRIDGE.SLAVES device show ${BRDEV}
		fi
	}
fi

#### Ethernet ports

IFNAMES=`lshw -class network -quiet -short 2>/dev/null | awk '/^\// {print $2}'`

echo "#####"
echo "#####"
echo "#### " Physical ethernet interfaces
echo "#####"
echo "## " $IFNAMES

lspci | egrep -i --color 'network|ethernet'
#lshw -class network | egrep "(logical name|product)"
lshw -class network -quiet -short 2>/dev/null

#### IP addresses
echo "#####"
echo "#####"
echo "#### " IP addresses
echo "#####"

if type ifconfig > /dev/null
then
	ifconfig -a | egrep "(^[a-z]|inet|ether)"
else
	ip addr show |\
		egrep "(^[a-z0-9]|inet|ether)"
fi


#### Bonding

echo "#####"
echo "#####"
echo "#### " Bonding
if test -d /proc/net/bonding/
then

cd /proc/net/bonding/
for f in *
do
	if [ -f $f ]
	then
		IFBOND=`awk '/Slave Interface:/ {print $3}' $f`
		MODE=`awk '/Bonding Mode:/ {print $3}' $f`
		echo "## " $f - $IFBOND
		echo "##   Mode:" ${MODE}
		echo "## Status:"
		for if in $IFBOND
		do
			echo "# ${if}:"
			ethtool $if | egrep "Speed|detected"
			echo "# ${if} IP: " `ip addr show $if | awk '/inet /{print $2}'`
		done

		if $NM
		then

		CONBOND=`nmcli c s | egrep -e " bond .*${f}" | awk '{print $1}'`
		echo "# CON: " "$CONBOND"
		SLT=`nmcli c s "$CONBOND" | awk '/connection.slave-type/ {print $2}'`
		if [ _"$SLT" = _"bridge" ]
		then
			BR=`nmcli c s "$CONBOND" | awk '/connection.master/ {print $2}'`
			if expr "$BR" : "[a-z0-9]*-[a-z0-9]*-.*" > /dev/null 2>&1
			then
				BR=`nmcli c s | awk "/$BR/"'{print $NF}'`
			fi
			echo "## " $f - slave to bridge $BR
		else
			echo "# ${f} IP:" `ip addr show $f | awk '/inet /{print $2}'`
		fi

		else
			BR=`brctl show | awk "/$f$/"'{print $1}'`
			if [ "_$BR" != "_" ]
			then
				echo "## " $f - slave to bridge $BR
			else
				echo "# ${f} IP:" `ip addr show $f | awk '/inet /{print $2}'`
			fi
		fi
	fi
done

else
	echo "## No bonding present"
fi

#### Bridges

echo "#####"
echo "#####"
echo "#### Bridges"
echo "#####"
echo "# List"
brctl show
echo "# Link"
bridge link | grep master | sed -e 's/^[0-9]*: //' \
-e 's/:.*master//'

BRIDGES=`nmcli \
	-t -f GENERAL.TYPE,GENERAL.DEVICE,BRIDGE.SLAVES device show \
	| awk -F: \
	'/GENERAL.TYPE:bridge/ {getline; getline br; printf("%s\n",$2)}'`

for BRIDGE in ${BRIDGES}
do
	echo "## " BRIDGE $BRIDGE
	brctl show $BRIDGE
	echo "# ${BRIDGE} IP:" `ip addr show ${BRIDGE} | awk '/inet /{print $2}'`
done

#### VLANs

echo "#####"
echo "#####"
echo "#### VLANs"
echo "#####"

if $NM
then
	VLANS=`nmcli \
		-t -f TYPE,NAME,DEVICE c show \
		| awk -F: \
		'/^vlan:/ {printf("%s\n",$2)}'`
else
	VLANS=`ip -d addr show type vlan |\
		sed -e '/vlan/!d' -e 's/.* id //' -e 's/ .*//'`
fi

if $NM
then
	for VLAN in ${VLANS}
	do
		echo "## " VLAN $VLAN
		OUT=`nmcli c s $VLAN |\
		egrep '(vlan.id|vlan.parent|IP4.|connection.interface-name)'`
		echo "$OUT"
		PARENT=`echo "$OUT" | awk '/vlan.parent/{print $NF}'`
		PARENT=`nmcli c s | awk "/$PARENT/"'{print $NF}'`
		echo "# VLAN $VLAN (${PARENT})"
	done
else
	ip -d addr show type vlan | awk '
	/^[a-z0-9].*/ { IF=$2 }
	/vlan/ {VLAN=$5}
	/inet/ {IP=$2; printf("# VLAN %s - %s - %s\n", VLAN, IF, IP)}' |\
	sort -u
fi

echo "#####"
echo "#####"
echo "#### Routing"
echo "#####"

echo "## kernel forward and arp_filter: "
sysctl  net.ipv4.ip_forward 2>/dev/null
sysctl  net.ipv4.default.arp_filter 2>/dev/null

echo "## routes (netstat)"
type netstat > /dev/null && netstat -rn || echo "# neststat not available"
echo "## routes (route)"
type route > /dev/null && route -v || echo "# route not available"
echo "## routes (ip)"
ip route show

echo "##"
echo "## Routing Tables"
echo "# Rules"
ip rule list

RT=`ip rule list |\
sed -e '/lookup/!d' \
-e 's/.*lookup[ ]*//' \
-e 's/[ ].*//' | sort -u`


if [ -f /etc/iproute2/rt_tables ]
then
	RTTF=/etc/iproute2/rt_tables
else
	RTTF=/usr/share/iproute2/rt_tables
fi
echo "# TABLE Names in $RTTF:"

egrep -v -e '^#' $RTTF

echo "# TABLES:" $RT

for TABLE in $RT
do
	echo "# TABLE" $TABLE
	ip route show table $TABLE
done






