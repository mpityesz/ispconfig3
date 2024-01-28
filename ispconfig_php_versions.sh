### Update and upgrade before install
apt update
apt full-upgrade

### Install packages to prepare SURY repository
apt install -y apt-transport-https lsb-release ca-certificates

### Add the repository key
wget -O /etc/apt/trusted.gpg.d/php.gpg https://packages.sury.org/php/apt.gpg >/dev/null 2>&1

### Add the repository
echo "deb https://packages.sury.org/php/ $(lsb_release -c -s) main" > /etc/apt/sources.list.d/php.list

### Update APT
apt update
apt upgrade

### Install PHP 5.6
apt install php5.6 php5.6-common php5.6-cli php5.6-cgi php5.6-fpm php5.6-curl php5.6-intl php5.6-mbstring php5.6-pspell \
php5.6-gd php5.6-mysql php5.6-sqlite3 php5.6-ldap php5.6-json php5.6-imap \
php5.6-opcache php5.6-phpdbg php5.6-recode php5.6-tidy php5.6-readline \
php5.6-soap php5.6-xmlrpc php5.6-xml php5.6-xsl php5.6-zip \
libicu65

### Install PHP 7.0
apt install php7.0 php7.0-common php7.0-cli php7.0-cgi php7.0-fpm php7.0-curl php7.0-intl php7.0-mbstring php7.0-pspell \
php7.0-gd php7.0-mysql php7.0-sqlite3 php7.0-ldap php7.0-json php7.0-imap \
php7.0-opcache php7.0-phpdbg php7.0-recode php7.0-tidy php7.0-readline \
php7.0-soap php7.0-xmlrpc php7.0-xml php7.0-xsl php7.0-zip

### Install PHP 7.1
apt install php7.1 php7.1-common php7.1-cli php7.1-cgi php7.1-fpm php7.1-curl php7.1-intl php7.1-mbstring php7.1-pspell \
php7.1-gd php7.1-mysql php7.1-sqlite3 php7.1-ldap php7.1-json php7.1-imap \
php7.1-opcache php7.1-phpdbg php7.1-recode php7.1-tidy php7.1-readline \
php7.1-soap php7.1-xmlrpc php7.1-xml php7.1-xsl php7.1-zip

### Install PHP 7.2
apt install php7.2 php7.2-common php7.2-cli php7.2-cgi php7.2-fpm php7.2-curl php7.2-intl php7.2-mbstring php7.2-pspell \
php7.2-gd php7.2-mysql php7.2-sqlite3 php7.2-ldap php7.2-json php7.2-imap \
php7.2-opcache php7.2-phpdbg php7.2-recode php7.2-tidy php7.2-readline \
php7.2-soap php7.2-xmlrpc php7.2-xml php7.2-xsl php7.2-zip

### Install PHP 7.3
apt install php7.3 php7.3-common php7.3-cli php7.3-cgi php7.3-fpm php7.3-curl php7.3-intl php7.3-mbstring php7.3-pspell \
php7.3-gd php7.3-mysql php7.3-sqlite3 php7.3-ldap php7.3-json php7.3-imap \
php7.3-opcache php7.3-phpdbg php7.3-recode php7.3-tidy php7.3-readline \
php7.3-soap php7.3-xmlrpc php7.3-xml php7.3-xsl php7.3-zip \
libonig5

### Install PHP 7.4
apt install php7.4 php7.4-common php7.4-cli php7.4-cgi php7.4-fpm php7.4-curl php7.4-intl php7.4-mbstring php7.4-pspell \
php7.4-gd php7.4-mysql php7.4-sqlite3 php7.4-ldap php7.4-json php7.4-imap \
php7.4-opcache php7.4-phpdbg php7.4-recode php7.4-tidy php7.4-readline \
php7.4-soap php7.4-xmlrpc php7.4-xml php7.4-xsl php7.4-zip \
libonig5

### Install PHP 8.0
apt install php8.0 php8.0-common php8.0-cli php8.0-cgi php8.0-fpm php8.0-curl php8.0-intl php8.0-mbstring php8.0-pspell \
php8.0-gd php8.0-mysql php8.0-sqlite3 php8.0-ldap php8.0-json php8.0-imap \
php8.0-opcache php8.0-phpdbg php8.0-recode php8.0-tidy php8.0-readline \
php8.0-soap php8.0-xmlrpc php8.0-xml php8.0-xsl php8.0-zip \
libonig5

### Install PHP 8.1
apt install php8.1 php8.1-common php8.1-cli php8.1-cgi php8.1-fpm php8.1-curl php8.1-intl php8.1-mbstring php8.1-pspell \
php8.1-gd php8.1-mysql php8.1-sqlite3 php8.1-ldap php8.1-json php8.1-imap \
php8.1-opcache php8.1-phpdbg php8.1-recode php8.1-tidy php8.1-readline \
php8.1-soap php8.1-xmlrpc php8.1-xml php8.1-xsl php8.1-zip \
libonig5

### Install PHP 8.2
apt install php8.2 php8.2-common php8.2-cli php8.2-cgi php8.2-fpm php8.2-curl php8.2-intl php8.2-mbstring php8.2-pspell \
php8.2-gd php8.2-mysql php8.2-sqlite3 php8.2-ldap php8.2-json php8.2-imap \
php8.2-opcache php8.2-phpdbg php8.2-recode php8.2-tidy php8.2-readline \
php8.2-soap php8.2-xmlrpc php8.2-xml php8.2-xsl php8.2-zip \
libonig5

### Install PHP 8.3
apt install php8.3 php8.3-common php8.3-cli php8.3-cgi php8.3-fpm php8.3-curl php8.3-intl php8.3-mbstring php8.3-pspell \
php8.3-gd php8.3-mysql php8.3-sqlite3 php8.3-ldap php8.3-json php8.3-imap \
php8.3-opcache php8.3-phpdbg php8.3-recode php8.3-tidy php8.3-readline \
php8.3-soap php8.3-xmlrpc php8.3-xml php8.3-xsl php8.3-zip \
libonig5

### Fix default version of the OS
### On Debian 12, choose 8.2, Debian 11, choose 7.4, on Debian 10, choose 7.3, on Debian 9, choose PHP 7.0.
update-alternatives --config php
update-alternatives --config php-cgi
update-alternatives --config php-fpm.sock

