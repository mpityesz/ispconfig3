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
    local MSG="[INFO] $1"
    echo -e "\e[32m${MSG}\e[0m"
    if [ -n "${INSTALL_LOG:-}" ] && [ "$DRY_RUN" != true ]; then
        echo "${MSG}" >> "$INSTALL_LOG"
    fi
}

# Error message in red
log_error() {
    local MSG="[ERROR] $1"
    echo -e "\e[31m${MSG}\e[0m" >&2
    if [ -n "${INSTALL_LOG:-}" ] && [ "$DRY_RUN" != true ]; then
        echo "${MSG}" >> "$INSTALL_LOG"
    fi
}

# Warning message in yellow
log_warning() {
    local MSG="[WARNING] $1"
    echo -e "\e[33m${MSG}\e[0m"
    if [ -n "${INSTALL_LOG:-}" ] && [ "$DRY_RUN" != true ]; then
        echo "${MSG}" >> "$INSTALL_LOG"
    fi
}

# Informational message in blue
log_info() {
    local MSG="[INFO] $1"
    echo -e "\e[34m${MSG}\e[0m"
    if [ -n "${INSTALL_LOG:-}" ] && [ "$DRY_RUN" != true ]; then
        echo "${MSG}" >> "$INSTALL_LOG"
    fi
}

# Dry-run command indicator in cyan
log_dry_run() {
    local MSG="[DRY-RUN] $1"
    echo -e "\e[36m${MSG}\e[0m"
    if [ -n "${INSTALL_LOG:-}" ]; then
        echo "${MSG}" >> "$INSTALL_LOG"
    fi
}

# =============================================================================
# DIRECTORY MANAGEMENT
# =============================================================================

# Create necessary directories for logging
# Creates the installation log directory and PHP-specific log directories
create_directories() {
    # Create directory for installation log file
    if [ -n "${INSTALL_LOG:-}" ]; then
        local INSTALL_LOG_DIR
        INSTALL_LOG_DIR=$(dirname "$INSTALL_LOG")
        
        if [ "$DRY_RUN" = true ]; then
            if [ ! -d "$INSTALL_LOG_DIR" ]; then
                log_dry_run "Would create installation log directory: $INSTALL_LOG_DIR"
            fi
        else
            if [ ! -d "$INSTALL_LOG_DIR" ]; then
                mkdir -p "$INSTALL_LOG_DIR" && \
                    log "Created installation log directory: $INSTALL_LOG_DIR" || \
                    log_warning "Failed to create installation log directory: $INSTALL_LOG_DIR"
            fi
        fi
    fi

    # Create PHP log directories for each version
    if [ "${CREATE_LOG_DIR:-yes}" = "yes" ] && [ -n "${LOG_DIR:-}" ]; then
        if [ ${#PHP_VERSIONS[@]} -eq 0 ]; then
            return
        fi

        for PHP_VERSION in "${PHP_VERSIONS[@]}"; do
            local PHP_LOG_DIR="${LOG_DIR}/${PHP_VERSION}"
            
            if [ "$DRY_RUN" = true ]; then
                log_dry_run "Would create PHP log directory: $PHP_LOG_DIR"
            else
                if [ ! -d "$PHP_LOG_DIR" ]; then
                    mkdir -p "$PHP_LOG_DIR" && \
                        log "Created PHP ${PHP_VERSION} log directory: $PHP_LOG_DIR" || \
                        log_warning "Failed to create PHP ${PHP_VERSION} log directory: $PHP_LOG_DIR"
                    
                    # Set proper permissions (www-data:www-data 755)
                    if [ -d "$PHP_LOG_DIR" ]; then
                        chown www-data:www-data "$PHP_LOG_DIR" 2>/dev/null || true
                        chmod 755 "$PHP_LOG_DIR" 2>/dev/null || true
                    fi
                fi
            fi
        done
    fi
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
    # Check if repository is already configured
    local REPO_EXISTS=false
    if [ -f /etc/apt/sources.list.d/php.list ]; then
        REPO_EXISTS=true
        log "SURY repository configuration file exists: /etc/apt/sources.list.d/php.list"
    elif [ "$DRY_RUN" != true ] && apt-cache policy 2>/dev/null | grep -q "packages.sury.org"; then
        REPO_EXISTS=true
        log "SURY repository is already configured in apt sources"
    fi

    if [ "$REPO_EXISTS" = true ]; then
        log "SURY repository is already configured"
        return
    fi

    log "Adding SURY PHP repository..."
    
    if [ "$DRY_RUN" = true ]; then
        log_dry_run "Repository not found, would perform the following steps:"
        log_dry_run "  1. Install prerequisites: apt-get install -y apt-transport-https lsb-release ca-certificates wget"
        log_dry_run "  2. Download GPG key: wget -O /etc/apt/trusted.gpg.d/php.gpg https://packages.sury.org/php/apt.gpg"
        local CODENAME
        CODENAME=$(lsb_release -c -s 2>/dev/null || echo "unknown")
        log_dry_run "  3. Create repository file: /etc/apt/sources.list.d/php.list"
        log_dry_run "     Content: deb https://packages.sury.org/php/ ${CODENAME} main"
        log_dry_run "  4. Update package lists: apt-get update"
        return
    fi
    
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
    
    if [ "$DRY_RUN" = true ]; then
        log_dry_run "Would install ${#PACKAGES[@]} packages for PHP ${PHP_VERSION}:"
        for pkg in "${PACKAGES[@]}"; do
            log_dry_run "  - $pkg"
        done
        log_dry_run "Command: apt-get install -y ${PACKAGES[*]}"
        return
    fi
    
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
        
        # Show PHP log directory configuration if enabled
        if [ -n "${LOG_DIR:-}" ]; then
            log_dry_run "  error_log            = ${LOG_DIR}/${PHP_VERSION}/error.log"
        fi
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

    # Configure PHP error log to version-specific directory
    if [ -n "${LOG_DIR:-}" ]; then
        local PHP_ERROR_LOG="${LOG_DIR}/${PHP_VERSION}/error.log"
        sed -i "s|;*error_log\s*=.*|error_log = ${PHP_ERROR_LOG}|" "$PHP_INI_FILE"
        log_info "PHP error log configured: $PHP_ERROR_LOG"
    fi

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

# Return the sortprio value for a given PHP version
# Newer versions get a lower number so they appear first in ISPConfig
# Arguments:
#   $1 - PHP version number (e.g. 5.6, 7.4, 8.3)
get_sortprio() {
    local PHP_VERSION=$1
    case "$PHP_VERSION" in
        8.4) echo 10 ;;
        8.3) echo 20 ;;
        8.2) echo 30 ;;
        8.1) echo 40 ;;
        8.0) echo 50 ;;
        7.4) echo 60 ;;
        7.3) echo 70 ;;
        7.2) echo 80 ;;
        7.1) echo 90 ;;
        7.0) echo 100 ;;
        5.6) echo 110 ;;
        *)   echo 100 ;;
    esac
}

# Import PHP version information into ISPConfig database
# This allows ISPConfig to recognize and use the newly installed PHP versions
integrate_with_ispconfig() {
    if [ "${AUTO_ADD_TO_ISPCONFIG:-no}" = "yes" ]; then
        log "Integrating PHP versions with ISPConfig database..."

        # Determine which MySQL/MariaDB client is available
        local MYSQL_CMD
        if command -v mariadb &>/dev/null; then
            MYSQL_CMD="mariadb"
        elif command -v mysql &>/dev/null; then
            MYSQL_CMD="mysql"
        else
            log_warning "No MySQL/MariaDB client found. Skipping ISPConfig integration."
            return
        fi

        local DB_ARGS=(
            -h "${ISPCONFIG_DB_HOST:-localhost}"
            -u "${ISPCONFIG_DB_USER:-root}"
            "${ISPCONFIG_DB_NAME:-dbispconfig}"
        )
        # Pass password via environment variable to avoid exposure in process listings
        if [ -n "${ISPCONFIG_DB_PASS:-}" ]; then
            export MYSQL_PWD="${ISPCONFIG_DB_PASS}"
        fi

        for PHP_VERSION in "${PHP_VERSIONS[@]}"; do
            local NAME="PHP ${PHP_VERSION} - Sury"
            local FASTCGI_BIN="php-cgi${PHP_VERSION}"
            local FASTCGI_INI="/etc/php/${PHP_VERSION}/cgi/php.ini"
            local FPM_INIT="php${PHP_VERSION}-fpm"
            local FPM_INI="/etc/php/${PHP_VERSION}/fpm/php.ini"
            local FPM_POOL="/etc/php/${PHP_VERSION}/fpm/pool.d"
            local FPM_SOCKET="/var/lib/php${PHP_VERSION}-fpm"
            local CLI_BIN="php${PHP_VERSION}"
            local SORTPRIO
            SORTPRIO=$(get_sortprio "$PHP_VERSION")
            local SERVER_ID="${ISPCONFIG_SERVER_ID:-1}"

            # Sanitize string values: escape single quotes for SQL safety
            local safe_NAME="${NAME//\'/\'\'}"
            local safe_FASTCGI_BIN="${FASTCGI_BIN//\'/\'\'}"
            local safe_FASTCGI_INI="${FASTCGI_INI//\'/\'\'}"
            local safe_FPM_INIT="${FPM_INIT//\'/\'\'}"
            local safe_FPM_INI="${FPM_INI//\'/\'\'}"
            local safe_FPM_POOL="${FPM_POOL//\'/\'\'}"
            local safe_FPM_SOCKET="${FPM_SOCKET//\'/\'\'}"
            local safe_CLI_BIN="${CLI_BIN//\'/\'\'}"

            local SQL
            SQL="INSERT IGNORE INTO \`server_php\` (
                \`sys_userid\`, \`sys_groupid\`,
                \`sys_perm_user\`, \`sys_perm_group\`, \`sys_perm_other\`,
                \`server_id\`, \`client_id\`,
                \`name\`,
                \`php_fastcgi_binary\`, \`php_fastcgi_ini_dir\`,
                \`php_fpm_init_script\`, \`php_fpm_ini_dir\`,
                \`php_fpm_pool_dir\`, \`php_fpm_socket_dir\`,
                \`php_cli_binary\`,
                \`active\`, \`sortprio\`
            ) VALUES (
                1, 1,
                'riud', 'riud', '',
                ${SERVER_ID}, 0,
                '${safe_NAME}',
                '${safe_FASTCGI_BIN}', '${safe_FASTCGI_INI}',
                '${safe_FPM_INIT}', '${safe_FPM_INI}',
                '${safe_FPM_POOL}', '${safe_FPM_SOCKET}',
                '${safe_CLI_BIN}',
                'y', ${SORTPRIO}
            );"

            if [ "$DRY_RUN" = true ]; then
                log_dry_run "Would execute SQL for PHP ${PHP_VERSION}: ${SQL}"
            else
                if echo "$SQL" | "$MYSQL_CMD" "${DB_ARGS[@]}" 2>/dev/null; then
                    log "Added PHP ${PHP_VERSION} to ISPConfig database (${NAME})"
                else
                    log_warning "Failed to add PHP ${PHP_VERSION} to ISPConfig database. Check credentials."
                fi
            fi
        done
    else
        log_info "ISPConfig integration disabled (AUTO_ADD_TO_ISPCONFIG != yes)"
    fi
}

# =============================================================================
# UPDATE-ALTERNATIVES CONFIGURATION
# =============================================================================

# Configure update-alternatives for all installed PHP versions
# Sets the recommended default PHP version based on Debian/Ubuntu version
configure_update_alternatives() {
    log "Configuring update-alternatives for PHP..."

    if [ ${#PHP_VERSIONS[@]} -eq 0 ]; then
        return
    fi

    # Determine recommended PHP version based on Debian/Ubuntu version
    local RECOMMENDED_PHP=""
    
    if version_ge "$DEBIAN_VERSION" "13"; then
        RECOMMENDED_PHP="8.3"  # Debian 13 (Trixie) - estimated
    elif version_ge "$DEBIAN_VERSION" "12"; then
        RECOMMENDED_PHP="8.2"  # Debian 12 (Bookworm)
    elif version_ge "$DEBIAN_VERSION" "11"; then
        RECOMMENDED_PHP="7.4"  # Debian 11 (Bullseye)
    elif version_ge "$DEBIAN_VERSION" "10"; then
        RECOMMENDED_PHP="7.3"  # Debian 10 (Buster)
    else
        RECOMMENDED_PHP="7.0"  # Older Debian versions
    fi

    log "Recommended PHP version for Debian ${DEBIAN_VERSION}: ${RECOMMENDED_PHP}"

    # Check if recommended version is installed
    local DEFAULT_VERSION=""
    for PHP_VERSION in "${PHP_VERSIONS[@]}"; do
        if [ "$PHP_VERSION" = "$RECOMMENDED_PHP" ]; then
            DEFAULT_VERSION="$RECOMMENDED_PHP"
            break
        fi
    done

    # If recommended version not installed, use the newest installed version
    if [ -z "$DEFAULT_VERSION" ]; then
        log_warning "Recommended PHP ${RECOMMENDED_PHP} not installed, using newest available version"
        DEFAULT_VERSION="${PHP_VERSIONS[0]}"
        local MIN_PRIO=$(get_sortprio "$DEFAULT_VERSION")
        
        for PHP_VERSION in "${PHP_VERSIONS[@]}"; do
            local PRIO=$(get_sortprio "$PHP_VERSION")
            if [ "$PRIO" -lt "$MIN_PRIO" ]; then
                MIN_PRIO=$PRIO
                DEFAULT_VERSION=$PHP_VERSION
            fi
        done
    fi
    
    local DEFAULT_BIN="/usr/bin/php${DEFAULT_VERSION}"
    
    if [ "$DRY_RUN" = true ]; then
        log_dry_run "Would set default PHP version: update-alternatives --set php ${DEFAULT_BIN}"
    else
        if [ -x "$DEFAULT_BIN" ]; then
            update-alternatives --set php "$DEFAULT_BIN" && \
                log "Set default PHP version to ${DEFAULT_VERSION}" || \
                log_warning "Failed to set default PHP version to ${DEFAULT_VERSION}"
        else
            log_warning "PHP binary not found: ${DEFAULT_BIN}"
        fi
    fi
}

# =============================================================================
# EXTENSION VERIFICATION
# =============================================================================

# Verify that all required and optional extensions are loaded for each PHP version
# Performs comprehensive checks including:
# - Core extensions (always required)
# - Optional extensions (based on configuration)
# - Version-specific extensions (json, gettext, recode, mcrypt, apcu-bc)
# Logs detailed warnings for any missing or non-functional extensions
verify_php_extensions() {
    log "=========================================="
    log "Verifying PHP extensions for all installed versions..."
    log "=========================================="

    # Core extensions that should be present in all PHP versions
    local CORE_EXTENSIONS=(
        "curl"
        "gd"
        "imap"
        "intl"
        "ldap"
        "mbstring"
        "mysql"
        "opcache"
        "pdo_mysql"
        "pdo_sqlite"
        "pspell"
        "readline"
        "soap"
        "sqlite3"
        "tidy"
        "xml"
        "xmlrpc"
        "xsl"
        "zip"
    )

    # Optional extensions map: config variable -> module name
    declare -A OPTIONAL_EXT_MAP=(
        ["INSTALL_IMAGICK"]="imagick"
        ["INSTALL_MEMCACHE"]="memcache"
        ["INSTALL_MEMCACHED"]="memcached"
        ["INSTALL_APCU"]="apcu"
    )

    local TOTAL_ERRORS=0
    local TOTAL_WARNINGS=0

    for PHP_VERSION in "${PHP_VERSIONS[@]}"; do
        local PHP_BIN="php${PHP_VERSION}"
        local VERSION_ERRORS=0
        local VERSION_WARNINGS=0

        log "Checking PHP ${PHP_VERSION}..."

        if [ "$DRY_RUN" = true ]; then
            log_dry_run "Would verify extensions for PHP ${PHP_VERSION} using: ${PHP_BIN} -m"
            continue
        fi

        if ! command -v "$PHP_BIN" &>/dev/null; then
            log_error "PHP binary not found: ${PHP_BIN}. Skipping extension check."
            ((TOTAL_ERRORS++))
            continue
        fi

        # Get loaded modules
        local LOADED_MODULES
        if ! LOADED_MODULES=$("$PHP_BIN" -m 2>/dev/null); then
            log_error "Failed to query PHP ${PHP_VERSION} modules"
            ((TOTAL_ERRORS++))
            continue
        fi

        # Check core extensions
        for EXT in "${CORE_EXTENSIONS[@]}"; do
            # Special handling for mysql -> mysqli
            local CHECK_EXT="$EXT"
            if [ "$EXT" = "mysql" ]; then
                CHECK_EXT="mysqli"
            fi

            if ! echo "$LOADED_MODULES" | grep -qi "^${CHECK_EXT}$"; then
                log_error "PHP ${PHP_VERSION}: MISSING core extension: ${EXT}"
                ((VERSION_ERRORS++))
                ((TOTAL_ERRORS++))
            fi
        done

        # Check version-specific core extensions
        
        # JSON: separate package for PHP < 8.0, built-in from 8.0+
        if version_lt "$PHP_VERSION" "8.0"; then
            if ! echo "$LOADED_MODULES" | grep -qi "^json$"; then
                log_error "PHP ${PHP_VERSION}: MISSING extension: json (required for PHP < 8.0)"
                ((VERSION_ERRORS++))
                ((TOTAL_ERRORS++))
            fi
        fi

        # gettext: separate package for PHP <= 7.3, merged into common from 7.4+
        if version_le "$PHP_VERSION" "7.3"; then
            if ! echo "$LOADED_MODULES" | grep -qi "^gettext$"; then
                log_warning "PHP ${PHP_VERSION}: MISSING extension: gettext (recommended for PHP <= 7.3)"
                ((VERSION_WARNINGS++))
                ((TOTAL_WARNINGS++))
            fi
        fi

        # recode: available only for PHP <= 7.3 (if enabled in config)
        if [ "${INSTALL_RECODE:-yes}" = "yes" ] && version_le "$PHP_VERSION" "7.3"; then
            if ! echo "$LOADED_MODULES" | grep -qi "^recode$"; then
                log_warning "PHP ${PHP_VERSION}: recode is enabled in config but NOT loaded"
                ((VERSION_WARNINGS++))
                ((TOTAL_WARNINGS++))
            fi
        fi

        # mcrypt: native for PHP <= 7.1 (if enabled in config)
        if [ "${INSTALL_MCRYPT:-yes}" = "yes" ] && version_le "$PHP_VERSION" "7.1"; then
            if ! echo "$LOADED_MODULES" | grep -qi "^mcrypt$"; then
                log_warning "PHP ${PHP_VERSION}: mcrypt is enabled in config but NOT loaded"
                ((VERSION_WARNINGS++))
                ((TOTAL_WARNINGS++))
            fi
        fi

        # apcu-bc: available only for PHP < 8.0 (if enabled in config)
        if [ "${INSTALL_APCU_BC:-yes}" = "yes" ] && version_lt "$PHP_VERSION" "8.0"; then
            if ! echo "$LOADED_MODULES" | grep -qi "^apc$"; then
                log_warning "PHP ${PHP_VERSION}: apcu-bc is enabled in config but APC compatibility layer NOT loaded"
                ((VERSION_WARNINGS++))
                ((TOTAL_WARNINGS++))
            fi
        fi

        # Check optional extensions
        for CONFIG_KEY in "${!OPTIONAL_EXT_MAP[@]}"; do
            local CONFIG_VAL="${!CONFIG_KEY:-no}"
            local MODULE_NAME="${OPTIONAL_EXT_MAP[$CONFIG_KEY]}"

            if [ "$CONFIG_VAL" = "yes" ]; then
                if echo "$LOADED_MODULES" | grep -qi "^${MODULE_NAME}$"; then
                    log_info "PHP ${PHP_VERSION}: ${MODULE_NAME} ✓"
                else
                    log_warning "PHP ${PHP_VERSION}: ${MODULE_NAME} is enabled in config but NOT loaded"
                    ((VERSION_WARNINGS++))
                    ((TOTAL_WARNINGS++))
                fi
            fi
        done

        # Test critical functionality
        
        # Test OPcache
        if echo "$LOADED_MODULES" | grep -qi "^opcache$"; then
            if ! "$PHP_BIN" -r "echo opcache_get_status() !== false ? 'OK' : 'FAIL';" 2>/dev/null | grep -q "OK"; then
                log_warning "PHP ${PHP_VERSION}: OPcache loaded but may not be properly configured"
                ((VERSION_WARNINGS++))
                ((TOTAL_WARNINGS++))
            fi
        fi

        # Test APCu (if installed)
        if [ "${INSTALL_APCU:-yes}" = "yes" ] && echo "$LOADED_MODULES" | grep -qi "^apcu$"; then
            if ! "$PHP_BIN" -r "apcu_store('test', 1); echo apcu_fetch('test') === 1 ? 'OK' : 'FAIL';" 2>/dev/null | grep -q "OK"; then
                log_warning "PHP ${PHP_VERSION}: APCu loaded but cache operations failing"
                ((VERSION_WARNINGS++))
                ((TOTAL_WARNINGS++))
            else
                log_info "PHP ${PHP_VERSION}: APCu functional test ✓"
            fi
        fi

        # Test Memcached (if installed)
        if [ "${INSTALL_MEMCACHED:-yes}" = "yes" ] && echo "$LOADED_MODULES" | grep -qi "^memcached$"; then
            if ! "$PHP_BIN" -r "echo class_exists('Memcached') ? 'OK' : 'FAIL';" 2>/dev/null | grep -q "OK"; then
                log_warning "PHP ${PHP_VERSION}: Memcached extension loaded but class not available"
                ((VERSION_WARNINGS++))
                ((TOTAL_WARNINGS++))
            else
                log_info "PHP ${PHP_VERSION}: Memcached class available ✓"
            fi
        fi

        # Summary for this version
        if [ "$VERSION_ERRORS" -eq 0 ] && [ "$VERSION_WARNINGS" -eq 0 ]; then
            log "PHP ${PHP_VERSION}: All extensions verified successfully ✓"
        else
            if [ "$VERSION_ERRORS" -gt 0 ]; then
                log_error "PHP ${PHP_VERSION}: ${VERSION_ERRORS} error(s) found"
            fi
            if [ "$VERSION_WARNINGS" -gt 0 ]; then
                log_warning "PHP ${PHP_VERSION}: ${VERSION_WARNINGS} warning(s) found"
            fi
        fi
        
        echo ""
    done

    # Global summary
    log "=========================================="
    log "Extension Verification Summary"
    log "=========================================="
    log "Total PHP versions checked: ${#PHP_VERSIONS[@]}"
    
    if [ "$TOTAL_ERRORS" -eq 0 ] && [ "$TOTAL_WARNINGS" -eq 0 ]; then
        log "Result: ALL CHECKS PASSED ✓"
    else
        if [ "$TOTAL_ERRORS" -gt 0 ]; then
            log_error "Total errors: ${TOTAL_ERRORS}"
        fi
        if [ "$TOTAL_WARNINGS" -gt 0 ]; then
            log_warning "Total warnings: ${TOTAL_WARNINGS}"
        fi
        
        if [ "$TOTAL_ERRORS" -gt 0 ]; then
            log_error "Some critical extensions are missing. Review the errors above."
        fi
    fi
    log "=========================================="
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

    # Step 2: Create necessary directories
    create_directories

    # Step 3: Setup SURY repository (if enabled in configuration)
    if [ "${INSTALL_SURY_REPO:-yes}" = "yes" ]; then
        add_sury_repository
    fi

    # Step 4: Install and configure each selected PHP version
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

    # Step 5: Configure update-alternatives (if enabled)
    if [ "${CONFIGURE_UPDATE_ALTERNATIVES:-yes}" = "yes" ]; then
        configure_update_alternatives
    fi

    # Step 6: Verify PHP extensions (if enabled)
    if [ "${VERIFY_EXTENSIONS:-yes}" = "yes" ]; then
        verify_php_extensions
    fi

    # Step 7: Integrate with ISPConfig if enabled
    integrate_with_ispconfig

    # Step 8: Cleanup package cache
    if [ "${CLEANUP_AFTER_INSTALL:-yes}" = "yes" ]; then
        log "Cleaning up package cache..."
        run_cmd apt-get autoremove -y
        run_cmd apt-get autoclean
    fi

    # Step 9: Summary
    log "=========================================="
    log "Installation completed!"
    log "PHP versions processed: ${PHP_VERSIONS[*]}"
    if [ "$DRY_RUN" = true ]; then
        log_dry_run "Dry-run: no actual changes were made."
    fi
    if [ -n "${INSTALL_LOG:-}" ]; then
        log "Installation log saved to: $INSTALL_LOG"
    fi
}

# Execute main function with all script arguments
main "$@"
