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
#Initial upgrade and install
apt update && apt -y upgrade && apt install lsb-release

#PHP
apt -y install curl apt-transport-https ca-certificates
sudo apt install php-fpm php-mbstring php-xmlrpc php-soap php-apcu php-smbclient php-ldap php-redis php-gd php-xml php-intl php-json php-imagick php-mysql php-cli php-ldap php-zip php-curl php-dev libmcrypt-dev php-pear -y

#All Others
apt -y install locales sngrep build-essential aptitude openssh-server mariadb-server mariadb-client bison doxygen flex php-pear curl sox libncurses5-dev libssl-dev libmariadbclient-dev mpg123 libxml2-dev libnewt-dev sqlite3 libsqlite3-dev pkg-config automake libtool-bin autoconf git subversion uuid uuid-dev libiksemel-dev tftpd postfix mailutils vim ntp libspandsp-dev libcurl4-openssl-dev libical-dev libneon27-dev libasound2-dev libogg-dev libvorbis-dev libicu-dev libsrtp*-dev unixodbc unixodbc-dev python-dev xinetd e2fsprogs dbus sudo xmlstarlet lame ffmpeg dirmngr linux-headers*

#Node.js
curl -sL https://deb.nodesource.com/setup_12.x | sudo -E bash -
apt -y install nodejs

#ODBC
wget https://downloads.mariadb.com/Connectors/odbc/latest/mariadb-connector-odbc-3.1.9-debian-buster-amd64.tar.gz -P /usr/src
tar -zxvf /usr/src/mariadb-connector-odbc-3.1*.tar.gz -C /usr/src/
cp /usr/src/mariadb-connector-odbc-3.1*/lib/mariadb/libmaodbc.so  /usr/lib/x86_64-linux-gnu/odbc/

#Create /etc/odbcinst.ini
cat >> /etc/odbcinst.ini << EOF
[MySQL]
Description = ODBC for MariaDB
Driver = /usr/lib/x86_64-linux-gnu/odbc/libmaodbc.so
Setup = /usr/lib/x86_64-linux-gnu/odbc/libodbcmyS.so
FileUsage = 1
  
EOF

#Create /etc/odbc.ini
cat >> /etc/odbc.ini << EOF
[MySQL-asteriskcdrdb]
Description = MariaDB connection to 'asteriskcdrdb' database
driver = MySQL
server = localhost
database = asteriskcdrdb
Port = 3306
Socket = /var/run/mysqld/mysqld.sock
option = 3
  
EOF

#MongoDB required if you plan to use XMPP
wget -qO - https://www.mongodb.org/static/pgp/server-4.2.asc | sudo apt-key add -
echo "deb http://repo.mongodb.org/apt/debian $(lsb_release -sc)/mongodb-org/4.2 main" \
| sudo tee /etc/apt/sources.list.d/mongodb-org-4.2.list
apt update && apt install -y mongodb-org
systemctl enable mongod

# FIND YOUR TIMEZONE
tzselect
sudo apt purge ntp -y
sudo systemctl start systemd-timesyncd
sudo systemctl status systemd-timesyncd
timedatectl status
systemctl restart rsyslog

cp ./freepbx /usr/src/freepbx_nginx

#DAHDI
cd /usr/src
wget http://downloads.asterisk.org/pub/telephony/dahdi-linux-complete/releases/dahdi-linux-complete-3.1.0+3.1.0.tar.gz
tar zxvf dahdi-linux-complete-3.1*
cd /usr/src/dahdi-linux-complete-3.1*/
make all && make install && make config
make install-config
systemctl restart dahdi

#Asterisk
apt install gcc wget g++ make patch libedit-dev uuid-dev  libxml2-dev libsqlite3-dev openssl libssl-dev bzip2 -y
cd /usr/src/ && wget http://downloads.asterisk.org/pub/telephony/asterisk/asterisk-17-current.tar.gz 
tar -xzvf asterisk-17-current.tar.gz
cd asterisk-17*/
sudo contrib/scripts/get_mp3_source.sh
sudo contrib/scripts/install_prereq install
#script to detect what debian version is running to add the jansson-bundled
#sudo configure --with-pjproject-bundled --with-jansson-bundled
sudo ./configure 
make menuselect

echo "###################################################################################################################"
echo "#             Applying the changes made                                                                           #"
echo "###################################################################################################################"
make
make install
sudo make progdocs
sudo make samples
sudo make config
sudo ldconfig


#Create Asterisk User, compile, install and set preliminary ownership
sudo groupadd asterisk
sudo useradd -r -d /var/lib/asterisk -g asterisk asterisk
sudo usermod -aG audio,dialout asterisk
sudo chown -R asterisk.asterisk /etc/asterisk
sudo chown -R asterisk.asterisk /var/{lib,log,spool}/asterisk
sudo chown -R asterisk.asterisk /usr/lib/asterisk
sed -i 's/;AST_USER/AST_USER/g' /etc/default/asterisk
sed -i 's/;AST_GROUP/AST_GROUP/g' /etc/default/asterisk
sed -i 's/;runuser/runuser/g' /etc/asterisk/asterisk.conf
sed -i 's/;rungroup/rungroup/g' /etc/asterisk/asterisk.conf
sed -i 's";\[radius\]"\[radius\]"g' /etc/asterisk/cdr.conf
sed -i 's";radiuscfg => /usr/local/etc/radiusclient-ng/radiusclient.conf"radiuscfg => /etc/radcli/radiusclient.conf"g' /etc/asterisk/cdr.conf
sed -i 's";radiuscfg => /usr/local/etc/radiusclient-ng/radiusclient.conf"radiuscfg => /etc/radcli/radiusclient.conf"g' /etc/asterisk/cel.conf

sudo systemctl restart asterisk
sudo systemctl enable asterisk


#FreePBX
cd /usr/src
git clone -b release/15.0 --single-branch https://github.com/freepbx/framework.git freepbx
touch /etc/asterisk/modules.conf
cd /usr/src/freepbx
./start_asterisk start
./install -n

# Minimal module install
fwconsole ma downloadinstall framework core voicemail sipsettings infoservices \
featurecodeadmin logfiles callrecording cdr dashboard music soundlang recordings conferences
fwconsole chown
rm -rf /home/asterisk/.package_cache/npm/
rm -rf /home/asterisk/.npm
fwconsole ma downloadinstall pm2 
fwconsole reload

cat >> /etc/systemd/system/freepbx.service << EOF
[Unit]
Description=Freepbx
After=mariadb.service
 
[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/sbin/fwconsole start
ExecStop=/usr/sbin/fwconsole stop
 
[Install]
WantedBy=multi-user.target
EOF

systemctl enable freepbx

php_ver=`php -v | grep PHP | head -1 | cut -d ' ' -f2 | cut -c 1-3`
#sudo systemctl stop php-fpm
sudo ps aux  |  grep -i php-fpm  |  awk '{print $2}' | xargs sudo kill -9

#Configure Nginx web server
sed -i 's/\(^upload_max_filesize = \).*/\120M/' /etc/php/$php_ver/fpm/php.ini
sed -i 's/\(^memory_limit = \).*/\1256M/' /etc/php/$php_ver/fpm/php.ini
sed -i 's/www-data/asterisk/' /etc/php/$php_ver/fpm/pool.d/www.conf


echo " "
read -p 'Please enter your Domain Name: ' domainame
echo " "
read -p 'Please enter your email: ' my_email
if [ -z "$domainame" ] || [ -z "$my_email" ]
then
    echo 'Inputs cannot be blank please try again!'
    exit 0
fi
echo " "

sudo apt install nginx-full certbot python-certbot-nginx python3-certbot-nginx -y

certbot --nginx --agree-tos --redirect --staple-ocsp --email $my_email -d $domainame
sudo systemctl stop nginx
sudo ps aux  |  grep -i nginx  |  awk '{print $2}' | xargs sudo kill -9

cp /usr/src/freepbx_nginx /etc/nginx/sites-available/freepbx
sudo sed -i "s/my_domain_name/$domainame/g" /etc/nginx/sites-available/freepbx
sudo sed -i "s/www-data/asterisk/g" /etc/nginx/nginx.conf
sudo rm /etc/nginx/sites-enabled/default
sudo ln -s /etc/nginx/sites-available/freepbx /etc/nginx/sites-enabled/

nginx -t
systemctl start nginx
systemctl status nginx

systemctl start php$php_ver-fpm
systemctl status php$php_ver-fpm

my_ip=`hostname -I`
echo " "
echo "###################################################################################################################"
echo "#   You should now be able to access the Freepbx GUI at http://$my_ip                                  #"
echo "###################################################################################################################"
echo " "
echo " "
echo "###################################################################################################################"
echo "#              Please answer Y to all questions                                                                   #"
echo "###################################################################################################################"
echo " "

#Post-install tasks
mysql_secure_installation

echo " "
touch /etc/xinetd.d/tftp
cat >> /etc/xinetd.d/tftp << EOF
service tftp
{
protocol        = udp
port            = 69
socket_type     = dgram
wait            = yes
user            = nobody
server          = /usr/sbin/in.tftpd
server_args     = /tftpboot
disable         = no
}
EOF

mkdir /tftpboot
chmod 777 /tftpboot
systemctl restart xinetd
sudo apt-get -y install fail2ban ufw
cat >> /etc/fail2ban/jail.local << EOF
[postfix]
enabled  = true
port     = smtp
filter   = postfix
logpath  = /var/log/mail.log
maxretry = 3
[ssh]
enabled = true
port    = ssh
filter  = sshd
logpath  = /var/log/auth.log
maxretry = 3
[vsftpd]
enabled = false
port = ftp
filter = vsftpd
logpath = /var/log/auth.log
maxretry = 5
[pure-ftpd]
enabled = true
port = ftp
filter = pure-ftpd
logpath = /var/log/syslog
maxretry = 3
EOF

sudo systemctl enable fail2ban.service
sudo systemctl start fail2ban.service
wget http://www.voipbl.org/voipbl.sh -O /usr/local/bin/voipbl.sh
chmod +x /usr/local/bin/voipbl.sh
cat >> /etc/fail2ban/jail.conf << EOF
[asterisk-iptables]
action = iptables-allports[name=ASTERISK, protocol=all]
         voipbl[serial=XXXXXXXXXX]
	 
cat >> /etc/fail2ban/action.d/voipbl.conf << EOF 	 
# Description: Configuration for Fail2Ban
[Definition]
actionban   = <getcmd> "<url>/ban/?serial=<serial>&ip=<ip>&count=<failures>"
actionunban = <getcmd> "<url>/unban/?serial=<serial>&ip=<ip>&count=<failures>"
[Init]
getcmd = wget --no-verbose --tries=3 --waitretry=10 --connect-timeout=10 \
              --read-timeout=60 --retry-connrefused --output-document=- \
	      --user-agent=Fail2Ban
url =
http://www.voipbl.org
EOF

touch /etc/cron.d/voipbl
cat >> /etc/cron.d/voipbl << EOF
# update blacklist each 4 hours
0 */4 * * * * root /usr/local/bin/voipbl.sh

EOF
sudo systemctl restart fail2ban
