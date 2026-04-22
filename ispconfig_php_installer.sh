#!/bin/bash

# ISPConfig PHP Installer Script
#
# This script automates the installation of selected PHP versions on ISPConfig servers
# and manages PHP-FPM services.

# Load configuration
if [ -f "ispconfig_php_installer.conf" ]; then
    source ispconfig_php_installer.conf
else
    echo "Configuration file not found!"
    exit 1
fi

# Colored logging functions
log() { echo -e "\e[32m[INFO]\e[0m $1"; }
log_error() { echo -e "\e[31m[ERROR]\e[0m $1"; }
log_warning() { echo -e "\e[33m[WARNING]\e[0m $1"; }
log_info() { echo -e "\e[34m[INFO]\e[0m $1"; }

# Check for root privileges
if [ "$EUID" -ne 0 ]; then
    log_error "This script must be run as root";
    exit 1;
fi

# Detect Debian version
DEBIAN_VERSION=$(lsb_release -rs)
log "Detected Debian version: $DEBIAN_VERSION"

# Add SURY repository if needed
if ! apt-cache policy | grep -q sury; then
    log "Adding SURY repository..."
    add-apt-repository -y ppa:ondrej/php
    apt-get update
fi

# Helper function to check package installation status
check_package_installed() {
    dpkg -l | grep -q $1
}

# Install PHP versions with extensions based on config
for PHP_VERSION in ${PHP_VERSIONS[@]}; do
    if ! check_package_installed "php$PHP_VERSION"; then
        log "Installing PHP version $PHP_VERSION..."
        apt-get install -y php$PHP_VERSION php$PHP_VERSION-mysql php$PHP_VERSION-fpm
        # Handle version-specific packages
        if [[ "$PHP_VERSION" < "8.0" ]]; then
            apt-get install -y php$PHP_VERSION-json php$PHP_VERSION-recode php$PHP_VERSION-mcrypt php$PHP_VERSION-apcu-bc
        else
            apt-get install -y php$PHP_VERSION-xdebug
        fi
    else
        log_warning "PHP version $PHP_VERSION is already installed.";
    fi

    # Configure php.ini settings
    PHP_INI_FILE="/etc/php/$PHP_VERSION/fpm/php.ini"
    if [ -f "$PHP_INI_FILE" ]; then
        cp "$PHP_INI_FILE" "$PHP_INI_FILE.bak"
        sed -i 's/;date.timezone =/date.timezone = "UTC"/' "$PHP_INI_FILE"
        sed -i 's/memory_limit = .*/memory_limit = 256M/' "$PHP_INI_FILE"
        sed -i 's/upload_max_filesize = .*/upload_max_filesize = 64M/' "$PHP_INI_FILE"
        sed -i 's/post_max_size = .*/post_max_size = 64M/' "$PHP_INI_FILE"
        sed -i 's/max_execution_time = .*/max_execution_time = 300/' "$PHP_INI_FILE"
        sed -i 's/max_input_time = .*/max_input_time = 300/' "$PHP_INI_FILE"
    else
        log_error "php.ini for version $PHP_VERSION not found!"
    fi

    # Enable and start FPM service
    systemctl enable php$PHP_VERSION-fpm
    systemctl start php$PHP_VERSION-fpm
done

# Execute SQL import if AUTO_ADD_TO_ISPCONFIG is yes
if [ "$AUTO_ADD_TO_ISPCONFIG" == "yes" ]; then
    log "Importing SQL to ISPConfig..."
    # ... SQL import commands here ...
fi

# Output summary
log "Installation completed. PHP versions installed: ${PHP_VERSIONS[@]}"