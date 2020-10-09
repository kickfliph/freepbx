#!/bin/bash

# Discard stdin. Needed when running from an one-liner which includes a newline
read -N 999999 -t 0.001

# Detect Debian users running the script with "sh" instead of bash
if readlink /proc/$$/exe | grep -q "dash"; then
	echo 'This installer needs to be run with "bash", not "sh".'
	exit
fi

# Detect OpenVZ 6
if [[ $(uname -r | cut -d "." -f 1) -eq 2 ]]; then
	echo "The system is running an old kernel, which is incompatible with this installer."
	exit
fi

# Detect OS
# $os_version variables aren't always in use, but are kept here for convenience
if grep -qs "ubuntu" /etc/os-release; then
	os="ubuntu"
	os_version=$(grep 'VERSION_ID' /etc/os-release | cut -d '"' -f 2 | tr -d '.')i
	apt-get install git build-essential wget -y
elif [[ -e /etc/debian_version ]]; then
	os="debian"
	os_version=$(grep -oE '[0-9]+' /etc/debian_version | head -1)
	apt-get install git build-essential wget -y
else
	echo "This installer seems to be running on an unsupported distribution.
Supported distributions are Ubuntu, Debian."
	exit
fi

if [[ "$os" == "ubuntu" && "$os_version" -lt 1804 ]]; then
	echo "Ubuntu 18.04 or higher is required to use this installer.
This version of Ubuntu is too old and unsupported."
	exit
fi

if [[ "$os" == "debian" && "$os_version" -lt 10 ]]; then
	echo "Debian 10 or higher is required to use this installer.
This version of Debian is too old and unsupported."
	exit
fi

# Detect environments where $PATH does not include the sbin directories
if ! grep -q sbin <<< "$PATH"; then
	echo '$PATH does not include sbin. Try using "su -" instead of "su".'
	exit
fi

if [[ "$EUID" -ne 0 ]]; then
	echo "This installer needs to be run with superuser privileges."
	exit
fi

echo deb http://ftp.us.debian.org/debian/ buster-backports main > /etc/apt/sources.list.d/backports.list
echo deb-src http://ftp.us.debian.org/debian/ buster-backports main >> /etc/apt/sources.list.d/backports.list
apt-get update
apt-get upgrade

#Install all the necessary packages

apt-get install -y build-essential linux-headers-`uname -r` openssh-server apache2 mariadb-server mariadb-client bison flex php php-curl php-cli php-pdo php-mysql php-pear php-gd php-mbstring php-intl php-bcmath curl sox libncurses5-dev libssl-dev mpg123 libxml2-dev libnewt-dev sqlite3 libsqlite3-dev pkg-config automake libtool autoconf git unixodbc-dev uuid uuid-dev libasound2-dev libogg-dev libvorbis-dev libicu-dev libcurl4-openssl-dev libical-dev libneon27-dev libsrtp2-dev libspandsp-dev sudo subversion libtool-bin python-dev unixodbc dirmngr sendmail-bin sendmail asterisk debhelper-compat cmake libmariadb-dev odbc-mariadb php-ldap

#Node.js
curl -sL https://deb.nodesource.com/setup_12.x | sudo -E bash -
apt -y install nodejs

#Install this required Pear module

pear install Console_Getopt

#Prepare Asterisk
systemctl stop asterisk
systemctl disable asterisk
cd /etc/asterisk
mkdir DIST
mv * DIST
cp DIST/asterisk.conf .
sed -i 's/(!)//' asterisk.conf
touch modules.conf
touch cdr.conf

#Configure Apache web server
sed -i 's/\(^upload_max_filesize = \).*/\120M/' /etc/php/7.3/apache2/php.ini
sed -i 's/\(^memory_limit = \).*/\1256M/' /etc/php/7.3/apache2/php.ini
sed -i 's/^\(User\|Group\).*/\1 asterisk/' /etc/apache2/apache2.conf
sed -i 's/AllowOverride None/AllowOverride All/' /etc/apache2/apache2.conf
a2enmod rewrite
service apache2 restart
rm /var/www/html/index.html

#Configure ODBC
cat <<EOF > /etc/odbcinst.ini
[MySQL]
Description = ODBC for MySQL (MariaDB)
Driver = /usr/lib/x86_64-linux-gnu/odbc/libmaodbc.so
FileUsage = 1
EOF
 
cat <<EOF > /etc/odbc.ini
[MySQL-asteriskcdrdb]
Description = MySQL connection to 'asteriskcdrdb' database
Driver = MySQL
Server = localhost
Database = asteriskcdrdb
Port = 3306
Socket = /var/run/mysqld/mysqld.sock
Option = 3
EOF

#Download FFMPEG static build for sound file manipulation
cd /usr/local/src
wget "https://johnvansickle.com/ffmpeg/releases/ffmpeg-release-amd64-static.tar.xz"
tar xf ffmpeg-release-amd64-static.tar.xz
cd ffmpeg-4*
mv ffmpeg /usr/local/bin
#Install FreePBX
cd /usr/local/src
wget http://mirror.freepbx.org/modules/packages/freepbx/freepbx-15.0-latest.tgz
tar zxvf freepbx-15.0-latest.tgz
cd /usr/local/src/freepbx/
./start_asterisk start
./install -n

#Get the rest of the modules

fwconsole ma installall

#Uninstall digium_phones
fwconsole ma uninstall digium_phones

#Apply the current configuration
fwconsole reload

#Set symlinks to the correct sound files
cd /usr/share/asterisk
mv sounds sounds-DIST
ln -s /var/lib/asterisk/sounds sounds

#Perform a restart to load all Asterisk modules that had not yet been configured
fwconsole restart

#Set up systemd (startup script)
cat <<EOF > /etc/systemd/system/freepbx.service
[Unit]
Description=FreePBX VoIP Server
After=mariadb.service
[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/sbin/fwconsole start -q
ExecStop=/usr/sbin/fwconsole stop -q
[Install]
WantedBy=multi-user.target
EOF
 
systemctl daemon-reload
systemctl enable freepbx

