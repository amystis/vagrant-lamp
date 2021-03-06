#!/usr/bin/env bash


echo "[BOOTSTRAP] Applying nasty hack for /stdin: is not a tty/ message..."
sed -i 's/^mesg n$/tty -s \&\& mesg n/g' /root/.profile

echo "[BOOTSTRAP] Importing config file..."
. /vagrant/.vagrant_bootstrap/bootstrap.cfg


echo "[BOOTSTRAP] Setting up locales..."
export LANGUAGE=$LOCALE_CODESET
export LANG=$LOCALE_CODESET
export LC_ALL=$LOCALE_CODESET
locale-gen $LOCALE_LANGUAGE $LOCALE_CODESET > /dev/null


echo "[BOOTSTRAP] Changing installer mode to noninteractive..."
export DEBIAN_FRONTEND=noninteractive


echo "[BOOTSTRAP] Refreshing repositories..."
apt-key update
apt-get upgrade -y -qq
apt-get update -y -qq


echo "[BOOTSTRAP] Installing core packages..." 
apt-get install -y -qq vim tmux curl wget libmagickwand-dev libmagickcore-dev imagemagick build-essential make openssl python-software-properties zsh git-core unzip tree curl acl ruby memcached debconf-utils checkinstall zip locate ruby-full libsqlite3-dev  tzdata


echo "[BOOTSTRAP] Setting up timezone..."
echo $TIMEZONE > /etc/timezone
dpkg-reconfigure --frontend noninteractive tzdata

#######
# GIT #
#######

echo "[BOOTSTRAP] Installing and configuring Git..."
apt-get install -y -qq git
git config --global color.branch auto
git config --global color.diff auto
git config --global color.status auto


###############
# Ondřej Surý #
###############

echo "[BOOTSTRAP] Adding LAMP repositories..."
add-apt-repository -y ppa:ondrej/php5-5.6
add-apt-repository -y ppa:ondrej/apache2
add-apt-repository -y ppa:ondrej/mysql-5.6
apt-key adv --keyserver keyserver.ubuntu.com --recv-keys E5267A6C


echo "[BOOTSTRAP] Updating repositories..."
apt-get update -qq
apt-get upgrade -qq


###########
# Apache2 #
###########

echo "[BOOTSTRAP] Installing Apache2..."
apt-get install -y -qq apache2

echo "[BOOTSTRAP] Applying nasty fix to /apache2: Could not reliably determine the server's fully qualified domain name/ error..."
echo "ServerName $SERVER_NAME" >> /etc/apache2/apache2.conf


echo "[BOOTSTRAP] Adding Apache2 a little more air, to speed up things..."
PREFORK=$(cat <<EOF
<IfModule prefork.c>
    StartServers 2
    MinSpareServers 6
    MaxSpareServers 4
    ServerLimit 4
    MaxClients 4
    MaxRequestsPerChild 3000
</IfModule>
EOF
)
echo "${PREFORK}" > /etc/apache2/apache2.conf

echo "[BOOTSTRAP] Configuring overrides globally for Apache2..."
rm -rf /var/www/html
VHOST=$(cat <<EOF
<VirtualHost *:80>
  ServerName $SERVER_NAME
  ServerAlias $SERVER_ALIAS
  DocumentRoot /var/www
  ErrorLog /var/log/apache2/error.log
  CustomLog /var/log/apache2/access.log combined
  <Directory "/var/www">
    AllowOverride All
    Require all granted
  </Directory>
</VirtualHost>
EOF
)
echo "${VHOST}" > /etc/apache2/sites-enabled/000-default.conf

echo "[BOOTSTRAP] Adding vagrant user to www-data group..."
usermod -a -G vagrant www-data


echo "[BOOTSTRAP] Enabling Apache2 modules..."
a2enmod rewrite
a2enmod expires
a2enmod headers
a2enmod actions


echo "[BOOTSTRAP] Restarting Apache2..."
service apache2 restart


########
# PHP5 #
########

echo "Setup PHP 5."
apt-get install -y -qq php5 php5-gd php5-sqlite php5-pgsql php5-ldap php5-common php5-geoip php5-redis php5-imagick php5-memcache php5-memcached  php5-mysql php5-xsl php5-curl php5-mcrypt php5-intl php5-cli php5-dev libapache2-mod-php5 php-apc php-pear php5-json php5-xdebug
mv /etc/php5/apache2/php.ini /etc/php5/apache2/php.ini.bak
cp -s /usr/share/php5/php.ini-development /etc/php5/apache2/php.ini
sed -i 's#;date.timezone\([[:space:]]*\)=\([[:space:]]*\)*#date.timezone\1=\2\"'"$timezone"'\"#g' /etc/php5/apache2/php.ini
sed -i 's#display_errors = Off#display_errors = On#g' /etc/php5/apache2/php.ini
sed -i 's#display_startup_errors = Off#display_startup_errors = On#g' /etc/php5/apache2/php.ini
sed -i 's#error_reporting = E_ALL & ~E_DEPRECATED & ~E_STRICT#error_reporting = E_ALL#g' /etc/php5/apache2/php.ini
sed -i 's#;date.timezone\([[:space:]]*\)=\([[:space:]]*\)*#date.timezone\1=\2\"'"$timezone"'\"#g' /etc/php5/cli/php.ini
sed -i 's#display_errors = Off#display_errors = On#g' /etc/php5/cli/php.ini
sed -i 's#display_startup_errors = Off#display_startup_errors = On#g' /etc/php5/cli/php.ini
sed -i 's#error_reporting = E_ALL & ~E_DEPRECATED & ~E_STRICT#error_reporting = E_ALL#g' /etc/php5/cli/php.ini
a2enmod php5
php5enmod mcrypt # Needs to be activated manually (that's an issue for Ubuntu 14.04)

echo "[BOOTSTRAP] Restarting Apache2..."
service apache2 restart


###########
# XDdebug #
###########

echo "[BOOTSTRAP] Configuring XDdebug..."

# xdebug.remote_connect_back=1 Most people don't want it to be set to true. It doesn't allow you to debug CLI scripts remotely (XDdebug doesn't know the clients IP address, so it doesn't know where to send debug data).

cp /dev/null /etc/php5/cli/conf.d/20-xdebug.ini
cp /dev/null /etc/php5/apache2/conf.d/20-xdebug.ini
cat << EOF | tee -a /etc/php5/mods-available/xdebug.ini
zend_extension="$(find /usr/lib/php5 -name xdebug.so)"
xdebug.remote_autostart=1 ;You most likely don't need it. It starts the debugger session every time you run a script. If you're working on DEV only environment with CLI scripts, you can speed up development by enabling it.
xdebug.cli_color=1
xdebug.max_nesting_level = 1000000
xdebug.remote_connect_back=1
xdebug.remote_enable=1
xdebug.remote_handler=dbgp
xdebug.remote_host=$HOST_IP_ADDRESS ; Default IP address for VirtualBox host machine.
xdebug.remote_log="/tmp/log/xdebug.log"
xdebug.remote_port=9000
xdebug.scream=0
xdebug.show_exception_trace=On
xdebug.show_local_vars=1
xdebug.trace_format=1
xdebug.var_display_max_children = 256
xdebug.var_display_max_data = 1024
xdebug.var_display_max_depth = 5
EOF


#############
#   MySQL   #
#############

echo "[BOOTSTRAP] Setting up selections for MySQL installer..."
echo "mysql-server mysql-server/root_password password $MYSQL_PASSWORD" | debconf-set-selections
echo "mysql-server mysql-server/root_password_again password $MYSQL_PASSWORD" | debconf-set-selections


echo "[BOOTSTRAP] Installing MySQL..."
# Install MySQL without prompt
apt-get install -y -qq mysql-server-5.6 mysql-client-5.6


echo "[BOOTSTRAP] Configuring MySQL server listen to all connection..."
sed -i "s/bind-address.*=.*/bind-address=0.0.0.0/" /etc/mysql/my.cnf
MYSQLGRANT="GRANT ALL ON *.* to root@'%' IDENTIFIED BY '$MYSQL_PASSWORD'; FLUSH PRIVILEGES;"
mysql -u root -p$MYSQL_PASSWORD mysql -e "${MYSQLGRANT}"


echo "[BOOTSTRAP] Creating a main database..."
mysql -u root -p$MYSQL_PASSWORD -e "CREATE DATABASE IF NOT EXISTS $DEFAULT_DATABASE_NAME;"


echo "[BOOTSTRAP] Restarting MySQL..."
echo "[BOOTSTRAP] 3..."
sleep 1
echo "[BOOTSTRAP] 2..."
sleep 1
echo "[BOOTSTRAP] 1..."
service mysql restart > /dev/null
echo "[BOOTSTRAP] MySQL started..."

###########
# Postfix #
###########

echo "[BOOTSTRAP] Preconfiguring postfix selections..."
echo postfix postfix/mailname string $SERVER_NAME | debconf-set-selections
echo postfix postfix/main_mailer_type string 'Internet Site' | debconf-set-selections

echo "[BOOTSTRAP] Installing  postfix..."
apt-get install -y -qq postfix
service postfix reload > /dev/null


################
# Post install #
################

echo "[BOOTSTRAP] Setting hostname..."
hostname $SERVER_NAME


echo "[BOOTSTRAP] Restarting Apache2..."
service apache2 restart > /dev/null


echo "[BOOTSTRAP] Cleaning up..."
dpkg --configure -a # when upgrade or install doesnt run well (e.g. loss of connection) this may resolve quite a few issues
apt-get autoremove -y > /dev/null
apt-get autoclean -y > /dev/null