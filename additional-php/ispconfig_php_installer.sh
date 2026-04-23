#!/bin/bash

# =============================================================================
# ISPConfig PHP Installer Script
# =============================================================================
#
# This script automates the installation of multiple PHP versions on ISPConfig
# servers. It handles:
# - Detection of the Debian/Ubuntu version
# - Addition of the SURY PHP repository
# - Installation of PHP versions with all required extensions
# - Configuration of php.ini settings for each version
# - Management of PHP-FPM services
# - Optional integration with ISPConfig database
#
# Requirements:
# - Root privileges
# - Debian/Ubuntu based system
# - ispconfig_php_installer.conf configuration file
#
# Usage:
#   ./ispconfig_php_installer.sh [OPTIONS]
#
# Options:
#   --config <file>    Config file path (default: <script-dir>/ispconfig_php_installer.conf)
#   --mode <mode>      Installation mode: auto|interactive|dry-run (default: auto)
#   --dry-run          Print commands without executing them (same as --mode dry-run)
#   -h, --help         Show this help message
#
# =============================================================================

# =============================================================================
# DEFAULTS
# =============================================================================

DEFAULT_CONFIG="$(dirname "$0")/ispconfig_php_installer.conf"
DEFAULT_MODE="auto"
DRY_RUN=false

# =============================================================================
# COLORED LOGGING FUNCTIONS
# =============================================================================

# Standard informational message in green
log() {
    echo -e "\e[32m[INFO]\e[0m $1"
}

# Error message in red
log_error() {
    echo -e "\e[31m[ERROR]\e[0m $1" >&2
}

# Warning message in yellow
log_warning() {
    echo -e "\e[33m[WARNING]\e[0m $1"
}

# Informational message in blue
log_info() {
    echo -e "\e[34m[INFO]\e[0m $1"
}

# Dry-run command indicator in cyan
log_dry_run() {
    echo -e "\e[36m[DRY-RUN]\e[0m $1"
}

# =============================================================================
# HELP
# =============================================================================

# Display usage information and exit
show_help() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "ISPConfig PHP Installer - installs multiple PHP versions with all extensions"
    echo ""
    echo "Options:"
    echo "  --config <file>    Config file path"
    echo "                     (default: $(dirname "$0")/ispconfig_php_installer.conf)"
    echo "  --mode <mode>      Installation mode (default: auto)"
    echo "                       auto        - Install without prompts"
    echo "                       interactive - Ask for confirmation per PHP version"
    echo "                       dry-run     - Print commands without executing"
    echo "  --dry-run          Shorthand for --mode dry-run"
    echo "  -h, --help         Show this help message"
}

# =============================================================================
# ARGUMENT PARSING
# =============================================================================

# Parse command-line arguments, setting CONFIG_FILE, INSTALL_MODE, and DRY_RUN
parse_arguments() {
    CONFIG_FILE="$DEFAULT_CONFIG"
    INSTALL_MODE="$DEFAULT_MODE"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --config)
                if [[ -z "${2:-}" ]]; then
                    log_error "--config requires a file path argument"
                    exit 1
                fi
                CONFIG_FILE="$2"
                shift 2
                ;;
            --mode)
                if [[ -z "${2:-}" ]]; then
                    log_error "--mode requires a value: auto|interactive|dry-run"
                    exit 1
                fi
                case "$2" in
                    auto|interactive|dry-run)
                        INSTALL_MODE="$2"
                        ;;
                    *)
                        log_error "Invalid mode: '$2'. Valid modes: auto, interactive, dry-run"
                        show_help
                        exit 1
                        ;;
                esac
                shift 2
                ;;
            --dry-run)
                DRY_RUN=true
                INSTALL_MODE="dry-run"
                shift
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done

    if [ "$INSTALL_MODE" = "dry-run" ]; then
        DRY_RUN=true
    fi
}

# =============================================================================
# COMMAND WRAPPER (supports dry-run mode)
# =============================================================================

# Execute a command or print it when dry-run mode is active
# Arguments: full command with arguments
run_cmd() {
    if [ "$DRY_RUN" = true ]; then
        log_dry_run "$*"
    else
        "$@"
    fi
}

# =============================================================================
# SYSTEM CHECKS AND PREREQUISITES
# =============================================================================

# Check if the script is being run with root privileges
# Skipped in dry-run mode since no system changes are made
# Exit with error code 1 if not running as root (in non-dry-run mode)
check_root_privileges() {
    if [ "$DRY_RUN" = true ]; then
        return
    fi
    if [ "$EUID" -ne 0 ]; then
        log_error "This script must be run as root (use sudo or login as root)"
        exit 1
    fi
}

# Load the configuration file containing PHP versions and settings
# Exit with error code 1 if configuration file is not found
load_configuration() {
    if [ -f "$CONFIG_FILE" ]; then
        # shellcheck source=/dev/null
        source "$CONFIG_FILE"
        log "Configuration file loaded: $CONFIG_FILE"
    else
        log_error "Configuration file not found: $CONFIG_FILE"
        exit 1
    fi
}

# Build the PHP_VERSIONS array from individual INSTALL_PHP_XX config variables
# Reads INSTALL_PHP_56 through INSTALL_PHP_84 and collects versions set to "yes"
build_php_versions_array() {
    PHP_VERSIONS=()

    local -A VERSION_FLAGS=(
        ["5.6"]="${INSTALL_PHP_56:-no}"
        ["7.0"]="${INSTALL_PHP_70:-no}"
        ["7.1"]="${INSTALL_PHP_71:-no}"
        ["7.2"]="${INSTALL_PHP_72:-no}"
        ["7.3"]="${INSTALL_PHP_73:-no}"
        ["7.4"]="${INSTALL_PHP_74:-no}"
        ["8.0"]="${INSTALL_PHP_80:-no}"
        ["8.1"]="${INSTALL_PHP_81:-no}"
        ["8.2"]="${INSTALL_PHP_82:-no}"
        ["8.3"]="${INSTALL_PHP_83:-no}"
        ["8.4"]="${INSTALL_PHP_84:-no}"
    )

    for VERSION in 5.6 7.0 7.1 7.2 7.3 7.4 8.0 8.1 8.2 8.3 8.4; do
        if [ "${VERSION_FLAGS[$VERSION]:-no}" = "yes" ]; then
            PHP_VERSIONS+=("$VERSION")
        fi
    done

    if [ ${#PHP_VERSIONS[@]} -eq 0 ]; then
        log_warning "No PHP versions selected for installation."
        log_warning "Set INSTALL_PHP_XX=yes in the configuration file."
    else
        log "PHP versions to install: ${PHP_VERSIONS[*]}"
    fi
}

# Detect the current Debian/Ubuntu version
# Sets DEBIAN_VERSION global variable
detect_debian_version() {
    DEBIAN_VERSION=$(lsb_release -rs)
    log "Detected Debian/Ubuntu version: $DEBIAN_VERSION"
}

# =============================================================================
# VERSION COMPARISON HELPERS
# =============================================================================

# Returns 0 (true) if version $1 is strictly less than $2
version_lt() {
    awk "BEGIN{exit !($1 < $2)}"
}

# Returns 0 (true) if version $1 is less than or equal to $2
version_le() {
    awk "BEGIN{exit !($1 <= $2)}"
}

# Returns 0 (true) if version $1 is greater than or equal to $2
version_ge() {
    awk "BEGIN{exit !($1 >= $2)}"
}

# =============================================================================
# REPOSITORY MANAGEMENT
# =============================================================================

# Add the SURY PHP repository for Debian/Ubuntu if not already present
# Uses the official packages.sury.org method (works on both Debian and Ubuntu)
add_sury_repository() {
    if [ -f /etc/apt/sources.list.d/php.list ] || apt-cache policy 2>/dev/null | grep -q "packages.sury.org"; then
        log "SURY repository is already configured"
        return
    fi

    log "Adding SURY PHP repository..."
    run_cmd apt-get install -y apt-transport-https lsb-release ca-certificates wget
    run_cmd wget -O /etc/apt/trusted.gpg.d/php.gpg https://packages.sury.org/php/apt.gpg
    local CODENAME
    CODENAME=$(lsb_release -c -s)
    run_cmd bash -c "echo \"deb https://packages.sury.org/php/ ${CODENAME} main\" > /etc/apt/sources.list.d/php.list"
    run_cmd apt-get update
    log "SURY repository added successfully"
}

# =============================================================================
# PACKAGE MANAGEMENT
# =============================================================================

# Check if a specific package is installed on the system
# Arguments:
#   $1 - exact package name to check
# Returns: 0 if installed, non-zero if not installed
check_package_installed() {
    dpkg -s "$1" 2>/dev/null | grep -q "^Status: install ok installed"
}

# Build the complete list of packages to install for a given PHP version
# The list is based on the documentation (ispconfig_additional_php.txt) and
# the optional extension flags from the configuration file
# Arguments:
#   $1 - PHP version number (e.g. 5.6, 7.4, 8.0)
# Outputs space-separated package names to stdout
get_packages_for_version() {
    local PHP_VERSION=$1
    local PKGS=()

    # Base packages available for all supported PHP versions
    PKGS+=(
        "php${PHP_VERSION}"
        "php${PHP_VERSION}-common"
        "php${PHP_VERSION}-cli"
        "php${PHP_VERSION}-cgi"
        "php${PHP_VERSION}-fpm"
        "php${PHP_VERSION}-curl"
        "php${PHP_VERSION}-intl"
        "php${PHP_VERSION}-mbstring"
        "php${PHP_VERSION}-pspell"
        "php${PHP_VERSION}-gd"
        "php${PHP_VERSION}-mysql"
        "php${PHP_VERSION}-sqlite3"
        "php${PHP_VERSION}-ldap"
        "php${PHP_VERSION}-imap"
        "php${PHP_VERSION}-opcache"
        "php${PHP_VERSION}-phpdbg"
        "php${PHP_VERSION}-tidy"
        "php${PHP_VERSION}-readline"
        "php${PHP_VERSION}-soap"
        "php${PHP_VERSION}-xmlrpc"
        "php${PHP_VERSION}-xml"
        "php${PHP_VERSION}-xsl"
        "php${PHP_VERSION}-zip"
    )

    # PHP < 8.0: JSON is a separate package (built-in from 8.0 onwards)
    if version_lt "$PHP_VERSION" "8.0"; then
        PKGS+=("php${PHP_VERSION}-json")
    fi

    # PHP <= 7.3: gettext is a separate package (merged into common from 7.4 onwards)
    if version_le "$PHP_VERSION" "7.3"; then
        PKGS+=("php${PHP_VERSION}-gettext")
    fi

    # PHP <= 7.3: recode extension available (removed in PHP 7.4), controlled by config
    if [ "${INSTALL_RECODE:-yes}" = "yes" ] && version_le "$PHP_VERSION" "7.3"; then
        PKGS+=("php${PHP_VERSION}-recode")
    fi

    # PHP <= 7.1: mcrypt available as a native package (PECL only from 7.2 onwards), controlled by config
    if [ "${INSTALL_MCRYPT:-yes}" = "yes" ] && version_le "$PHP_VERSION" "7.1"; then
        PKGS+=("php${PHP_VERSION}-mcrypt")
    fi

    # Optional extensions controlled by configuration flags
    if [ "${INSTALL_IMAGICK:-yes}" = "yes" ]; then
        PKGS+=("php${PHP_VERSION}-imagick")
    fi
    if [ "${INSTALL_MEMCACHE:-yes}" = "yes" ]; then
        PKGS+=("php${PHP_VERSION}-memcache")
    fi
    if [ "${INSTALL_MEMCACHED:-yes}" = "yes" ]; then
        PKGS+=("php${PHP_VERSION}-memcached")
    fi
    if [ "${INSTALL_APCU:-yes}" = "yes" ]; then
        PKGS+=("php${PHP_VERSION}-apcu")
    fi

    # apcu-bc: compatibility layer, only available for PHP < 8.0
    if [ "${INSTALL_APCU_BC:-yes}" = "yes" ] && version_lt "$PHP_VERSION" "8.0"; then
        PKGS+=("php${PHP_VERSION}-apcu-bc")
    fi

    echo "${PKGS[@]}"
}

# Install a specific PHP version with all required extensions
# Skips installation if PHP-FPM for this version is already installed (idempotent)
# Arguments:
#   $1 - PHP version number (e.g., 7.4, 8.0, 8.1)
install_php_version() {
    local PHP_VERSION=$1

    if check_package_installed "php${PHP_VERSION}-fpm"; then
        log_warning "PHP $PHP_VERSION is already installed. Skipping."
        return
    fi

    log "Installing PHP $PHP_VERSION and all extensions..."

    local PACKAGES
    read -ra PACKAGES <<< "$(get_packages_for_version "$PHP_VERSION")"
    run_cmd apt-get install -y "${PACKAGES[@]}"

    log "PHP $PHP_VERSION installed successfully"
}

# =============================================================================
# INTERACTIVE CONFIRMATION
# =============================================================================

# Prompt the user for confirmation in interactive mode
# In auto or dry-run mode always returns 0 (proceed)
# Arguments:
#   $1 - Prompt message
# Returns: 0 to proceed, 1 to skip
confirm_action() {
    local PROMPT="$1"
    local REPLY

    if [ "$INSTALL_MODE" != "interactive" ]; then
        return 0
    fi

    echo -n "$PROMPT [y/N] "
    read -r REPLY
    case "$REPLY" in
        [yY][eE][sS]|[yY])
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

# =============================================================================
# PHP CONFIGURATION
# =============================================================================

# Configure php.ini settings for a specific PHP version using values from the
# configuration file. Creates a one-time backup before the first modification.
# Arguments:
#   $1 - PHP version number
configure_php_ini() {
    local PHP_VERSION=$1
    local PHP_INI_FILE="/etc/php/${PHP_VERSION}/fpm/php.ini"

    if [ "$DRY_RUN" = true ]; then
        log_dry_run "Would configure: $PHP_INI_FILE"
        log_dry_run "  date.timezone        = \"${PHP_TIMEZONE:-UTC}\""
        log_dry_run "  cgi.fix_pathinfo     = ${PHP_CGI_FIX_PATHINFO:-0}"
        log_dry_run "  memory_limit         = ${PHP_MEMORY_LIMIT:-256M}"
        log_dry_run "  upload_max_filesize  = ${PHP_UPLOAD_MAX_FILESIZE:-64M}"
        log_dry_run "  post_max_size        = ${PHP_POST_MAX_SIZE:-64M}"
        log_dry_run "  max_execution_time   = ${PHP_MAX_EXECUTION_TIME:-300}"
        log_dry_run "  max_input_time       = ${PHP_MAX_INPUT_TIME:-300}"
        return
    fi

    if [ ! -f "$PHP_INI_FILE" ]; then
        log_error "php.ini not found: $PHP_INI_FILE"
        return
    fi

    log "Configuring php.ini for PHP $PHP_VERSION..."

    # Create backup only on the first run (idempotent)
    if [ ! -f "${PHP_INI_FILE}.bak" ]; then
        cp "$PHP_INI_FILE" "${PHP_INI_FILE}.bak"
        log_info "Backup created: ${PHP_INI_FILE}.bak"
    fi

    local TIMEZONE="${PHP_TIMEZONE:-UTC}"
    local CGI_FIX="${PHP_CGI_FIX_PATHINFO:-0}"
    local MEM_LIMIT="${PHP_MEMORY_LIMIT:-256M}"
    local UPLOAD_SIZE="${PHP_UPLOAD_MAX_FILESIZE:-64M}"
    local POST_SIZE="${PHP_POST_MAX_SIZE:-64M}"
    local MAX_EXEC="${PHP_MAX_EXECUTION_TIME:-300}"
    local MAX_INPUT="${PHP_MAX_INPUT_TIME:-300}"

    # Set or replace timezone (handles both commented and uncommented forms)
    sed -i "s|;*date\.timezone\s*=.*|date.timezone = \"${TIMEZONE}\"|" "$PHP_INI_FILE"

    # Set CGI fix_pathinfo (0 is recommended for security)
    sed -i "s|;*cgi\.fix_pathinfo\s*=.*|cgi.fix_pathinfo = ${CGI_FIX}|" "$PHP_INI_FILE"

    # Set memory limit
    sed -i "s|memory_limit\s*=.*|memory_limit = ${MEM_LIMIT}|" "$PHP_INI_FILE"

    # Set maximum upload file size
    sed -i "s|upload_max_filesize\s*=.*|upload_max_filesize = ${UPLOAD_SIZE}|" "$PHP_INI_FILE"

    # Set maximum POST data size (should be >= upload_max_filesize)
    sed -i "s|post_max_size\s*=.*|post_max_size = ${POST_SIZE}|" "$PHP_INI_FILE"

    # Set maximum script execution time in seconds
    sed -i "s|max_execution_time\s*=.*|max_execution_time = ${MAX_EXEC}|" "$PHP_INI_FILE"

    # Set maximum time for input parsing in seconds
    sed -i "s|max_input_time\s*=.*|max_input_time = ${MAX_INPUT}|" "$PHP_INI_FILE"

    log "php.ini configured for PHP $PHP_VERSION"
}

# =============================================================================
# SERVICE MANAGEMENT
# =============================================================================

# Enable and optionally start PHP-FPM service for a specific PHP version
# Behavior is controlled by ENABLE_FPM_SERVICES and START_FPM_SERVICES config flags
# Arguments:
#   $1 - PHP version number
manage_php_fpm_service() {
    local PHP_VERSION=$1

    if [ "${ENABLE_FPM_SERVICES:-yes}" = "yes" ]; then
        log "Enabling php${PHP_VERSION}-fpm service..."
        run_cmd systemctl enable "php${PHP_VERSION}-fpm"
    fi

    if [ "${START_FPM_SERVICES:-no}" = "yes" ]; then
        log "Starting php${PHP_VERSION}-fpm service..."
        run_cmd systemctl start "php${PHP_VERSION}-fpm"

        if [ "$DRY_RUN" != true ]; then
            if systemctl is-active --quiet "php${PHP_VERSION}-fpm"; then
                log "PHP ${PHP_VERSION}-fpm service is running"
            else
                log_error "Failed to start PHP ${PHP_VERSION}-fpm service"
            fi
        fi
    fi
}

# =============================================================================
# ISPCONFIG INTEGRATION
# =============================================================================

# Import PHP version information into ISPConfig database
# This allows ISPConfig to recognize and use the newly installed PHP versions
integrate_with_ispconfig() {
    if [ "${AUTO_ADD_TO_ISPCONFIG:-no}" = "yes" ]; then
        log "Integrating PHP versions with ISPConfig database..."

        # TODO: Implement SQL import for each PHP version
        # The SQL commands would insert records into the server_php table
        # using ISPCONFIG_DB_HOST, ISPCONFIG_DB_NAME, ISPCONFIG_DB_USER,
        # ISPCONFIG_DB_PASS, and ISPCONFIG_SERVER_ID from the config.

        log_warning "ISPConfig database integration not yet implemented."
        log_warning "Please add PHP versions manually: System -> Additional PHP Versions"
    else
        log_info "ISPConfig integration disabled (AUTO_ADD_TO_ISPCONFIG != yes)"
    fi
}

# =============================================================================
# MAIN EXECUTION FLOW
# =============================================================================

# Main function that orchestrates the entire installation process
main() {
    # Parse command-line arguments before anything else
    parse_arguments "$@"

    if [ "$DRY_RUN" = true ]; then
        log_dry_run "Dry-run mode enabled. No changes will be made to the system."
    fi

    log "=========================================="
    log "ISPConfig PHP Installer Script Started"
    log "=========================================="

    # Step 1: Prerequisites
    check_root_privileges
    load_configuration
    build_php_versions_array
    detect_debian_version

    if [ ${#PHP_VERSIONS[@]} -eq 0 ]; then
        log "Nothing to install. Exiting."
        exit 0
    fi

    # Step 2: Setup SURY repository (if enabled in configuration)
    if [ "${INSTALL_SURY_REPO:-yes}" = "yes" ]; then
        add_sury_repository
    fi

    # Step 3: Install and configure each selected PHP version
    for PHP_VERSION in "${PHP_VERSIONS[@]}"; do
        log "=========================================="
        log "Processing PHP version $PHP_VERSION"
        log "=========================================="

        if ! confirm_action "Install PHP $PHP_VERSION?"; then
            log_info "Skipping PHP $PHP_VERSION"
            continue
        fi

        install_php_version "$PHP_VERSION"

        if [ "${CONFIGURE_PHP_INI:-yes}" = "yes" ]; then
            configure_php_ini "$PHP_VERSION"
        fi

        manage_php_fpm_service "$PHP_VERSION"
    done

    # Step 4: Integrate with ISPConfig if enabled
    integrate_with_ispconfig

    # Step 5: Cleanup package cache
    if [ "${CLEANUP_AFTER_INSTALL:-yes}" = "yes" ]; then
        log "Cleaning up package cache..."
        run_cmd apt-get autoremove -y
        run_cmd apt-get autoclean
    fi

    # Step 6: Summary
    log "=========================================="
    log "Installation completed!"
    log "PHP versions processed: ${PHP_VERSIONS[*]}"
    if [ "$DRY_RUN" = true ]; then
        log_dry_run "Dry-run: no actual changes were made."
    fi
    log "=========================================="
}

# Execute main function with all arguments
main "$@"
