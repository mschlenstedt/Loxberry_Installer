#!/bin/bash

########################################################################
# Adjust this to the latest release image

TARGET_VERSION_ID="13"
TARGET_PRETTY_NAME="Debian GNU/Linux 13 (trixie)"
LBHOME="/opt/loxberry"
PHPVER_PROD=7.4
PHPVER_TEST=8.4

#
########################################################################

# Needed for some LoxBerry scripts
export LBHOMEDIR=$LBHOME
export PERL5LIB=$LBHOME/libs/perllib
export APT_LISTCHANGES_FRONTEND="none"
export DEBIAN_FRONTEND="noninteractive"
export PATH=$PATH:/usr/sbin/

# Run as root
if (( $EUID != 0 )); then
    echo "This script has to be run as root."
    exit 1
fi

if [ -e  $LBHOME/config/system/do_lbupdate ]; then
	echo "This script was already executed on this LoxBerry. You cannot reinstall LoxBerry."
	echo "If you are sure what you are doing, rm $LBHOME/config/system/do_lbupdate and restart again."
	exit 1
fi

echo -e "\n\nNote! If you were logged in as user 'loxberry' and used 'su' to switch to the root account, your connection may be lost now...\n\n"
/usr/bin/killall -u loxberry
sleep 3

# Commandline options
while getopts "t:b:u:" o; do
    case "${o}" in
        t)
            TAG=${OPTARG}
            ;;
        b)
            BRANCH=${OPTARG}
            ;;
        u)
            GITHUB_AUTH=${OPTARG}
            ;;
        *)
            ;;
    esac
done
shift $((OPTIND-1))

# install needed packages
/usr/bin/apt-get -y --allow-unauthenticated --allow-downgrades --allow-remove-essential --allow-change-held-packages --allow-releaseinfo-change update
/usr/bin/apt-get --no-install-recommends -y --allow-unauthenticated --fix-broken --reinstall --allow-downgrades --allow-remove-essential --allow-change-held-packages install jq git lsb-release

# Stop loxberry Service
if /bin/systemctl --no-pager status apache2.service; then
	/bin/systemctl stop apache2.service
fi
if /bin/systemctl --no-pager status loxberry.service; then
	/bin/systemctl disable loxberry.service
	/bin/systemctl stop loxberry.service
fi
if /bin/systemctl --no-pager status ssdpd.service; then
	/bin/systemctl disable ssdpd.service
	/bin/systemctl stop ssdpd.service
fi
if /bin/systemctl --no-pager status mosquitto.service; then
	/bin/systemctl disable mosquitto.service
	/bin/systemctl stop mosquitto.service
fi
if /bin/systemctl --no-pager status createtmpfs.service; then
	/bin/systemctl disable createtmpfs.service
	/bin/systemctl stop createtmpfs.service
	echo -e "\nThere are some old mounts of tmpfs filesystems. Please reboot and start installation again.\n"
	exit 1
fi

# Clear screen
/usr/bin/tput clear

# Formating - to be used in echo's
BLACK=`/usr/bin/tput setaf 0`
RED=`/usr/bin/tput setaf 1`
GREEN=`/usr/bin/tput setaf 2`
YELLOW=`/usr/bin/tput setaf 3`
BLUE=`/usr/bin/tput setaf 4`
MAGENTA=`/usr/bin/tput setaf 5`
CYAN=`/usr/bin/tput setaf 6`
WHITE=`/usr/bin/tput setaf 7`
BOLD=`/usr/bin/tput bold`
ULINE=`/usr/bin/tput smul`
RESET=`/usr/bin/tput sgr0`

########################################################################
# Functions

# Horizontal Rule
HR () {
	/usr/bin/echo -en "${!1}"
	printf '%.s─' $(seq 1 $(/usr/bin/tput cols))
	/usr/bin/echo -e "${RESET}"
}

# Section
TITLE () {
	/usr/bin/echo -e ""
	HR "WHITE"
	/usr/bin/echo -e "${BOLD}$1${RESET}"
	HR "WHITE"
	/usr/bin/echo -e ""
}

# Messages
OK () {
	/usr/bin/echo -e "\n${GREEN}[  OK   ]${RESET} .... $1"
}
FAIL () {
	/usr/bin/echo -e "\n${RED}[FAILED ]${RESET} .... $1"
}
WARNING () {
	/usr/bin/echo -e "\n${MAGENTA}[WARNING]${RESET} .... $1"
}
INFO () {
	/usr/bin/echo -e "\n${YELLOW}[ INFO  ]${RESET} .... $1"
}

#
########################################################################


# Main Script
HR "GREEN"
/usr/bin/echo -e "${BOLD}LoxBerry - BEYOND THE LIMITS${RESET}"
HR "GREEN"

# Read Distro infos
if [ -e /etc/os-release ]; then
	. /etc/os-release
	#PRETTY_NAME="Debian GNU/Linux 11 (bullseye)"
	#NAME="Debian GNU/Linux"
	#VERSION_ID="11"
	#VERSION="11 (bullseye)"
	#VERSION_CODENAME=bullseye
	#ID=debian
	#HOME_URL="https://www.debian.org/"
	#SUPPORT_URL="https://www.debian.org/support"
	#BUG_REPORT_URL="https://bugs.debian.org/"
fi
if [ -e /boot/dietpi/.hw_model ]; then
	. /boot/dietpi/.hw_model
	#G_HW_MODEL=20
	#G_HW_MODEL_NAME='Virtual Machine (x86_64)'
	#G_HW_ARCH=10
	#G_HW_ARCH_NAME='x86_64'
	#G_HW_CPUID=0
	#G_HW_CPU_CORES=2
	#G_DISTRO=6
	#G_DISTRO_NAME='bullseye'
	#G_ROOTFS_DEV='/dev/sda1'
	#G_HW_UUID='0f26dd2a-8ed6-40ee-86e9-c3b204dba1e0'
fi
if [ -e /boot/dietpi/.version ]; then
	. /boot/dietpi/.version
	#G_DIETPI_VERSION_CORE=8
	#G_DIETPI_VERSION_SUB=13
	#G_DIETPI_VERSION_RC=2
	#G_GITBRANCH='master'
	#G_GITOWNER='MichaIng'
	#G_LIVE_PATCH_STATUS[0]='applied'
	#G_LIVE_PATCH_STATUS[1]='not applicable'
fi

# Check correct distribution
if [ ! -e /boot/dietpi/.version ]; then
	/usr/bin/echo -e "\n${RED}This seems not to be a DietPi Image. LoxBerry can only be installed on DietPi.\n"
	/usr/bin/echo -e "We expect $TARGET_PRETTY_NAME as distribution."
	/usr/bin/echo -e "Please download the correct image from ${ULINE}https://dietpi.com\n${RESET}"
	exit 1
fi

if [ $VERSION_ID -ne $TARGET_VERSION_ID ]; then
	/usr/bin/echo -e "\n${RED}You are running $PRETTY_NAME. This distribution"
	/usr/bin/echo -e "is not supported by LoxBerry.\n"
	/usr/bin/echo -e "We expect $TARGET_PRETTY_NAME as distribution."
	/usr/bin/echo -e "Please download the correct image from ${ULINE}https://dietpi.com\n${RESET}"
	exit 1
fi

# Get latest release
if [ -z $TAG ]; then
	TARGETRELEASE="latest"
else
	TARGETRELEASE="tags/$TAG"
fi

if [ ! -z $BRANCH ]; then
	LBVERSION="Branch $BRANCH (latest)"
else
	GITHUB_AUTH_OPT=""
	if [ ! -z "$GITHUB_AUTH" ]; then
		GITHUB_AUTH_OPT="-u $GITHUB_AUTH"
	fi
	RELEASEJSON=`/usr/bin/curl -s $GITHUB_AUTH_OPT \
		-H "Accept: application/vnd.github+json" \
		https://api.github.com/repos/mschlenstedt/Loxberry/releases/$TARGETRELEASE`

	LBVERSION=$(/usr/bin/echo $RELEASEJSON | /usr/bin/jq -r ".tag_name")
	LBNAME=$(/usr/bin/echo $RELEASEJSON | /usr/bin/jq -r ".name")
	LBTARBALL=$(/usr/bin/echo $RELEASEJSON | /usr/bin/jq -r ".tarball_url")

	if [ -z $LBVERSION ] || [ $LBVERSION = "null" ]; then
		GHMESSAGE=$(/usr/bin/echo $RELEASEJSON | /usr/bin/jq -r ".message // empty")
		if [ ! -z "$GHMESSAGE" ]; then
			FAIL "Cannot download latest release information from GitHub: $GHMESSAGE\n"
		else
			FAIL "Cannot download latest release information from GitHub.\n"
		fi
		exit 1
	fi
fi

# Welcome screen with overview
/usr/bin/echo -e "\nThis script will install ${BOLD}${ULINE}LoxBerry $LBVERSION${RESET} on your system.\n"
/usr/bin/echo -e "${RED}${BOLD}WARNING!${RESET}${RED} You cannot undo the installation! Your system will be converted"
/usr/bin/echo -e "into a LoxBerry with no return! Nothing will be like it was before ;-)${RESET}"
/usr/bin/echo -e "\n${ULINE}Your system seems to be:${RESET}\n"
/usr/bin/echo -e "Distribution:       $PRETTY_NAME"
/usr/bin/echo -e "DietPi Version:     $G_DIETPI_VERSION_CORE.$G_DIETPI_VERSION_SUB"
/usr/bin/echo -e "Hardware Model:     $G_HW_MODEL_NAME"
/usr/bin/echo -e "Architecture:       $G_HW_ARCH_NAME"
/usr/bin/echo -e ""
/usr/bin/echo -e ""
echo -e "Press ${BOLD}<CTRL>+C${RESET} to abort. Installation continues automatically in 15 seconds..."
sleep 15
/usr/bin/tput clear

# Download Release
TITLE "Downloading LoxBerry sources from GitHub..."

rm -rf $LBHOME
mkdir -p $LBHOME
cd $LBHOME

if [ ! -z $BRANCH ]; then
	/usr/bin/git clone https://github.com/mschlenstedt/Loxberry.git -b $BRANCH
	if [ ! -d $LBHOME/Loxberry ]; then
		FAIL "Could not download LoxBerry sources.\n"
		exit 1
	else
		OK "Successfully downloaded LoxBerry sources."
  		shopt -s dotglob
		mv $LBHOME/Loxberry/* $LBHOME
		rm -r $LBHOME/Loxberry
	fi
else
	/usr/bin/curl -L -o $LBHOME/src.tar.gz $LBTARBALL
	if [ ! -e $LBHOME/src.tar.gz ]; then
		FAIL "Could not download LoxBerry sources.\n"
		exit 1
	else
		OK "Successfully downloaded LoxBerry sources."
	fi
	# Extracting sources
	TITLE "Extracting LoxBerry sources..."

	/usr/bin/tar xvfz src.tar.gz --strip-components=1 > /dev/null
	if [ $? != 0 ]; then
		FAIL "Could not extract LoxBerry sources.\n"
		exit 1
	else
		OK "Successfully downloaded LoxBerry sources."
		rm $LBHOME/src.tar.gz
	fi
fi

# Get latest packagesXX.txt - if not in Repo
if [ ! -e "$LBHOME/packages${TARGET_VERSION_ID}.txt" ]; then
	/usr/bin/curl -L -o $LBHOME/packages${TARGET_VERSION_ID}.txt https://raw.githubusercontent.com/mschlenstedt/Loxberry/refs/heads/master/packages${TARGET_VERSION_ID}.txt
fi

# Adding User loxberry
TITLE "Adding user 'loxberry', setting default passwd..."

/usr/bin/killall -u loxberry
/usr/bin/sleep 3

/usr/sbin/deluser --quiet loxberry > /dev/null 2>&1
/usr/sbin/adduser --no-create-home --home $LBHOME --disabled-password --gecos "" loxberry
if [ $? != 0 ]; then
	FAIL "Could not create user 'loxberry'.\n"
	exit 1
else
	OK "Successfully created user 'loxberry'."
fi

/usr/bin/echo 'loxberry:loxberry' | /usr/sbin/chpasswd -c SHA512
if [ $? != 0 ]; then
	FAIL "Could not set password for user 'loxberry'.\n"
	exit 1
else
	OK "Successfully set default password for user 'loxberry'."
fi

# Configuring hardware architecture
TITLE "Configuring your hardware architecture $G_HW_ARCH_NAME..."

HWMODELFILENAME=`echo "$G_HW_MODEL_NAME" | tr " " "_" | sed "s/[^[:alnum:]_]\+//g"`
/usr/bin/echo $HWMODELFILENAME > $LBHOME/config/system/is_hwmodel_$HWMODELFILENAME.cfg
/usr/bin/echo $G_HW_ARCH_NAME > $LBHOME/config/system/is_arch_$G_HW_ARCH_NAME.cfg

# Compatibility - this was standard until LB3.0.0.0
if /usr/bin/echo $HWMODELFILENAME | /usr/bin/grep -q "x86_64"; then
	/usr/bin/echo "x64" > $LBHOME/config/system/is_x64.cfg
fi
# Raspberry Pi detection, multi-stage. DietPi names the model "RPi ..." (not
# "Raspberry Pi ..."), so grepping the model name for "raspberry" never matched
# on current DietPi and is_raspberry.cfg was not written. Stage 1: DietPi's
# numeric hardware model (0-9 is the Raspberry Pi range). Stage 2: fall back to
# /proc/device-tree/model.
IS_RASPBERRY=0
if /usr/bin/echo "$G_HW_MODEL" | /usr/bin/grep -qE '^[0-9]$'; then
	IS_RASPBERRY=1
elif [ -r /proc/device-tree/model ] && /usr/bin/tr -d ' ' < /proc/device-tree/model | /usr/bin/grep -qi "raspberry pi"; then
	IS_RASPBERRY=1
fi
if [ "$IS_RASPBERRY" = "1" ]; then
	/usr/bin/echo "raspberry" > $LBHOME/config/system/is_raspberry.cfg
fi

if [ ! -e $LBHOME/config/system/is_arch_$G_HW_ARCH_NAME.cfg ]; then
	FAIL "Could not set your architecture.\n"
	exit 1
else
	OK "Successfully set architecture of your system."
fi

# Installing OpenSSH Server
TITLE "Installing OpenSSH server..."
/boot/dietpi/dietpi-software install 105

# Configuring hardware architecture
TITLE "Installing additional software packages from apt repository..."

/boot/dietpi/func/dietpi-set_software apt reset
/boot/dietpi/func/dietpi-set_software apt compress disable
/boot/dietpi/func/dietpi-set_software apt clean

# Configure PHP - we want still PHP7.4
TITLE "Preparing PHP Installation..."
cd `mktemp -d`
wget -q https://packages.sury.org/debsuryorg-archive-keyring.deb
apt-get install ./debsuryorg-archive-keyring.deb
. /etc/os-release
cat << EOF > /etc/apt/sources.list.d/sury-php.sources
Types: deb deb-src
URIs: https://packages.sury.org/php
Suites: $VERSION_CODENAME
Components: main
Signed-By: /usr/share/keyrings/debsuryorg-archive-keyring.gpg
EOF

# Installing YARN
TITLE "Preparing Yarn Installation..."
/usr/bin/curl -sL https://dl.yarnpkg.com/debian/pubkey.gpg | /usr/bin/gpg --dearmor | /usr/bin/tee /usr/share/keyrings/yarnkey.gpg >/dev/null
/usr/bin/echo "deb [signed-by=/usr/share/keyrings/yarnkey.gpg] https://dl.yarnpkg.com/debian stable main" | /usr/bin/tee /etc/apt/sources.list.d/yarn.list

# Installing Cloudflare for Remote Support
TITLE "Preparing Cloudflare Installation..."
sudo mkdir -p --mode=0755 /usr/share/keyrings
curl -fsSL https://pkg.cloudflare.com/cloudflare-main.gpg | sudo tee /usr/share/keyrings/cloudflare-main.gpg >/dev/null
echo 'deb [signed-by=/usr/share/keyrings/cloudflare-main.gpg] https://pkg.cloudflare.com/cloudflared any main' | sudo tee /etc/apt/sources.list.d/cloudflared.list

/usr/bin/apt-get -y --allow-unauthenticated --allow-downgrades --allow-remove-essential --allow-change-held-packages --allow-releaseinfo-change update
apt-cache policy php

# Alle gewuenschten Paketnamen extrahieren (Zeilen die mit "ii " beginnen)
WANTED=$(awk '/^ii / {print $2}' "$LBHOME/packages${TARGET_VERSION_ID}.txt" | sed 's/:.*$//')

# Bereits installierte Pakete
INSTALLED=$(dpkg-query -W -f='${Package}\n' 2>/dev/null | sort -u)

# Verfuegbare Pakete (im Repo vorhanden)
AVAILABLE=$(apt-cache pkgnames 2>/dev/null | sort -u)

# Delta: gewuenscht, verfuegbar, aber noch nicht installiert
PACKAGES=""
SKIPPED_NOTFOUND=""
for pkg in $WANTED; do
        if echo "$AVAILABLE" | grep -qx "$pkg"; then
                if ! echo "$INSTALLED" | grep -qx "$pkg"; then
                        PACKAGES+="$pkg "
                fi
        else
                SKIPPED_NOTFOUND+="$pkg\n"
        fi
done

if [ -n "$SKIPPED_NOTFOUND" ]; then
        WARNING "Packages not found in repos (skipped): $SKIPPED_NOTFOUND"
fi

echo -e "\n${BOLD}Installing $(echo $PACKAGES | wc -w) packages...${RESET}\n"

/usr/bin/apt-get --no-install-recommends -y --allow-unauthenticated --fix-broken --reinstall --allow-downgrades --allow-remove-essential --allow-change-held-packages install $PACKAGES
if [ $? != 0 ]; then
        FAIL "Could not install (at least some) queued packages.\n"
	exit 1
else
        OK "Successfully installed all queued packages.\n"
fi

/boot/dietpi/func/dietpi-set_software apt compress enable
/boot/dietpi/func/dietpi-set_software apt clean
/usr/bin/apt-get -y --allow-unauthenticated --allow-downgrades --allow-remove-essential --allow-change-held-packages --allow-releaseinfo-change update

# Adding user loxberry to different additional groups
TITLE "Adding user LoxBerry to some additional groups..."

# Group membership
/usr/sbin/usermod -a -G dialout loxberry
/usr/sbin/usermod -a -G audio loxberry
/usr/sbin/usermod -a -G gpio loxberry
/usr/sbin/usermod -a -G tty loxberry
/usr/sbin/usermod -a -G www-data loxberry
/usr/sbin/usermod -a -G video loxberry
/usr/sbin/usermod -a -G i2c loxberry
/usr/sbin/usermod -a -G dietpi loxberry
/usr/sbin/usermod -a -G adm loxberry

OK "Successfully configured additional groups."

# Setting up systemwide environments
TITLE "Settings up systemwide environments..."

# LoxBerry Home Directory in Environment
/usr/bin/awk -v s="LBHOMEDIR=$LBHOME" '/^LBHOMEDIR=/{$0=s;f=1} {a[++n]=$0} END{if(!f)a[++n]=s;for(i=1;i<=n;i++)print a[i]>ARGV[1]}' /etc/environment
/usr/bin/awk -v s="LBPHTMLAUTH=$LBHOME/webfrontend/htmlauth/plugins" '/^LBPHTMLAUTH=/{$0=s;f=1} {a[++n]=$0} END{if(!f)a[++n]=s;for(i=1;i<=n;i++)print a[i]>ARGV[1]}' /etc/environment
/usr/bin/awk -v s="LBPHTML=$LBHOME/webfrontend/html/plugins" '/^LBPHTML=/{$0=s;f=1} {a[++n]=$0} END{if(!f)a[++n]=s;for(i=1;i<=n;i++)print a[i]>ARGV[1]}' /etc/environment
/usr/bin/awk -v s="LBPTEMPL=$LBHOME/templates/plugins" '/^LBPTEMPL=/{$0=s;f=1} {a[++n]=$0} END{if(!f)a[++n]=s;for(i=1;i<=n;i++)print a[i]>ARGV[1]}' /etc/environment
/usr/bin/awk -v s="LBPDATA=$LBHOME/data/plugins" '/^LBPDATA=/{$0=s;f=1} {a[++n]=$0} END{if(!f)a[++n]=s;for(i=1;i<=n;i++)print a[i]>ARGV[1]}' /etc/environment
/usr/bin/awk -v s="LBPLOG=$LBHOME/log/plugins" '/^LBPLOG=/{$0=s;f=1} {a[++n]=$0} END{if(!f)a[++n]=s;for(i=1;i<=n;i++)print a[i]>ARGV[1]}' /etc/environment
/usr/bin/awk -v s="LBPCONFIG=$LBHOME/config/plugins" '/^LBPCONFIG=/{$0=s;f=1} {a[++n]=$0} END{if(!f)a[++n]=s;for(i=1;i<=n;i++)print a[i]>ARGV[1]}' /etc/environment
/usr/bin/awk -v s="LBPBIN=$LBHOME/bin/plugins" '/^LBPBIN=/{$0=s;f=1} {a[++n]=$0} END{if(!f)a[++n]=s;for(i=1;i<=n;i++)print a[i]>ARGV[1]}' /etc/environment
/usr/bin/awk -v s="LBSHTMLAUTH=$LBHOME/webfrontend/htmlauth/system" '/^LBSHTMLAUTH=/{$0=s;f=1} {a[++n]=$0} END{if(!f)a[++n]=s;for(i=1;i<=n;i++)print a[i]>ARGV[1]}' /etc/environment
/usr/bin/awk -v s="LBSHTML=$LBHOME/webfrontend/html/system" '/^LBSHTML=/{$0=s;f=1} {a[++n]=$0} END{if(!f)a[++n]=s;for(i=1;i<=n;i++)print a[i]>ARGV[1]}' /etc/environment
/usr/bin/awk -v s="LBSTEMPL=$LBHOME/templates/system" '/^LBSTEMPL=/{$0=s;f=1} {a[++n]=$0} END{if(!f)a[++n]=s;for(i=1;i<=n;i++)print a[i]>ARGV[1]}' /etc/environment
/usr/bin/awk -v s="LBSDATA=$LBHOME/data/system" '/^LBSDATA=/{$0=s;f=1} {a[++n]=$0} END{if(!f)a[++n]=s;for(i=1;i<=n;i++)print a[i]>ARGV[1]}' /etc/environment
/usr/bin/awk -v s="LBSLOG=$LBHOME/log/system" '/^LBSLOG=/{$0=s;f=1} {a[++n]=$0} END{if(!f)a[++n]=s;for(i=1;i<=n;i++)print a[i]>ARGV[1]}' /etc/environment
/usr/bin/awk -v s="LBSTMPFSLOG=$LBHOME/log/system_tmpfs" '/^LBSTMPFSLOG=/{$0=s;f=1} {a[++n]=$0} END{if(!f)a[++n]=s;for(i=1;i<=n;i++)print a[i]>ARGV[1]}' /etc/environment
/usr/bin/awk -v s="LBSCONFIG=$LBHOME/config/system" '/^LBSCONFIG=/{$0=s;f=1} {a[++n]=$0} END{if(!f)a[++n]=s;for(i=1;i<=n;i++)print a[i]>ARGV[1]}' /etc/environment
/usr/bin/awk -v s="LBSBIN=$LBHOME/bin" '/^LBSBIN=/{$0=s;f=1} {a[++n]=$0} END{if(!f)a[++n]=s;for(i=1;i<=n;i++)print a[i]>ARGV[1]}' /etc/environment
/usr/bin/awk -v s="LBSSBIN=$LBHOME/sbin" '/^LBSSBIN=/{$0=s;f=1} {a[++n]=$0} END{if(!f)a[++n]=s;for(i=1;i<=n;i++)print a[i]>ARGV[1]}' /etc/environment
/usr/bin/awk -v s="PERL5LIB=$LBHOME/libs/perllib" '/^PERL5LIB=/{$0=s;f=1} {a[++n]=$0} END{if(!f)a[++n]=s;for(i=1;i<=n;i++)print a[i]>ARGV[1]}' /etc/environment

# Set environments for Apache
/usr/bin/sed -i -e "s#/opt/loxberry/#$LBHOME/#g" $LBHOME/system/apache2/envvars 

# Environment Variablen laden
source /etc/environment

# LoxBerry global environment variables in Apache
if [ -z $LBSSBIN ]; then
	FAIL "Could not set systemwide environments.\n"
	exit 1
else
	OK "Successfully set systemwide environments."
fi

# Configuring sudoers
TITLE "Setting up sudoers..."

# sudoers.d
if [ -d /etc/sudoers.d ]; then
	mv /etc/sudoers.d /etc/sudoers.d.orig
fi
if [ -L /etc/sudoers.d ]; then
	rm /etc/sudoers.d
fi
ln -s $LBHOME/system/sudoers/ /etc/sudoers.d

# sudoers: Replace /opt/loxberry with current home path
/usr/bin/sed -i -e "s#/opt/loxberry/#$LBHOME/#g" $LBHOME/system/sudoers/lbdefaults

if [ ! -L /etc/sudoers.d ]; then
	FAIL "Could not set up sudoers.\n"
	exit 1
else
	OK "Successfully set up sudoers."
fi

# Configuring profile
TITLE "Setting up profile for user 'loxberry'sudoers..."

# profile.d/loxberry.sh
if [ -L /etc/profile.d/loxberry.sh ]; then
	rm /etc/profile.d/loxberry.sh
fi
ln -s $LBHOME/system/profile/loxberry.sh /etc/profile.d/loxberry.sh

if [ ! -L /etc/profile.d/loxberry.sh ]; then
	FAIL "Could not set up profile for user 'loxberry'.\n"
	exit 1
else
	OK "Successfully set up profile for user 'loxberry'."
fi

# Setting up Initskript for LoxBerry
TITLE "Setting up Service files for LoxBerry..."

# LoxBerry Init Script
if [ -e /etc/systemd/system/loxberry.service ]; then
	rm /etc/systemd/system/loxberry.service
fi
ln -s $LBHOME/system/systemd/loxberry.service /etc/systemd/system/loxberry.service
/usr/bin/echo ""
/bin/systemctl daemon-reload
/bin/systemctl enable loxberry.service

if ! /bin/systemctl is-enabled loxberry.service; then
	FAIL "Could not set up Service for LoxBerry.\n"
	exit 1
else
	OK "Successfully set up service for LoxBerry."
fi

# Createtmpfs Init Script
if [ -e /etc/systemd/system/createtmpfs.service ]; then
	rm /etc/systemd/system/createtmpfs.service
fi
ln -s $LBHOME/system/systemd/createtmpfs.service /etc/systemd/system/createtmpfs.service
/usr/bin/echo ""
/bin/systemctl daemon-reload
/bin/systemctl enable createtmpfs.service

if ! /bin/systemctl is-enabled createtmpfs.service; then
	FAIL "Could not set up Service for Createtmpfs.\n"
	exit 1
else
	OK "Successfully set up service for Createtmpfs."
fi

# LoxBerry SSDPD Service
if [ -e /etc/systemd/system/ssdpd.service ]; then
	rm /etc/systemd/system/ssdpd.service
fi
ln -s $LBHOME/system/systemd/ssdpd.service /etc/systemd/system/ssdpd.service
/usr/bin/echo ""
/bin/systemctl daemon-reload
/bin/systemctl enable ssdpd.service

if ! /bin/systemctl is-enabled ssdpd.service; then
	FAIL "Could not set up Service for SSDPD.\n"
	exit 1
else
	OK "Successfully set up service for SSDPD."
fi

# LoxBerry Mosquitto Service
# Integrate LoxBerry's mosquitto needs (tmpfs logfile, createtmpfs boot-ordering)
# as a systemd DROP-IN that EXTENDS the distro unit - not the old
# /etc/systemd/system/mosquitto.service whole-unit symlink, which shadowed the
# distro unit and was silently lost on mosquitto package upgrades. A drop-in is
# never touched by dpkg, and is kept in sync at runtime by mqtt-handler.pl
# (ensure_mosquitto_dropin).
# Remove any stale whole-unit override so the distro unit stays the base.
if [ -e /etc/systemd/system/mosquitto.service ] || [ -L /etc/systemd/system/mosquitto.service ]; then
	rm -f /etc/systemd/system/mosquitto.service
fi
mkdir -p /etc/systemd/system/mosquitto.service.d
cat > /etc/systemd/system/mosquitto.service.d/loxberry.conf <<'MOSQEOF'
# Managed by LoxBerry - do not edit.
# Extends the distro mosquitto.service with LoxBerry's tmpfs logfile and
# createtmpfs boot-ordering. A drop-in survives mosquitto package upgrades.
[Unit]
After=createtmpfs.service
Requires=createtmpfs.service

[Service]
EnvironmentFile=/etc/environment
ExecStartPre=/bin/mkdir -m 740 -p /var/log/mosquitto
ExecStartPre=/bin/chown mosquitto /var/log/mosquitto
ExecStartPre=/bin/touch ${LBSTMPFSLOG}/mosquitto.log
ExecStartPre=/bin/chown mosquitto:loxberry ${LBSTMPFSLOG}/mosquitto.log
ExecStartPre=/bin/chmod 640 ${LBSTMPFSLOG}/mosquitto.log
ExecStartPre=/bin/ln -sf ${LBSTMPFSLOG}/mosquitto.log /var/log/mosquitto/mosquitto.log
MOSQEOF
chmod 644 /etc/systemd/system/mosquitto.service.d/loxberry.conf
/usr/bin/echo ""
/bin/systemctl daemon-reload
/bin/systemctl enable mosquitto.service

if ! /bin/systemctl is-enabled mosquitto.service; then
	FAIL "Could not set up Service for Mosquitto.\n"
	exit 1
else
	OK "Successfully set up service for Mosquitto."
fi

# PHP - we install PHP8.x for testing and 7.4 for production
TITLE "Configuring PHP ${PHPVER_PROD}..."

if [ ! -e /etc/php/${PHPVER_PROD} ]; then
	FAIL "Could not set up PHP - target folder /etc/php/${PHPVER_PROD} does not exist.\n"
	exit 1
fi

mkdir -p /etc/php/${PHPVER_PROD}/apache2/conf.d
mkdir -p /etc/php/${PHPVER_PROD}/cgi/conf.d
mkdir -p /etc/php/${PHPVER_PROD}/cli/conf.d
rm /etc/php/${PHPVER_PROD}/apache2/conf.d/20-loxberry.ini
rm /etc/php/${PHPVER_PROD}/cgi/conf.d/20-loxberry.ini
rm /etc/php/${PHPVER_PROD}/cli/conf.d/20-loxberry.ini
ln -s $LBHOME/system/php/loxberry-apache.ini /etc/php/${PHPVER_PROD}/apache2/conf.d/20-loxberry-apache.ini
ln -s $LBHOME/system/php/loxberry-apache.ini /etc/php/${PHPVER_PROD}/cgi/conf.d/20-loxberry-apache.ini
ln -s $LBHOME/system/php/loxberry-cli.ini /etc/php/${PHPVER_PROD}/cli/conf.d/20-loxberry-cli.ini

if [ ! -L  /etc/php/${PHPVER_PROD}/apache2/conf.d/20-loxberry-apache.ini ]; then
	FAIL "Could not set up PHP ${PHPVER_PROD}.\n"
	exit 1
else
	OK "Successfully set up PHP ${PHPVER_PROD}."
fi

TITLE "Configuring PHP ${PHPVER_TEST}..."

if [ ! -e /etc/php/${PHPVER_TEST} ]; then
	FAIL "Could not set up PHP - target folder /etc/php/${PHPVER_TEST} does not exist.\n"
	exit 1
fi

mkdir -p /etc/php/${PHPVER_TEST}/apache2/conf.d
mkdir -p /etc/php/${PHPVER_TEST}/cgi/conf.d
mkdir -p /etc/php/${PHPVER_TEST}/cli/conf.d
rm /etc/php/${PHPVER_TEST}/apache2/conf.d/20-loxberry.ini
rm /etc/php/${PHPVER_TEST}/cgi/conf.d/20-loxberry.ini
rm /etc/php/${PHPVER_TEST}/cli/conf.d/20-loxberry.ini
ln -s $LBHOME/system/php/loxberry-apache.ini /etc/php/${PHPVER_TEST}/apache2/conf.d/20-loxberry-apache.ini
ln -s $LBHOME/system/php/loxberry-apache.ini /etc/php/${PHPVER_TEST}/cgi/conf.d/20-loxberry-apache.ini
ln -s $LBHOME/system/php/loxberry-cli.ini /etc/php/${PHPVER_TEST}/cli/conf.d/20-loxberry-cli.ini

if [ ! -L  /etc/php/${PHPVER_TEST}/apache2/conf.d/20-loxberry-apache.ini ]; then
	FAIL "Could not set up PHP ${PHPVER_TEST}.\n"
	exit 1
else
	OK "Successfully set up PHP ${PHPVER_TEST}."
fi

TITLE "Enabling PHP ${PHPVER_PROD}..."
/usr/bin/update-alternatives --set php /usr/bin/php${PHPVER_PROD}


# Configuring Apache2
TITLE "Configuring Apache2..."

# Apache Config
if [ ! -L /etc/apache2 ]; then
	mv /etc/apache2 /etc/apache2.orig
fi
if [ -L /etc/apache2 ]; then  
    rm /etc/apache2
fi
ln -s $LBHOME/system/apache2 /etc/apache2
if [ ! -L /etc/apache2 ]; then
	FAIL "Could not set up Apache2 Config.\n"
	exit 1
else
	OK "Successfully set up Apache2 Config."
fi

# Apache logs stay in the distro default /var/log/apache2 - provide the
# stable LoxBerry path log/system_tmpfs/apache2 as a symlink
mkdir -p /var/log/apache2
rm -rf $LBHOME/log/system_tmpfs/apache2
ln -sfn /var/log/apache2 $LBHOME/log/system_tmpfs/apache2
if [ ! -L $LBHOME/log/system_tmpfs/apache2 ]; then
	FAIL "Could not set up Apache2 log directory symlink.\n"
	exit 1
else
	OK "Successfully set up Apache2 log directory symlink."
fi

/usr/sbin/a2dismod php*
/usr/sbin/a2dissite 001-default-ssl
rm $LBHOME/system/apache2/mods-available/php*
rm $LBHOME/system/apache2/mods-enabled/php*
cp /etc/apache2.orig/mods-available/php* /etc/apache2/mods-available
/usr/sbin/a2enmod php${PHPVER_PROD}

# Disable PrivateTmp for Apache2 on systemd
if [ ! -e /etc/systemd/system/apache2.service.d/privatetmp.conf ]; then
	mkdir -p /etc/systemd/system/apache2.service.d
	ln -s $LBHOME/system/systemd/apache-privatetmp.conf /etc/systemd/system/apache2.service.d/privatetmp.conf
fi

if [ ! -L  /etc/systemd/system/apache2.service.d/privatetmp.conf ]; then
	FAIL "Could not set up Apache2 Private Temp Config.\n"
	exit 1
else
	OK "Successfully set up Apache2 Private Temp Config."
fi

# Configuring Python 3 - reenable pip installations
TITLE "Configuring Python3..."

/usr/bin/echo -e '[global]\nbreak-system-packages=true' > /etc/pip.conf
if [ -e /etc/pip.conf ]; then
	OK "Python3 configured successfully.\n"
else
	FAIL "Could not set up Python 3.\n"
	exit 1
fi

# Configuring Samba
TITLE "Configuring Samba..."

if [ ! -L /etc/samba ]; then
	mv /etc/samba /etc/samba.old
fi
if [ -L /etc/samba ]; then
    rm /etc/samba
fi
ln -s $LBHOME/system/samba /etc/samba
/usr/bin/sed -i -e "s#/opt/loxberry/#$LBHOME/#g" $LBHOME/system/samba/smb.conf

if [ ! -L /etc/samba ]; then
	FAIL "Could not set up Samba Config.\n"
	exit 1
fi

if ! testparm -s --debuglevel=1 $LBHOME/system/samba/smb.conf; then
	FAIL "Could not set up Samba Config.\n"
	exit 1
else
	OK "Successfully set up Samba Config."
fi

if /bin/systemctl --no-pager status smbd; then
	/bin/systemctl restart smbd
fi
if /bin/systemctl --no-pager status nmbd; then
	/bin/systemctl restart nmbd
fi

if ! /bin/systemctl --no-pager status smbd; then
	FAIL "Could not reconfigure Samba.\n"
	exit 1
else
	OK "Successfully reconfigured Samba."
fi

# Add Samba default user
(/usr/bin/echo 'loxberry'; echo 'loxberry') | /usr/bin/smbpasswd -a -s loxberry

# Configuring VSFTP
TITLE "Configuring VSFTP..."

if [ ! -L /etc/vsftpd.conf ]; then
	mv /etc/vsftpd.conf /etc/vsftpd.conf.old
fi
if [ -L /etc/vsftpd.conf ]; then
    rm /etc/vsftpd.conf
fi
ln -s $LBHOME/system/vsftpd/vsftpd.conf /etc/vsftpd.conf

if [ ! -L /etc/vsftpd.conf ]; then
	FAIL "Could not set up VSFTPD Config.\n"
	exit 1
else
	OK "Successfully set up VSFTPD Config."
fi

if /bin/systemctl --no-pager status vsftpd; then
	/bin/systemctl restart vsftpd
fi

if ! /bin/systemctl --no-pager status vsftpd; then
	FAIL "Could not reconfigure VSFTPD.\n"
	exit 1
else
	OK "Successfully reconfigured VSFTPD."
fi

# Configuring MSMTP
TITLE "Configuring MSMTP..."

if [ -d $LBHOME/system/msmtp ]; then
	rm /etc/msmtprc
	ln -s $LBHOME/system/msmtp/msmtprc /etc/msmtprc
	chmod 0600 $LBHOME/system/msmtp/msmtprc
fi
chmod 0600 $LBHOME/system/msmtp/aliases

if [ ! -e /etc/msmtprc ]; then
	FAIL "Could not set up MSMTP Config.\n"
	exit 1
else
	OK "Successfully set up MSMTP Config."
fi

# Cron.d
TITLE "Configuring Cron.d..."

if [ ! -L /etc/cron.d ]; then
	mv /etc/cron.d /etc/cron.d.orig
fi
if [ -L /etc/cron.d ]; then
    rm /etc/cron.d
fi
ln -s $LBHOME/system/cron/cron.d /etc/cron.d

if [ ! -L /etc/cron.d ]; then
	FAIL "Could not set up Cron.d.\n"
	exit 1
else
	OK "Successfully set up Cron.d."
fi
cp /etc/cron.d.orig/* /etc/cron.d

# USB Mounts
TITLE "Configuring automatic USB Mounts..."

# Systemd service for usb automount
mkdir -p /media/usb
if [ -e /etc/systemd/system/usb-mount@.service ]; then
	rm /etc/systemd/system/usb-mount@.service
fi
ln -s $LBHOME/system/systemd/usb-mount@.service /etc/systemd/system/usb-mount@.service

# Create udev rules for usbautomount
if [ -e /etc/udev/rules.d/99-usbmount.rules ]; then
	rm /etc/udev/rules.d/99-usbmount.rules
fi
ln -s $LBHOME/system/udev/usbmount.rules /etc/udev/rules.d/99-usbmount.rules
/usr/bin/sed -i -e "s#/opt/loxberry/#$LBHOME/#g" $LBHOME/system/udev/usbmount.rules 

/bin/systemctl daemon-reload

if [ ! -L /etc/systemd/system/usb-mount@.service ]; then
	FAIL "Could not set up Service for USB-Mount.\n"
	exit 1
else
	OK "Successfully set up service for USB-Mount."
fi
if [ ! -L /etc/udev/rules.d/99-usbmount.rules ]; then
	FAIL "Could not set up udev Rules for USB-Mount.\n"
	exit 1
else
	OK "Successfully set up udev Rules for USB-Mount."
fi

# Configure autofs
TITLE "Configuring AutoFS for Samba Netshares..."

mkdir -p /media/smb
if [ -L /etc/creds ]; then
    rm /etc/creds
fi
ln -s $LBHOME/system/samba/credentials /etc/creds
/usr/bin/sed -i -e "s#/opt/loxberry/#$LBHOME/#g" $LBHOME/system/autofs/loxberry_smb.autofs
ln -s $LBHOME/system/autofs/loxberry_smb.autofs /etc/auto.master.d/loxberry_smb.autofs
chmod 0755 $LBHOME/system/autofs/loxberry_smb.autofs
rm $LBHOME/system/storage/smb/.dummy
/bin/systemctl restart autofs

if ! /bin/systemctl --no-pager status autofs; then
	FAIL "Could not reconfigure AutoFS.\n"
	exit 1
else
	OK "Successfully reconfigured AutoFS."
fi

# Config for watchdog
TITLE "Configuring Watchdog..."

/bin/systemctl disable watchdog.service
/bin/systemctl stop watchdog.service

if [ ! -L /etc/watchdog.conf ]; then
	mv /etc/watchdog.conf /etc/watchdog.orig
fi
if [ -L /etc/watchdog.conf ]; then
    rm /etc/watchdog.conf
fi
if ! cat /etc/default/watchdog | grep -q -e "watchdog_options"; then
	/usr/bin/echo 'watchdog_options="-v"' >> /etc/default/watchdog
fi
if ! cat /etc/default/watchdog | /usr/bin/grep -q -e "watchdog_options.*-v"; then
	/usr/bin/sed -i 's#watchdog_options="\(.*\)"#watchdog_options="\1 -v"#' /etc/default/watchdog
fi
/usr/bin/sed -i -e "s#/opt/loxberry/#$LBHOME/#g" $LBHOME/system/watchdog/rsyslog.conf
ln -f -s $LBHOME/system/watchdog/watchdog.conf /etc/watchdog.conf
ln -f -s $LBHOME/system/watchdog/rsyslog.conf /etc/rsyslog.d/10-watchdog.conf
/bin/systemctl restart rsyslog.service

if [ ! -L /etc/watchdog.conf ]; then
	FAIL "Could not reconfigure Watchdog.\n"
	exit 1
else
	OK "Successfully reconfigured Watchdog."
fi

# Activating i2c
TITLE "Enabling I2C (if supported)..."

/boot/dietpi/func/dietpi-set_hardware i2c enable

# Set hosts environment
TITLE "Setting hosts environment..."

rm /etc/network/if-up.d/001hosts
rm /etc/dhcp/dhclient-exit-hooks.d/sethosts
ln -f -s $LBHOME/sbin/sethosts.sh /etc/network/if-up.d/001host
ln -f -s $LBHOME/sbin/sethosts.sh /etc/dhcp/dhclient-exit-hooks.d/sethosts 

if [ ! -L /etc/network/if-up.d/001host ]; then
	FAIL "Could not set host environment.\n"
	exit 1
else
	OK "Successfully set host environment."
fi

# Configure listchanges to have no output - for apt beeing non-interactive
TITLE "Configuring listchanges to be quit..."

if [ -e /etc/apt/listchanges.conf ]; then
	/usr/bin/sed -i 's/frontend=pager/frontend=none/' /etc/apt/listchanges.conf
fi

OK "Successfully configured listchanges."

# Reconfigure PAM
TITLE "Reconfigure PAM to allow shorter (weaker) passwords..."

sed -i 's/obscure/minlen=1/' /etc/pam.d/common-password

if ! /usr/bin/cat /etc/pam.d/common-password | /usr/bin/grep -q "minlen="; then
	FAIL "Could not reconfigure PAM.\n"
	exit 1
else
	OK "Successfully reconfigured PAM."
fi

# Reconfigure Unattended Updates
TITLE "Reconfigure Unattended Updates for LoxBerry..."

if [ -e /etc/apt/apt.conf.d/02periodic ]; then
    rm /etc/apt/apt.conf.d/02periodic
fi
if [ -e /etc/apt/apt.conf.d/50unattended-upgrades ]; then
    rm /etc/apt/apt.conf.d/50unattended-upgrades
fi
ln -f -s $LBHOME/system/unattended-upgrades/periodic.conf /etc/apt/apt.conf.d/02periodic
ln -f -s $LBHOME/system/unattended-upgrades/unattended-upgrades.conf /etc/apt/apt.conf.d/50unattended-upgrades

if [ ! -L /etc/apt/apt.conf.d/50unattended-upgrades ]; then
	FAIL "Could not reconfigure Unattended Updates.\n"
	exit 1
else
	OK "Successfully reconfigured Unattended Updates."
fi

/bin/systemctl enable unattended-upgrades

if ! /bin/systemctl is-enabled unattended-upgrades; then
	FAIL "Could not enable  Unattended Updates.\n"
	exit 1
else
	OK "Successfully enabled Unattended Updates."
fi

# Enable LoxBerry Update after next reboot
TITLE "Enable LoxBerry update after next reboot..."
/usr/bin/touch $LBHOME/config/system/do_lbupdate

if [ ! -e $LBHOME/config/system/do_lbupdate ]; then
	FAIL "Could not enable LoxBerry Update.\n"
	exit 1
else
	OK "Successfully enabled LoxBerry Update."
fi

# Automatically repair filesystem errors on boot
TITLE "Automatically repair filesystem errors on boot..."

if [ ! -f /etc/default/rcS ]; then
	/usr/bin/echo "FSCKFIX=yes" > /etc/default/rcS
else
	if ! cat /etc/default/rcS | grep -q "FSCKFIX"; then
		/usr/bin/echo "FSCKFIX=yes" >> /etc/default/rcS
	fi
fi

if [ ! -f /etc/default/rcS ]; then
	FAIL "Could not configure FSCK / rcS.\n"
	exit 1
else
	OK "Successfully configured FSCK / rcS."
fi

# Disable SSH Root password access
TITLE "Disable root login via ssh and password..."
/boot/dietpi/func/dietpi-set_software disable_ssh_password_logins root

# Installing NodeJS
TITLE "Installing NodeJS"
/boot/dietpi/dietpi-software install 9

# Installing YARN
TITLE "Installing Yarn"
/usr/bin/curl -sL https://dl.yarnpkg.com/debian/pubkey.gpg | /usr/bin/gpg --dearmor | /usr/bin/tee /usr/share/keyrings/yarnkey.gpg >/dev/null
/usr/bin/echo "deb [signed-by=/usr/share/keyrings/yarnkey.gpg] https://dl.yarnpkg.com/debian stable main" | /usr/bin/tee /etc/apt/sources.list.d/yarn.list

/usr/bin/apt-get -y --allow-unauthenticated --allow-downgrades --allow-remove-essential --allow-change-held-packages --allow-releaseinfo-change update
/usr/bin/apt-get --no-install-recommends -y --allow-unauthenticated --fix-broken --reinstall --allow-downgrades --allow-remove-essential --allow-change-held-packages install yarn

# Configuring /etc/hosts
TITLE "Setting up /etc/hosts and /etc/hostname..."

/usr/bin/touch /etc/mailname
$LBHOME/sbin/changehostname.sh loxberry

OK "Successfully set up /etc/hosts."

# Set correct File Permissions
TITLE "Setting File Permissions..."

$LBHOME/sbin/resetpermissions.sh

if [ $? != 0 ]; then
	FAIL "Could not set File Permissions for LoxBerry.\n"
	exit 1
else
	OK "Successfully set File Permissions for LoxBerry."
fi

# Create Config
TITLE "Create LoxBerry Config from Defaults..."
/usr/bin/su loxberry -c "export PERL5LIB=$LBHOME/libs/perllib && $LBHOME/bin/createconfig.pl"
/usr/bin/su loxberry -c "export PERL5LIB=$LBHOME/libs/perllib && $LBHOME/bin/createconfig.pl" # Run twice
# Set MQTT Gateway to V2 (due to updates the default is V1 still)
/usr/bin/jq '.Mqtt.Gatewayversion = 2' /opt/loxberry/config/system/general.json > /tmp/gj.tmp && mv /tmp/gj.tmp /opt/loxberry/config/system/general.json
export PERL5LIB=$LBHOME/libs/perllib && $LBHOME/sbin/mqtt-handler.pl action=updateconfig

# Create Python venv for MQTT Gateway V2
TITLE "Creating Python venv for MQTT Gateway V2..."
python3 -m venv $LBHOME/system/python_venv/mqttgateway
$LBHOME/system/python_venv/mqttgateway/bin/pip install -q -r $LBHOME/system/python_venv/requirements_mqttgateway.txt
chown -R loxberry:loxberry $LBHOME/system/python_venv
OK "Python venv for MQTT Gateway V2 created."

if [ ! -e $LBHOME/config/system/general.json ]; then
	FAIL "Could not create default config files.\n"
	exit 1
else
	OK "Successfully created default config files."
fi

# MQTT Gateway compatibility
ln -f -s $LBHOME/webfrontend/html/system/tools/mqtt/receive.php $LBHOME/webfrontend/html/plugins/mqttgateway/receive.php
ln -f -s $LBHOME/webfrontend/html/system/tools/mqtt/receive_pub.php $LBHOME/webfrontend/html/plugins/mqttgateway/receive_pub.php
ln -f -s $LBHOME/webfrontend/htmlauth/system/tools/mqtt.php $LBHOME/webfrontend/htmlauth/plugins/mqttgateway/mqtt.php
chown -R loxberry:loxberry $LBHOME/webfrontend/htmlauth/plugins/mqttgateway
chown -R loxberry:loxberry $LBHOME/webfrontend/html/plugins/mqttgateway
chown -R loxberry:loxberry $LBHOME/webfrontend/html/system/tools/mqtt

# Set Timezone to LoxBerry's Standard
TITLE "Setting Timezone to Default..."
/usr/bin/timedatectl set-timezone Europe/Berlin
/usr/sbin/dpkg-reconfigure -f noninteractive tzdata
/usr/bin/timedatectl

# Restart Systemd Login Service
TITLE "Correct Systemd Login Service..."

/bin/systemctl unmask systemd-logind.service
/bin/systemctl start systemd-logind.service

# Start Apache
TITLE "Start Apache2 Webserver..."

/bin/systemctl restart apache2

if ! /bin/systemctl --no-pager status apache2; then
       FAIL "Could not reconfigure Apache2.\n"
       exit 1
else
       OK "Successfully reconfigured Apache2."
fi

# Install some default configs for root
TITLE "Installing some default config files for root..."
cp $LBHOME/.vimrc /root
cp $LBHOME/.profile /root

# Set correct File Permissions - again
TITLE "Setting File Permissions (again)..."
$LBHOME/sbin/resetpermissions.sh

if [ $? != 0 ]; then
	FAIL "Could not set File Permissions for LoxBerry.\n"
	exit 1
else
	OK "Successfully set File Permissions for LoxBerry."
fi

# The end
export PERL5LIB=$LBHOME/libs/perllib
IP=$(/usr/bin/perl -e 'use LoxBerry::System; $ip = LoxBerry::System::get_localip(); print $ip; exit;')
/usr/bin/echo -e "\n\n\n${GREEN}WE ARE DONE! :-)${RESET}"
/usr/bin/echo -e "\n\n${RED}If you are *NOT* connected via ethernet and dhcp, configure your"
/usr/bin/echo -e "network now with dietpi-config!"
/usr/bin/echo -e "\nIf you are done, you have to reboot your LoxBerry now!${RESET}"
/usr/bin/echo -e "\n${GREEN}Then point your browser to http://$IP or http://loxberry"
/usr/bin/echo -e "\nUse user 'loxberry' and pass 'loxberry' for the first login to the"
/usr/bin/echo -e "webinterface. It is strongly recommended to change your password during"
/usr/bin/echo -e "initial setup."
/usr/bin/echo -e "\nIf you would like to login via SSH at a later time, use user 'loxberry'"
/usr/bin/echo -e "and the password you have configured."
/usr/bin/echo -e "\nRoot's password was changed by yourself during initial setup of dietpi."
/usr/bin/echo -e "If you have not saved this password, you may reset the root password"
/usr/bin/echo -e "with the LoxBerry-Reset-Root plugin. See https://wiki.loxberry.de for"
/usr/bin/echo -e "details."
/usr/bin/echo -e "\nGood Bye.\n\n${RESET}"

exit 0
