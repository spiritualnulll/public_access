#!/bin/bash

###############################################################################
#                                                                             #
# Project: Pterodactyl Panel Installer                                        #
#                                                                             #
# Copyright (C) 2018 - 2025, Vilhelm Prytz, <vilhelm@prytznet.se>             #
#                                                                             #
# This program is free software: you can redistribute it and/or modify        #
# it under the terms of the GNU General Public License as published by        #
# the Free Software Foundation, either version 3 of the License, or           #
# (at your option) any later version.                                         #
#                                                                             #
# This program is distributed in the hope that it will be useful,             #
# but WITHOUT ANY WARRANTY; without even the implied warranty of              #
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the                #
# GNU General Public License for more details.                                #
#                                                                             #
# You should have received a copy of the GNU General Public License           #
# along with this program. If not, see <https://www.gnu.org/licenses/>.       #
#                                                                             #
# This script is not associated with the official Pterodactyl Project.        #
# https://github.com/pterodactyl-installer/pterodactyl-installer              #
#                                                                             #
###############################################################################

set -e

# ------------------- Constants ------------------- #
SCRIPT_VERSION="2.0.0"
PANEL_PATH="/var/www/pterodactyl"
DEFAULT_TIMEZONE="UTC"
GITHUB_BASE_URL="https://raw.githubusercontent.com/pterodactyl-installer/pterodactyl-installer"
CONFIG_PATH="$GITHUB_BASE_URL/master/configs"

# ------------------- Utility Functions ------------------- #

# Load library functions
function load_library() {
  # Check if script is loaded, load if not or fail otherwise
  if ! declare -F lib_loaded &>/dev/null; then
    source /tmp/lib.sh || source <(curl -sSL "$GITHUB_BASE_URL/master/lib/lib.sh")
    if ! declare -F lib_loaded &>/dev/null; then
      echo "* ERROR: Could not load library functions" >&2
      exit 1
    fi
  fi
}

function print_header() {
  clear
  echo "╔═══════════════════════════════════════════════════════════════════╗"
  echo "║                                                                   ║"
  echo "║        Pterodactyl Panel Installer v$SCRIPT_VERSION                         ║"
  echo "║                                                                   ║"
  echo "╚═══════════════════════════════════════════════════════════════════╝"
  echo ""
}

function validate_input() {
  # Validate required parameters
  local required_params=("email" "user_email" "user_username" "user_firstname" "user_lastname" "user_password")
  local missing_params=()

  for param in "${required_params[@]}"; do
    if [[ -z "${!param}" ]]; then
      missing_params+=("$param")
    fi
  done

  if [[ ${#missing_params[@]} -gt 0 ]]; then
    error "The following required parameters are missing: ${missing_params[*]}"
    exit 1
  fi
}

function generate_password() {
  local length="${1:-64}"
  tr -dc 'A-Za-z0-9!#$%&()*+,-./:;<=>?@[\]^_`{|}~' </dev/urandom | head -c "$length"
}

# ------------------- Installation Functions ------------------- #

function install_dependencies() {
  output "Installing dependencies for $OS $OS_VER..."

  # Update package repositories
  update_repos

  # Install firewall if requested
  if [[ "$CONFIGURE_FIREWALL" == true ]]; then
    install_firewall 
    configure_firewall
  fi

  # OS-specific dependency installation
  case "$OS" in
    ubuntu|debian)
      install_debian_dependencies
      ;;
    rocky|almalinux)
      install_rhel_dependencies
      ;;
    *)
      error "Unsupported operating system: $OS"
      exit 1
      ;;
  esac

  # Enable required services
  enable_services

  success "Dependencies installed successfully!"
}

function install_debian_dependencies() {
  # Install prerequisites
  install_packages "software-properties-common apt-transport-https ca-certificates gnupg curl"

  # Add repositories based on OS
  if [[ "$OS" == "ubuntu" ]]; then
    add-apt-repository universe -y
    LC_ALL=C.UTF-8 add-apt-repository -y ppa:ondrej/php
  elif [[ "$OS" == "debian" ]]; then
    install_packages "dirmngr lsb-release"
    curl -fsSL https://packages.sury.org/php/apt.gpg -o /etc/apt/trusted.gpg.d/php.gpg
    echo "deb https://packages.sury.org/php/ $(lsb_release -sc) main" > /etc/apt/sources.list.d/php.list
  fi

  # Update repositories after adding new sources
  update_repos

  # Install core packages
  install_packages "php8.3 php8.3-cli php8.3-common php8.3-gd php8.3-mysql php8.3-mbstring php8.3-bcmath php8.3-xml php8.3-fpm php8.3-curl php8.3-zip
                    mariadb-common mariadb-server mariadb-client
                    nginx
                    redis-server
                    zip unzip tar
                    git cron"

  # Install Let's Encrypt if configured
  if [[ "$CONFIGURE_LETSENCRYPT" == true ]]; then
    install_packages "certbot python3-certbot-nginx"
  fi
}

function install_rhel_dependencies() {
  # Install SELinux tools
  install_packages "policycoreutils selinux-policy selinux-policy-targeted
                   setroubleshoot-server setools setools-console mcstrans"

  # Add REMI repository for PHP 8.3
  install_packages "epel-release http://rpms.remirepo.net/enterprise/remi-release-$OS_VER_MAJOR.rpm"
  dnf module enable -y php:remi-8.3

  # Install core packages
  install_packages "php php-common php-fpm php-cli php-json php-mysqlnd php-mcrypt php-gd php-mbstring php-pdo php-zip php-bcmath php-dom php-opcache php-posix
                   mariadb mariadb-server
                   nginx
                   redis
                   zip unzip tar
                   git cronie"

  # Install Let's Encrypt if configured
  if [[ "$CONFIGURE_LETSENCRYPT" == true ]]; then
    install_packages "certbot python3-certbot-nginx"
  fi

  # Configure SELinux
  configure_selinux
  
  # Configure PHP-FPM
  configure_php_fpm
}

function configure_selinux() {
  output "Configuring SELinux permissions..."
  
  setsebool -P httpd_can_network_connect 1 || true
  setsebool -P httpd_execmem 1 || true
  setsebool -P httpd_unified 1 || true
  
  success "SELinux configured!"
}

function configure_php_fpm() {
  output "Configuring PHP-FPM..."
  
  curl -sSL -o /etc/php-fpm.d/www-pterodactyl.conf "$CONFIG_PATH/www-pterodactyl.conf"
  
  systemctl enable php-fpm
  systemctl restart php-fpm
  
  success "PHP-FPM configured!"
}

function enable_services() {
  output "Enabling and starting required services..."
  
  # Enable and start Redis
  case "$OS" in
    ubuntu|debian)
      systemctl enable redis-server
      systemctl restart redis-server
      ;;
    rocky|almalinux)
      systemctl enable redis
      systemctl restart redis
      ;;
  esac
  
  # Enable and start MariaDB
  systemctl enable mariadb
  systemctl restart mariadb
  
  # Enable Nginx (will be started after configuration)
  systemctl enable nginx
  
  success "Services enabled and started!"
}

function install_composer() {
  output "Installing Composer..."
  
  curl -sS https://getcomposer.org/installer | php -- --install-dir=/usr/local/bin --filename=composer
  
  success "Composer installed successfully!"
}

function download_panel() {
  output "Downloading Pterodactyl Panel files..."
  
  mkdir -p "$PANEL_PATH"
  cd "$PANEL_PATH" || exit 1
  
  curl -sSL -o panel.tar.gz "$PANEL_DL_URL"
  tar -xzf panel.tar.gz
  chmod -R 755 storage/* bootstrap/cache/
  
  cp .env.example .env
  
  success "Pterodactyl Panel files downloaded!"
}

function install_panel_dependencies() {
  output "Installing Panel dependencies with Composer..."
  
  cd "$PANEL_PATH" || exit 1
  
  # Add composer bin to PATH for RHEL-based systems
  if [[ "$OS" == "rocky" || "$OS" == "almalinux" ]]; then
    export PATH=/usr/local/bin:$PATH
  fi
  
  COMPOSER_ALLOW_SUPERUSER=1 composer install --no-dev --optimize-autoloader
  
  success "Panel dependencies installed!"
}

function create_database() {
  output "Setting up database..."
  
  # Create database user
  mysql -u root -e "CREATE USER IF NOT EXISTS '${MYSQL_USER}'@'127.0.0.1' IDENTIFIED BY '${MYSQL_PASSWORD}';"
  
  # Create database
  mysql -u root -e "CREATE DATABASE IF NOT EXISTS ${MYSQL_DB};"
  
  # Grant privileges
  mysql -u root -e "GRANT ALL PRIVILEGES ON ${MYSQL_DB}.* TO '${MYSQL_USER}'@'127.0.0.1' WITH GRANT OPTION;"
  mysql -u root -e "FLUSH PRIVILEGES;"
  
  success "Database configured!"
}

function configure_panel() {
  output "Configuring Pterodactyl Panel..."
  
  cd "$PANEL_PATH" || exit 1
  
  # Determine app URL
  local app_url="http://$FQDN"
  if [[ "$ASSUME_SSL" == true || "$CONFIGURE_LETSENCRYPT" == true ]]; then
    app_url="https://$FQDN"
  fi
  
  # Generate application key
  php artisan key:generate --force
  
  # Configure environment
  php artisan p:environment:setup \
    --author="$email" \
    --url="$app_url" \
    --timezone="$timezone" \
    --cache="redis" \
    --session="redis" \
    --queue="redis" \
    --redis-host="localhost" \
    --redis-pass="null" \
    --redis-port="6379" \
    --settings-ui=true
    
  # Configure database
  php artisan p:environment:database \
    --host="127.0.0.1" \
    --port="3306" \
    --database="$MYSQL_DB" \
    --username="$MYSQL_USER" \
    --password="$MYSQL_PASSWORD"
    
  # Run migrations
  php artisan migrate --seed --force
  
  # Create admin user
  php artisan p:user:make \
    --email="$user_email" \
    --username="$user_username" \
    --name-first="$user_firstname" \
    --name-last="$user_lastname" \
    --password="$user_password" \
    --admin=1
    
  success "Panel configured successfully!"
}

function set_permissions() {
  output "Setting correct file permissions..."
  
  cd "$PANEL_PATH" || exit 1
  
  case "$OS" in
    debian|ubuntu)
      chown -R www-data:www-data ./*
      ;;
    rocky|almalinux)
      chown -R nginx:nginx ./*
      ;;
  esac
  
  success "Permissions set!"
}

function setup_cron() {
  output "Setting up cron job..."
  
  # Add cron job without wiping existing crontab
  (crontab -l 2>/dev/null || echo "") | grep -v "artisan schedule:run" | { 
    cat
    echo "* * * * * php $PANEL_PATH/artisan schedule:run >> /dev/null 2>&1"
  } | crontab -
  
  success "Cron job installed!"
}

function setup_queue_worker() {
  output "Setting up queue worker service..."
  
  curl -sSL -o /etc/systemd/system/pteroq.service "$CONFIG_PATH/pteroq.service"
  
  # Set correct user based on OS
  case "$OS" in
    debian|ubuntu)
      sed -i -e "s@<user>@www-data@g" /etc/systemd/system/pteroq.service
      ;;
    rocky|almalinux)
      sed -i -e "s@<user>@nginx@g" /etc/systemd/system/pteroq.service
      ;;
  esac
  
  systemctl daemon-reload
  systemctl enable pteroq.service
  systemctl restart pteroq
  
  success "Queue worker service installed!"
}

function configure_firewall() {
  output "Configuring firewall rules..."
  
  firewall_allow_ports "22 80 443"
  
  success "Firewall configured!"
}

function configure_nginx() {
  output "Configuring Nginx web server..."
  
  # Determine which config file to use
  local config_file="nginx.conf"
  if [[ "$ASSUME_SSL" == true && "$CONFIGURE_LETSENCRYPT" == false ]]; then
    config_file="nginx_ssl.conf"
  fi
  
  # Set OS-specific paths and socket
  case "$OS" in
    ubuntu|debian)
      local php_socket="/run/php/php8.3-fpm.sock"
      local config_path_avail="/etc/nginx/sites-available"
      local config_path_enabled="/etc/nginx/sites-enabled"
      ;;
    rocky|almalinux)
      local php_socket="/var/run/php-fpm/pterodactyl.sock"
      local config_path_avail="/etc/nginx/conf.d"
      local config_path_enabled="$config_path_avail"
      ;;
  esac
  
  # Remove default site if it exists
  rm -f "$config_path_enabled/default"
  
  # Download and configure Nginx site
  curl -sSL -o "$config_path_avail/pterodactyl.conf" "$CONFIG_PATH/$config_file"
  
  # Replace placeholders in config
  sed -i -e "s@<domain>@${FQDN}@g" "$config_path_avail/pterodactyl.conf"
  sed -i -e "s@<php_socket>@${php_socket}@g" "$config_path_avail/pterodactyl.conf"
  
  # Create symlink if needed (Debian/Ubuntu)
  if [[ "$OS" == "ubuntu" || "$OS" == "debian" ]]; then
    ln -sf "$config_path_avail/pterodactyl.conf" "$config_path_enabled/pterodactyl.conf"
  fi
  
  # Restart Nginx if not using SSL
  if [[ "$ASSUME_SSL" == false && "$CONFIGURE_LETSENCRYPT" == false ]]; then
    systemctl restart nginx
  fi
  
  success "Nginx configured successfully!"
}

function setup_letsencrypt() {
  output "Setting up Let's Encrypt SSL certificate for $FQDN..."
  
  # Attempt to obtain certificate
  if ! certbot --nginx --redirect --non-interactive --agree-tos --no-eff-email --email "$email" -d "$FQDN"; then
    warning "Failed to obtain Let's Encrypt certificate!"
    
    # Ask to continue with SSL assumption or not
    read -rp "* Still assume SSL? (y/N): " CONFIGURE_SSL
    
    if [[ "$CONFIGURE_SSL" =~ [Yy] ]]; then
      ASSUME_SSL=true
      CONFIGURE_LETSENCRYPT=false
      configure_nginx
    else
      ASSUME_SSL=false
      CONFIGURE_LETSENCRYPT=false
      configure_nginx
    fi
  else
    success "Let's Encrypt certificate obtained and configured successfully!"
    systemctl restart nginx
  fi
}

function display_completion_message() {
  local panel_url
  if [[ "$ASSUME_SSL" == true || "$CONFIGURE_LETSENCRYPT" == true ]]; then
    panel_url="https://$FQDN"
  else
    panel_url="http://$FQDN"
  fi

  echo ""
  echo "╔═══════════════════════════════════════════════════════════════════╗"
  echo "║                                                                   ║"
  echo "║                      INSTALLATION COMPLETE                        ║"
  echo "║                                                                   ║"
  echo "╚═══════════════════════════════════════════════════════════════════╝"
  echo ""
  echo "* Panel URL: $panel_url"
  echo "* Admin Username: $user_username"
  echo "* MySQL Database: $MYSQL_DB"
  echo "* MySQL User: $MYSQL_USER"
  echo "* MySQL Password: $MYSQL_PASSWORD"
  echo ""
  echo "* Installation Log: /var/log/pterodactyl-installer.log"
  echo ""
  echo "Thank you for using this installer!"
  echo "If you encounter any issues, please visit: https://github.com/pterodactyl-installer/pterodactyl-installer"
  echo ""
}

# ------------------- Main Function ------------------- #

function main() {
  print_header
  
  # Load library functions
  load_library
  
  # Set default values for optional parameters
  : "${FQDN:=panel.example.com}"
  : "${MYSQL_DB:=panel}"
  : "${MYSQL_USER:=pterodactyl}"
  : "${MYSQL_PASSWORD:=$(generate_password 32)}"
  : "${timezone:=$DEFAULT_TIMEZONE}"
  : "${ASSUME_SSL:=false}"
  : "${CONFIGURE_LETSENCRYPT:=false}"
  : "${CONFIGURE_FIREWALL:=true}"
  
  # Validate required input parameters
  validate_input
  
  # Log installation
  output "Beginning Pterodactyl Panel installation on $OS $OS_VER"
  output "Domain: $FQDN"
  
  # Execute installation steps
  install_dependencies
  install_composer
  download_panel
  install_panel_dependencies
  create_database
  configure_panel
  set_permissions
  setup_cron
  setup_queue_worker
  # configure_nginx
  
  # Setup Let's Encrypt if requested
  # if [[ "$CONFIGURE_LETSENCRYPT" == true ]]; then
  #  setup_letsencrypt
  # fi
  
  display_completion_message
}

# Start the installation
main "$@"