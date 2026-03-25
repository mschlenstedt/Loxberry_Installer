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

if [ -e /boot/rootfsresized ]; then
	echo "This script was already executed on this LoxBerry. You cannot reinstall LoxBerry."
	echo "If you are sure what you are doing, rm /boot/rootfsresized and restart again."
	exit 1
fi

echo -e "\n\nNote! If you were logged in as user 'loxberry' and used 'su' to switch to the root account, your connection may be lost now...\n\n"
/usr/bin/killall -u loxberry 2>/dev/null
sleep 3

# Commandline options
while getopts "t:b:" o; do
    case "${o}" in
        t) TAG=${OPTARG} ;;
        b) BRANCH=${OPTARG} ;;
        *) ;;
    esac
done
shift $((OPTIND-1))

# Install needed packages
/usr/bin/apt-get -y --allow-unauthenticated --allow-downgrades --allow-remove-essential --allow-change-held-packages --allow-releaseinfo-change update
/usr/bin/apt-get --no-install-recommends -y --allow-unauthenticated --fix-broken --reinstall --allow-downgrades --allow-remove-essential --allow-change-held-packages install jq git lsb-release

# ---- Stop existing services ----
for svc in apache2 loxberry ssdpd mosquitto; do
        systemctl stop $svc.service 2>/dev/null
        systemctl disable $svc.service 2>/dev/null
done

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

# Read Distro Info
[ -e /etc/os-release ] && . /etc/os-release
[ -e /boot/dietpi/.hw_model ] && . /boot/dietpi/.hw_model
[ -e /boot/dietpi/.version ] && . /boot/dietpi/.version

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
if [ -z "$TAG" ]; then TARGETRELEASE="latest"; else TARGETRELEASE="tags/$TAG"; fi

if [ -n "$BRANCH" ]; then
        LBVERSION="Branch $BRANCH (latest)"
else
        RELEASEJSON=$(curl -s -H "Accept: application/vnd.github+json" \
                https://api.github.com/repos/mschlenstedt/Loxberry/releases/$TARGETRELEASE)
        LBVERSION=$(echo "$RELEASEJSON" | jq -r ".tag_name")
        LBTARBALL=$(echo "$RELEASEJSON" | jq -r ".tarball_url")
        if [ -z "$LBVERSION" ] || [ "$LBVERSION" = "null" ]; then
                FAIL "Cannot get release info from GitHub."; exit 1
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
/usr/bin/echo -e "\n\nHit ${BOLD}<CTRL>+C${RESET} now to stop, any other input will continue.\n"
read -n 1 -s -r -p "Press any key to continue"
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

# Adding User loxberry
TITLE "Adding user 'loxberry', setting default passwd, resetting user 'dietpi'..."

/usr/bin/killall -u loxberry > /dev/null 2>&1
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

/usr/bin/echo 'root:loxberry' | /usr/sbin/chpasswd -c SHA512
if [ $? != 0 ]; then
	FAIL "Could not set password for user 'root'.\n"
	exit 1
else
	OK "Successfully set default password for user 'root'."
fi

newdietpipassword=$(/usr/bin/echo $random | /usr/bin/md5sum | /usr/bin/head -c 20; echo)
/usr/bin/echo "dietpi:$newdietpipassword" | /usr/sbin/chpasswd -c SHA512
if [ $? != 0 ]; then
	FAIL "Could not set password for user 'dietpi'.\n"
	exit 1
else
	OK "Successfully set default password for user 'dietpi'."
fi


# Configuring hardware architecture
TITLE "Configuring your hardware architecture $G_HW_ARCH_NAM..."

HWMODELFILENAME=$(/usr/bin/cat /boot/dietpi/func/dietpi-obtain_hw_model | /usr/bin/grep "G_HW_MODEL $G_HW_MODEL " | /usr/bin/awk '/.*G_HW_MODEL .*/ {for(i=4; i<=NF; ++i) printf "%s_", $i; print ""}' | /usr/bin/sed 's/\//_/g' | /usr/bin/sed 's/[()]//g' | /usr/bin/sed 's/_$//' | /usr/bin/tr '[:upper:]' '[:lower:]')
/usr/bin/echo $HWMODELFILENAME > $LBHOME/config/system/is_hwmodel_$HWMODELFILENAME.cfg
/usr/bin/echo $G_HW_ARCH_NAME > $LBHOME/config/system/is_arch_$G_HW_ARCH_NAME.cfg

# Compatibility - this was standard until LB3.0.0.0
if /usr/bin/echo $HWMODELFILENAME | /usr/bin/grep -q "x86_64"; then
	/usr/bin/echo "x64" > $LBHOME/config/system/is_x64.cfg
fi
if /usr/bin/echo $HWMODELFILENAME | /usr/bin/grep -q "raspberry"; then
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

# ---- NodeJS (via DietPi) ----
TITLE "Installing NodeJS..."
/boot/dietpi/dietpi-software install 9

# Installing packages
TITLE "Installing additional software packages from apt repository..."

/boot/dietpi/func/dietpi-set_software apt reset
/boot/dietpi/func/dietpi-set_software apt compress disable
/boot/dietpi/func/dietpi-set_software apt clean

# Configure PHP - we want PHP7.4 as default (still...)
/usr/bin/curl -sL https://packages.sury.org/php/apt.gpg | /usr/bin/gpg --dearmor | /usr/bin/tee /usr/share/keyrings/deb.sury.org-php.gpg >/dev/null
/usr/bin/echo "deb [signed-by=/usr/share/keyrings/deb.sury.org-php.gpg] https://packages.sury.org/php/ $(lsb_release -sc) main" > /etc/apt/sources.list.d/php.list

# Yarn Repo
curl -sL https://dl.yarnpkg.com/debian/pubkey.gpg | gpg --dearmor | tee /usr/share/keyrings/yarnkey.gpg >/dev/null
echo "deb [signed-by=/usr/share/keyrings/yarnkey.gpg] https://dl.yarnpkg.com/debian stable main" > /etc/apt/sources.list.d/yarn.list

/usr/bin/apt-get -y --allow-unauthenticated --allow-downgrades --allow-remove-essential --allow-change-held-packages --allow-releaseinfo-change update

if [ ! -e "$LBHOME/packages${TARGET_VERSION_ID}.txt" ]; then
        FAIL "Missing: $LBHOME/packages${TARGET_VERSION_ID}.txt"
	exit 1
fi

# Alle gewuenschten Paketnamen extrahieren (Zeilen die mit "ii " beginnen)
#WANTED=$(awk '/^ii / {print $2}' "$LBHOME/packages${TARGET_VERSION_ID}.txt" | sed 's/:.*$//')
#
# Bereits installierte Pakete
#INSTALLED=$(dpkg-query -W -f='${Package}\n' 2>/dev/null | sort -u)
#
# Verfuegbare Pakete (im Repo vorhanden)
#AVAILABLE=$(apt-cache pkgnames 2>/dev/null | sort -u)
#
# Delta: gewuenscht, verfuegbar, aber noch nicht installiert
#PACKAGES=""
#SKIPPED_NOTFOUND=""
#for pkg in $WANTED; do
#        if echo "$AVAILABLE" | grep -qx "$pkg"; then
#                if ! echo "$INSTALLED" | grep -qx "$pkg"; then
#                        PACKAGES+="$pkg "
#                fi
#        else
#                SKIPPED_NOTFOUND+="$pkg "
#        fi
#done
#
## Yarn dazu (kommt aus dem gerade eingerichteten Repo)
#if ! echo "$INSTALLED" | grep -qx "yarn"; then
#        PACKAGES+="yarn "
#fi
#
#if [ -n "$SKIPPED_NOTFOUND" ]; then
#        WARNING "Packages not found in repos (skipped): $SKIPPED_NOTFOUND"
#fi
#
#echo -e "\n${BOLD}Installing $(echo $PACKAGES | wc -w) packages...${RESET}\n"
#
#/usr/bin/apt-get --no-install-recommends -y --allow-unauthenticated --fix-broken --reinstall --allow-downgrades --allow-remove-essential --allow-change-held-packages install $PACKAGES
#if [ $? != 0 ]; then
#        FAIL "Could not install (at least some) queued packages.\n"
#	exit 1
#else
#        OK "Successfully installed all queued packages.\n"
#fi

if [ -e "$LBHOME/packages${TARGET_VERSION_ID}.txt" ]; then
        PACKAGES=""
        /usr/bin/echo ""
        while read entry
        do
                if /usr/bin/echo $entry | /usr/bin/grep -Eq "^ii "; then
                        VAR=$(/usr/bin/echo $entry | sed "s/  / /g" | /usr/bin/cut -d " " -f 2 | /usr/bin/sed "s/:.*\$//")
                        PINFO=$(/usr/bin/apt-cache show $VAR 2>&1)
                        if /usr/bin/echo $PINFO | /usr/bin/grep -Eq "N: Unable to locate"; then
                        	WARNING "Unable to locate package $PACKAGE. Skipping..."
                                continue
                        fi
                        PACKAGE=$(echo $PINFO | /usr/bin/grep "Package: " | /usr/bin/cut -d " " -f 2)
			if [ -z $PACKAGE ] || [ $PACKAGE = "" ]; then
				continue
			fi
                        if /usr/bin/dpkg -s $PACKAGE > /dev/null 2>&1; then
                        	INFO "$PACKAGE seems to be already installed. Skipping..."
                                continue
                        fi
                        OK "Add package $PACKAGE to the installation queue..."
                        PACKAGES+="$PACKAGE "
                fi
        done < "$LBHOME/packages${TARGET_VERSION_ID}.txt"
else
        FAIL "Could not find packages list: $LBHOME/packages$TARGET_VERSION_ID.txt.\n"
        exit 1
fi

/usr/bin/echo ""
/usr/bin/echo "These packages will be installed now:"
/usr/bin/echo $PACKAGES
/usr/bin/echo ""

/usr/bin/apt-get --no-install-recommends -y --allow-unauthenticated --fix-broken --reinstall --allow-downgrades --allow-remove-essential --allow-change-held-packages install $PACKAGES
if [ $? != 0 ]; then
        FAIL "Could not install (at least some) queued packages.\n"
	exit 1
else
        OK "Successfully installed all queued packages.\n"
fi

/boot/dietpi/func/dietpi-set_software apt compress enable
/boot/dietpi/func/dietpi-set_software apt clean

# Removing unwanted packages
TITLE "Removing unwanted packages..."
/usr/bin/apt-get --no-install-recommends -y --allow-unauthenticated --fix-broken --reinstall --allow-downgrades --allow-remove-essential --allow-change-held-packages purge dhcpcd5 apparmor autoremove

/boot/dietpi/func/dietpi-set_software apt cache clean

# Adding user loxberry to different additional groups
TITLE "Adding user LoxBerry to some additional groups..."
for grp in dialout audio gpio tty www-data video i2c dietpi; do
        usermod -a -G $grp loxberry 2>/dev/null
done
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

for svc in loxberry createtmpfs ssdpd mosquitto; do
        rm -f /etc/systemd/system/${svc}.service
        ln -s $LBHOME/system/systemd/${svc}.service /etc/systemd/system/${svc}.service
done

# USB-Mount Service
mkdir -p /media/usb
rm -f /etc/systemd/system/usb-mount@.service
ln -s $LBHOME/system/systemd/usb-mount@.service /etc/systemd/system/usb-mount@.service

# Apache PrivateTmp
mkdir -p /etc/systemd/system/apache2.service.d
[ ! -e /etc/systemd/system/apache2.service.d/privatetmp.conf ] && \
        ln -s $LBHOME/system/systemd/apache-privatetmp.conf /etc/systemd/system/apache2.service.d/privatetmp.conf

# EIN daemon-reload fuer alles
systemctl daemon-reload
systemctl enable loxberry createtmpfs ssdpd mosquitto unattended-upgrades
OK "All services configured."

# PHP - we install PHP8.4 for testing and 7.4 for production
TITLE "Configuring PHP ${PHPVER_PROD} and ${PHPVER_TEST}..."

for VER in $PHPVER_PROD $PHPVER_TEST; do
        if [ ! -e /etc/php/${VER} ]; then
                FAIL "PHP $VER not found."; exit 1
        fi
        for DIR in apache2 cgi cli; do
                mkdir -p /etc/php/${VER}/${DIR}/conf.d
                rm -f /etc/php/${VER}/${DIR}/conf.d/20-loxberry*.ini
        done
        ln -sf $LBHOME/system/php/loxberry-apache.ini /etc/php/${VER}/apache2/conf.d/20-loxberry-apache.ini
        ln -sf $LBHOME/system/php/loxberry-apache.ini /etc/php/${VER}/cgi/conf.d/20-loxberry-apache.ini
        ln -sf $LBHOME/system/php/loxberry-cli.ini /etc/php/${VER}/cli/conf.d/20-loxberry-cli.ini
done
update-alternatives --set php /usr/bin/php${PHPVER_PROD}
OK "PHP configured."

# Configuring Apache2
TITLE "Configuring Apache2..."
[ ! -L /etc/apache2 ] && mv /etc/apache2 /etc/apache2.orig
[ -L /etc/apache2 ] && rm /etc/apache2
ln -s $LBHOME/system/apache2 /etc/apache2
a2dismod php* 2>/dev/null
a2dissite 001-default-ssl 2>/dev/null
rm -f $LBHOME/system/apache2/mods-available/php* $LBHOME/system/apache2/mods-enabled/php*
cp /etc/apache2.orig/mods-available/php* /etc/apache2/mods-available 2>/dev/null
a2enmod php${PHPVER_PROD}
OK "Apache2 configured."

# Configuring Network Interfaces
TITLE "Configuring Network..."

# Network config
TITLE "Configuring Network..."
[ ! -L /etc/network/interfaces ] && mv /etc/network/interfaces /etc/network/interfaces.old
[ -L /etc/network/interfaces ] && rm /etc/network/interfaces
ln -s $LBHOME/system/network/interfaces /etc/network/interfaces
[ -e /boot/config.txt ] && G_CONFIG_INJECT 'dtoverlay=disable-wifi' '#dtoverlay=disable-wifi' /boot/config.txt 2>/dev/null
OK "Network configured."

# Configuring Python 3 - reenable pip installations
TITLE "Configuring Python3..."
/usr/bin/echo -e '[global]\nbreak-system-packages=true' > /etc/pip.conf
OK "Python3 configured."

# Configuring Samba
TITLE "Configuring Samba..."
[ ! -L /etc/samba ] && mv /etc/samba /etc/samba.old
[ -L /etc/samba ] && rm /etc/samba
ln -s $LBHOME/system/samba /etc/samba
sed -i -e "s#/opt/loxberry/#$LBHOME/#g" $LBHOME/system/samba/smb.conf
systemctl restart smbd nmbd 2>/dev/null
(echo 'loxberry'; echo 'loxberry') | smbpasswd -a -s loxberry
OK "Samba configured."

# Configuring VSFTP
TITLE "Configuring VSFTPD..."
[ ! -L /etc/vsftpd.conf ] && mv /etc/vsftpd.conf /etc/vsftpd.conf.old
[ -L /etc/vsftpd.conf ] && rm /etc/vsftpd.conf
ln -s $LBHOME/system/vsftpd/vsftpd.conf /etc/vsftpd.conf
systemctl restart vsftpd 2>/dev/null
OK "VSFTPD configured."

# Configuring MSMTP
TITLE "Configuring MSMTP..."
rm -f /etc/msmtprc
ln -s $LBHOME/system/msmtp/msmtprc /etc/msmtprc
chmod 0600 $LBHOME/system/msmtp/msmtprc $LBHOME/system/msmtp/aliases
OK "MSMTP configured."

# Cron.d
TITLE "Configuring Cron.d..."
[ ! -L /etc/cron.d ] && mv /etc/cron.d /etc/cron.d.orig
[ -L /etc/cron.d ] && rm /etc/cron.d
ln -s $LBHOME/system/cron/cron.d /etc/cron.d
cp /etc/cron.d.orig/* /etc/cron.d 2>/dev/null
OK "Cron configured."

# USB Mounts
TITLE "Configuring automatic USB Mounts..."

# Systemd service for usb automount
mkdir -p /media/usb
rm /etc/systemd/system/usb-mount@.service
ln -s $LBHOME/system/systemd/usb-mount@.service /etc/systemd/system/usb-mount@.service

# Create udev rules for usbautomount
rm /etc/udev/rules.d/99-usbmount.rules
ln -s $LBHOME/system/udev/usbmount.rules /etc/udev/rules.d/99-usbmount.rules
/usr/bin/sed -i -e "s#/opt/loxberry/#$LBHOME/#g" $LBHOME/system/udev/usbmount.rules 
/bin/systemctl daemon-reload
OK "Successfully set up udev Rules for USB-Mount."

# Configure autofs
TITLE "Configuring AutoFS for Samba Netshares..."
mkdir -p /media/smb
rm /etc/creds
ln -s $LBHOME/system/samba/credentials /etc/creds
/usr/bin/sed -i -e "s#/opt/loxberry/#$LBHOME/#g" $LBHOME/system/autofs/loxberry_smb.autofs
ln -s $LBHOME/system/autofs/loxberry_smb.autofs /etc/auto.master.d/loxberry_smb.autofs
chmod 0755 $LBHOME/system/autofs/loxberry_smb.autofs
rm $LBHOME/system/storage/smb/.dummy
/bin/systemctl restart autofs
OK "Successfully reconfigured AutoFS."

# Config for watchdog
TITLE "Configuring Watchdog..."
/bin/systemctl disable watchdog.service
/bin/systemctl stop watchdog.service
[ ! -L /etc/watchdog.conf ] && mv /etc/watchdog.conf /etc/watchdog.orig 2>/dev/null
[ -L /etc/watchdog.conf ] && rm /etc/watchdog.conf
grep -q "watchdog_options" /etc/default/watchdog 2>/dev/null || echo 'watchdog_options="-v"' >> /etc/default/watchdog
grep -q "\-v" /etc/default/watchdog || sed -i 's#watchdog_options="\(.*\)"#watchdog_options="\1 -v"#' /etc/default/watchdog
sed -i -e "s#/opt/loxberry/#$LBHOME/#g" $LBHOME/system/watchdog/rsyslog.conf
ln -sf $LBHOME/system/watchdog/watchdog.conf /etc/watchdog.conf
ln -sf $LBHOME/system/watchdog/rsyslog.conf /etc/rsyslog.d/10-watchdog.conf
systemctl restart rsyslog.service
OK "Watchdog configured."

# Activating i2c
TITLE "Enabling I2C (if supported)..."
/boot/dietpi/func/dietpi-set_hardware i2c enable

# Set hosts environment
TITLE "Setting hosts environment..."
rm -f /etc/network/if-up.d/001hosts /etc/dhcp/dhclient-exit-hooks.d/sethosts
ln -sf $LBHOME/sbin/sethosts.sh /etc/network/if-up.d/001host
ln -sf $LBHOME/sbin/sethosts.sh /etc/dhcp/dhclient-exit-hooks.d/sethosts
OK "Hosts configured."

# Configure listchanges to have no output - for apt beeing non-interactive
TITLE "Configuring listchanges to be quit..."
[ -e /etc/apt/listchanges.conf ] && sed -i 's/frontend=pager/frontend=none/' /etc/apt/listchanges.conf
OK "Successfully configured listchanges."

# Reconfigure PAM
TITLE "Reconfigure PAM to allow shorter (weaker) passwords..."
sed -i 's/obscure/minlen=1/' /etc/pam.d/common-password
OK "Successfully reconfigured PAM."

# Reconfigure Unattended Updates
TITLE "Reconfigure Unattended Updates for LoxBerry..."
rm -f /etc/apt/apt.conf.d/02periodic /etc/apt/apt.conf.d/50unattended-upgrades
ln -sf $LBHOME/system/unattended-upgrades/periodic.conf /etc/apt/apt.conf.d/02periodic
ln -sf $LBHOME/system/unattended-upgrades/unattended-upgrades.conf /etc/apt/apt.conf.d/50unattended-upgrades
/bin/systemctl enable unattended-upgrades

# Enable LoxBerry Update after next reboot
TITLE "Enable LoxBerry update after next reboot..."
/usr/bin/touch /boot/do_lbupdate

# Automatically repair filesystem errors on boot
TITLE "Automatically repair filesystem errors on boot..."
[ ! -f /etc/default/rcS ] && echo "FSCKFIX=yes" > /etc/default/rcS
grep -q "FSCKFIX" /etc/default/rcS || echo "FSCKFIX=yes" >> /etc/default/rcS

# Disable SSH Root password access
TITLE "Disable root login via ssh and password..."
/boot/dietpi/func/dietpi-set_software disable_ssh_password_logins root

# Configuring /etc/hosts
TITLE "Setting up /etc/hosts and /etc/hostname..."
/usr/bin/touch /etc/mailname
$LBHOME/sbin/changehostname.sh loxberry
OK "Successfully set up /etc/hosts."

# Set correct File Permissions
TITLE "Setting File Permissions..."
$LBHOME/sbin/resetpermissions.sh

OK "Successfully set File Permissions for LoxBerry."

# Create Config
TITLE "Create LoxBerry Config from Defaults..."
/usr/bin/su loxberry -c "export PERL5LIB=$LBHOME/libs/perllib && $LBHOME/bin/createconfig.pl"
/usr/bin/su loxberry -c "export PERL5LIB=$LBHOME/libs/perllib && $LBHOME/bin/createconfig.pl" # Run twice
export PERL5LIB=$LBHOME/libs/perllib && $LBHOME/sbin/mqtt-handler.pl action=updateconfig
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

# The end
export PERL5LIB=$LBHOME/libs/perllib
IP=$(/usr/bin/perl -e 'use LoxBerry::System; $ip = LoxBerry::System::get_localip(); print $ip; exit;')
/usr/bin/echo -e "\n\n\n${GREEN}WE ARE DONE! :-)${RESET}"
/usr/bin/echo -e "\n\n${RED}If you are *NOT* connected via ethernet and dhcp, configure your"
/usr/bin/echo -e "network now with dietpi-config!"
/usr/bin/echo -e "\nIf you are done, you have to reboot your LoxBerry now!${RESET}"
/usr/bin/echo -e "\n${GREEN}Then point your browser to http://$IP or http://loxberry"
/usr/bin/echo -e "\nIf you would like to login via SSH, use user 'loxberry' and pass 'loxberry'."
/usr/bin/echo -e "Root's password is 'loxberry', too (you cannot login directly via SSH)."
/usr/bin/echo -e "\nGood Bye.\n\n${RESET}"

/usr/bin/touch /boot/rootfsresized

exit 0
