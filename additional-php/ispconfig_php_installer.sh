#!/bin/bash

# =============================================================================
# ISPConfig PHP Installer Script
# =============================================================================
#
# This script automates the installation of multiple PHP versions on ISPConfig 
# servers. It handles:
# - Detection of the Debian/Ubuntu version
# - Addition of the SURY PHP repository
# - Installation of PHP versions with required extensions
# - Configuration of php.ini settings for each version
# - Management of PHP-FPM services
# - Optional integration with ISPConfig database
#
# Requirements:
# - Root privileges
# - Debian/Ubuntu based system
# - ispconfig_php_installer.conf configuration file
#
# =============================================================================

# =============================================================================
# COLORED LOGGING FUNCTIONS
# =============================================================================

# Standard informational message in green
log() { 
    echo -e "\e[32m[INFO]\e[0m $1"
}

# Error message in red
log_error() { 
    echo -e "\e[31m[ERROR]\e[0m $1"
}

# Warning message in yellow
log_warning() { 
    echo -e "\e[33m[WARNING]\e[0m $1"
}

# Informational message in blue
log_info() { 
    echo -e "\e[34m[INFO]\e[0m $1"
}

# =============================================================================
# SYSTEM CHECKS AND PREREQUISITES
# =============================================================================

# Check if the script is being run with root privileges
# Exit with error code 1 if not running as root
check_root_privileges() {
    if [ "$EUID" -ne 0 ]; then
        log_error "This script must be run as root (use sudo or login as root)"
        exit 1
    fi
}

# Load the configuration file containing PHP versions and settings
# Exit with error code 1 if configuration file is not found
load_configuration() {
    if [ -f "ispconfig_php_installer.conf" ]; then
        source ispconfig_php_installer.conf
        log "Configuration file loaded successfully"
    else
        log_error "Configuration file 'ispconfig_php_installer.conf' not found!"
        exit 1
    fi
}

# Detect the current Debian/Ubuntu version
# Returns: Sets DEBIAN_VERSION global variable
detect_debian_version() {
    DEBIAN_VERSION=$(lsb_release -rs)
    log "Detected Debian/Ubuntu version: $DEBIAN_VERSION"
}

# =============================================================================
# REPOSITORY MANAGEMENT
# =============================================================================

# Add SURY repository for PHP packages if not already present
# SURY provides multiple PHP versions for Debian/Ubuntu systems
add_sury_repository() {
    if ! apt-cache policy | grep -q sury; then
        log "SURY repository not found. Adding it now..."
        add-apt-repository -y ppa:ondrej/php
        apt-get update
        log "SURY repository added successfully"
    else
        log "SURY repository is already configured"
    fi
}

# =============================================================================
# PACKAGE MANAGEMENT
# =============================================================================

# Check if a specific package is installed on the system
# Arguments:
#   $1 - package name to check
# Returns: 0 if installed, non-zero if not installed
check_package_installed() {
    dpkg -l | grep -q "^ii.*$1"
}

# Install a specific PHP version with core extensions
# Arguments:
#   $1 - PHP version number (e.g., 7.4, 8.0, 8.1)
install_php_version() {
    local PHP_VERSION=$1
    
    if ! check_package_installed "php$PHP_VERSION"; then
        log "Installing PHP version $PHP_VERSION..."
        
        # Install base PHP packages: CLI, MySQL extension, and FPM
        apt-get install -y \
            php$PHP_VERSION \
            php$PHP_VERSION-mysql \
            php$PHP_VERSION-fpm
        
        # Install version-specific extensions
        install_version_specific_extensions "$PHP_VERSION"
        
        log "PHP $PHP_VERSION installed successfully"
    else
        log_warning "PHP version $PHP_VERSION is already installed. Skipping installation."
    fi
}

# Install PHP extensions that vary based on PHP version
# Arguments:
#   $1 - PHP version number
install_version_specific_extensions() {
    local PHP_VERSION=$1
    
    # PHP versions before 8.0 require different extensions
    # mcrypt, recode, json are deprecated/removed in PHP 8+
    if [[ "$PHP_VERSION" < "8.0" ]]; then
        log_info "Installing legacy extensions for PHP $PHP_VERSION (< 8.0)"
        apt-get install -y \
            php$PHP_VERSION-json \
            php$PHP_VERSION-recode \
            php$PHP_VERSION-mcrypt \
            php$PHP_VERSION-apcu-bc
    else
        # PHP 8.0+ uses modern extensions
        log_info "Installing modern extensions for PHP $PHP_VERSION (>= 8.0)"
        apt-get install -y php$PHP_VERSION-xdebug
    fi
}

# =============================================================================
# PHP CONFIGURATION
# =============================================================================

# Configure php.ini settings for a specific PHP version
# Adjusts memory limits, upload sizes, execution times, and timezone
# Arguments:
#   $1 - PHP version number
configure_php_ini() {
    local PHP_VERSION=$1
    local PHP_INI_FILE="/etc/php/$PHP_VERSION/fpm/php.ini"
    
    if [ -f "$PHP_INI_FILE" ]; then
        log "Configuring php.ini for PHP $PHP_VERSION..."
        
        # Create backup of original php.ini before modifications
        cp "$PHP_INI_FILE" "$PHP_INI_FILE.bak"
        log_info "Backup created: $PHP_INI_FILE.bak"
        
        # Set timezone to UTC
        sed -i 's/;date.timezone =/date.timezone = "UTC"/' "$PHP_INI_FILE"
        
        # Increase memory limit for PHP scripts (default is often 128M)
        sed -i 's/memory_limit = .*/memory_limit = 256M/' "$PHP_INI_FILE"
        
        # Set maximum upload file size
        sed -i 's/upload_max_filesize = .*/upload_max_filesize = 64M/' "$PHP_INI_FILE"
        
        # Set maximum POST data size (should be >= upload_max_filesize)
        sed -i 's/post_max_size = .*/post_max_size = 64M/' "$PHP_INI_FILE"
        
        # Set maximum script execution time in seconds
        sed -i 's/max_execution_time = .*/max_execution_time = 300/' "$PHP_INI_FILE"
        
        # Set maximum time for input parsing in seconds
        sed -i 's/max_input_time = .*/max_input_time = 300/' "$PHP_INI_FILE"
        
        log "php.ini configuration completed for PHP $PHP_VERSION"
    else
        log_error "php.ini file not found at $PHP_INI_FILE for version $PHP_VERSION!"
    fi
}

# =============================================================================
# SERVICE MANAGEMENT
# =============================================================================

# Enable and start PHP-FPM service for a specific PHP version
# Arguments:
#   $1 - PHP version number
manage_php_fpm_service() {
    local PHP_VERSION=$1
    
    log "Enabling and starting PHP $PHP_VERSION FPM service..."
    
    # Enable service to start automatically on system boot
    systemctl enable php$PHP_VERSION-fpm
    
    # Start the service immediately
    systemctl start php$PHP_VERSION-fpm
    
    # Check if service started successfully
    if systemctl is-active --quiet php$PHP_VERSION-fpm; then
        log "PHP $PHP_VERSION FPM service is running"
    else
        log_error "Failed to start PHP $PHP_VERSION FPM service"
    fi
}

# =============================================================================
# ISPCONFIG INTEGRATION
# =============================================================================

# Import PHP version information into ISPConfig database
# This allows ISPConfig to recognize and use the newly installed PHP versions
integrate_with_ispconfig() {
    if [ "$AUTO_ADD_TO_ISPCONFIG" == "yes" ]; then
        log "Integrating PHP versions with ISPConfig database..."
        
        # TODO: Implement SQL import commands here
        # This should add entries to the ISPConfig database for each PHP version
        # The SQL commands would typically insert records into the server_php table
        
        log_warning "ISPConfig integration not yet implemented. Please add PHP versions manually."
    else
        log_info "Automatic ISPConfig integration is disabled in configuration"
    fi
}

# =============================================================================
# MAIN EXECUTION FLOW
# =============================================================================

# Main function that orchestrates the entire installation process
main() {
    log "=========================================="
    log "ISPConfig PHP Installer Script Started"
    log "=========================================="
    
    # Step 1: Check prerequisites
    check_root_privileges
    load_configuration
    detect_debian_version
    
    # Step 2: Setup repository
    add_sury_repository
    
    # Step 3: Install and configure each PHP version
    for PHP_VERSION in ${PHP_VERSIONS[@]}; do
        log "=========================================="
        log "Processing PHP version $PHP_VERSION"
        log "=========================================="
        
        install_php_version "$PHP_VERSION"
        configure_php_ini "$PHP_VERSION"
        manage_php_fpm_service "$PHP_VERSION"
    done
    
    # Step 4: Integrate with ISPConfig if enabled
    integrate_with_ispconfig
    
    # Step 5: Display summary
    log "=========================================="
    log "Installation completed successfully!"
    log "PHP versions installed: ${PHP_VERSIONS[@]}"
    log "=========================================="
}

# Execute main function
main
