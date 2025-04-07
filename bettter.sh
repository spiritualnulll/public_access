#!/bin/bash

# Color definitions
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Function to display verbose messages
function verbose() {
    local type=$1
    local message=$2
    local timestamp=$(date +"%H:%M:%S")
    
    case $type in
        "INFO")
            echo -e "[${BLUE}INFO ${timestamp}${NC}] $message"
            ;;
        "WARN")
            echo -e "[${YELLOW}WARN ${timestamp}${NC}] $message"
            ;;
        "ERROR")
            echo -e "[${RED}ERROR ${timestamp}${NC}] $message"
            ;;
        "SUCCESS")
            echo -e "[${GREEN}SUCCESS ${timestamp}${NC}] $message"
            ;;
        "PROMPT")
            echo -e "[${PURPLE}PROMPT ${timestamp}${NC}] $message"
            ;;
        "EXEC")
            echo -e "[${CYAN}EXEC ${timestamp}${NC}] $message"
            ;;
    esac
}

# Function to confirm with user
function confirm_continue() {
    local message=$1
    local default=${2:-y}
    
    while true; do
        verbose "PROMPT" "$message [y/n] (default: $default)"
        read -r response
        response=${response:-$default}
        case $response in
            [Yy]* ) return 0;;
            [Nn]* ) return 1;;
            * ) verbose "WARN" "Please answer yes (y) or no (n).";;
        esac
    done
}

# Function to handle errors
function error_handler() {
    local exit_code=$?
    local command=$BASH_COMMAND
    
    if [ $exit_code -ne 0 ]; then
        verbose "ERROR" "Command failed with exit code $exit_code: $command"
        
        if confirm_continue "Would you like to continue anyway?"; then
            verbose "WARN" "Continuing despite error..."
        else
            verbose "ERROR" "Installation aborted by user."
            exit $exit_code
        fi
    fi
}

# Enable error handling
trap error_handler ERR

# Check if running as root
if [ "$(id -u)" != "0" ]; then
   verbose "ERROR" "This script must be run as root"
   exit 1
fi

# Start installation
clear
verbose "INFO" "Starting Pterodactyl Panel installation script"
verbose "INFO" "This script will install Pterodactyl Panel on your system"

# Gather basic information
verbose "PROMPT" "Enter the domain name for your Pterodactyl Panel (e.g., panel.example.com):"
read -r FQDN

verbose "PROMPT" "Enter your email address (for SSL certificate):"
read -r EMAIL

# Ask for database details
verbose "PROMPT" "Enter the database password for Pterodactyl (leave blank to generate one):"
read -r -s DB_PASSWORD
echo ""

if [ -z "$DB_PASSWORD" ]; then
    DB_PASSWORD=$(openssl rand -base64 16)
    verbose "INFO" "Generated database password: $DB_PASSWORD"
    verbose "WARN" "Please save this password somewhere safe!"
fi

# Ask for confirmation before proceeding
if ! confirm_continue "Ready to begin installation?"; then
    verbose "INFO" "Installation cancelled by user."
    exit 0
fi

# Section 1: Install initial dependencies
verbose "INFO" "Starting installation of initial dependencies"
verbose "EXEC" "Installing software-properties-common and related packages"
apt -y install software-properties-common curl apt-transport-https ca-certificates gnupg
if [ $? -eq 0 ]; then
    verbose "SUCCESS" "Initial dependencies installed successfully"
else
    verbose "ERROR" "Failed to install initial dependencies"
    if ! confirm_continue "Continue anyway?"; then
        exit 1
    fi
fi

# Section 2: Add PHP repository
verbose "INFO" "Adding PHP repository"
verbose "EXEC" "Adding PPA:ondrej/php repository"
LC_ALL=C.UTF-8 add-apt-repository -y ppa:ondrej/php
if [ $? -eq 0 ]; then
    verbose "SUCCESS" "PHP repository added successfully"
else
    verbose "ERROR" "Failed to add PHP repository"
    if ! confirm_continue "Continue anyway?"; then
        exit 1
    fi
fi

# Section 3: Add Redis repository
verbose "INFO" "Adding Redis repository"
verbose "EXEC" "Downloading Redis GPG key"
curl -fsSL https://packages.redis.io/gpg | sudo gpg --dearmor -o /usr/share/keyrings/redis-archive-keyring.gpg
verbose "EXEC" "Adding Redis repository to sources list"
echo "deb [signed-by=/usr/share/keyrings/redis-archive-keyring.gpg] https://packages.redis.io/deb $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/redis.list
if [ $? -eq 0 ]; then
    verbose "SUCCESS" "Redis repository added successfully"
else
    verbose "ERROR" "Failed to add Redis repository"
    if ! confirm_continue "Continue anyway?"; then
        exit 1
    fi
fi

# Section 4: Add MariaDB repository
verbose "INFO" "Adding MariaDB repository"
verbose "EXEC" "Running MariaDB repository setup script"
curl -LsS https://r.mariadb.com/downloads/mariadb_repo_setup | sudo bash
if [ $? -eq 0 ]; then
    verbose "SUCCESS" "MariaDB repository added successfully"
else
    verbose "ERROR" "Failed to add MariaDB repository"
    if ! confirm_continue "Continue anyway?"; then
        exit 1
    fi
fi

# Section 5: Update repositories
verbose "INFO" "Updating package lists"
verbose "EXEC" "Running apt update"
apt update
if [ $? -eq 0 ]; then
    verbose "SUCCESS" "Package lists updated successfully"
else
    verbose "ERROR" "Failed to update package lists"
    if ! confirm_continue "Continue anyway?"; then
        exit 1
    fi
fi

# Section 6: Install required packages
verbose "INFO" "Installing required packages"
verbose "EXEC" "Installing PHP 8.3 and related packages"
apt -y install php8.3 php8.3-{common,cli,gd,mysql,mbstring,bcmath,xml,fpm,curl,zip} mariadb-server nginx tar unzip git redis-server
if [ $? -eq 0 ]; then
    verbose "SUCCESS" "Required packages installed successfully"
else
    verbose "ERROR" "Failed to install required packages"
    if ! confirm_continue "Continue anyway?"; then
        exit 1
    fi
fi

# Section 7: Install Composer
verbose "INFO" "Installing Composer"
verbose "EXEC" "Downloading and installing Composer"
curl -sS https://getcomposer.org/installer | sudo php -- --install-dir=/usr/local/bin --filename=composer
if [ $? -eq 0 ]; then
    verbose "SUCCESS" "Composer installed successfully"
else
    verbose "ERROR" "Failed to install Composer"
    if ! confirm_continue "Continue anyway?"; then
        exit 1
    fi
fi

# Section 8: Create directory structure
verbose "INFO" "Creating directory structure"
verbose "EXEC" "Creating /var/www/pterodactyl directory"
mkdir -p /var/www/pterodactyl
cd /var/www/pterodactyl
if [ $? -eq 0 ]; then
    verbose "SUCCESS" "Directory structure created successfully"
else
    verbose "ERROR" "Failed to create directory structure"
    if ! confirm_continue "Continue anyway?"; then
        exit 1
    fi
fi

# Section 9: Download and extract Pterodactyl Panel
verbose "INFO" "Downloading Pterodactyl Panel"
verbose "EXEC" "Fetching latest panel release"
curl -Lo panel.tar.gz https://github.com/pterodactyl/panel/releases/latest/download/panel.tar.gz
verbose "EXEC" "Extracting panel archive"
tar -xzvf panel.tar.gz
verbose "EXEC" "Setting proper permissions"
chmod -R 755 storage/* bootstrap/cache/
if [ $? -eq 0 ]; then
    verbose "SUCCESS" "Pterodactyl Panel downloaded and extracted successfully"
else
    verbose "ERROR" "Failed to download or extract Pterodactyl Panel"
    if ! confirm_continue "Continue anyway?"; then
        exit 1
    fi
fi

# Section 10: Configure MariaDB
verbose "INFO" "Configuring MariaDB"
verbose "EXEC" "Starting MariaDB service"
systemctl start mariadb
systemctl enable mariadb

verbose "INFO" "Creating database and user"
# Create database and user without asking for password input
mysql -e "CREATE USER 'pterodactyl'@'127.0.0.1' IDENTIFIED BY '${DB_PASSWORD}';"
mysql -e "CREATE DATABASE panel;"
mysql -e "GRANT ALL PRIVILEGES ON panel.* TO 'pterodactyl'@'127.0.0.1' WITH GRANT OPTION;"
mysql -e "FLUSH PRIVILEGES;"

if [ $? -eq 0 ]; then
    verbose "SUCCESS" "Database configured successfully"
else
    verbose "ERROR" "Failed to configure database"
    if ! confirm_continue "Continue anyway?"; then
        exit 1
    fi
fi

# Confirm database configuration
if confirm_continue "Database configured with username 'pterodactyl' and password '${DB_PASSWORD}'. Is this correct?"; then
    verbose "INFO" "Database configuration confirmed"
else
    verbose "PROMPT" "Enter new database username:"
    read -r DB_USER
    verbose "PROMPT" "Enter new database password:"
    read -r -s DB_PASSWORD
    echo ""
    
    # Update database configuration
    mysql -e "DROP USER 'pterodactyl'@'127.0.0.1';"
    mysql -e "CREATE USER '${DB_USER}'@'127.0.0.1' IDENTIFIED BY '${DB_PASSWORD}';"
    mysql -e "GRANT ALL PRIVILEGES ON panel.* TO '${DB_USER}'@'127.0.0.1' WITH GRANT OPTION;"
    mysql -e "FLUSH PRIVILEGES;"
    
    verbose "SUCCESS" "Database reconfigured successfully"
fi

# Section 11: Configure Pterodactyl Panel
verbose "INFO" "Configuring Pterodactyl Panel"
verbose "EXEC" "Creating .env file"
cp .env.example .env
if [ $? -eq 0 ]; then
    verbose "SUCCESS" "Environment file created successfully"
else
    verbose "ERROR" "Failed to create environment file"
    if ! confirm_continue "Continue anyway?"; then
        exit 1
    fi
fi

# Section 12: Install Panel dependencies
verbose "INFO" "Installing Panel dependencies with Composer"
verbose "EXEC" "Running composer install"
COMPOSER_ALLOW_SUPERUSER=1 composer install --no-dev --optimize-autoloader
if [ $? -eq 0 ]; then
    verbose "SUCCESS" "Panel dependencies installed successfully"
else
    verbose "ERROR" "Failed to install Panel dependencies"
    if ! confirm_continue "Continue anyway?"; then
        exit 1
    fi
fi

# Section 13: Generate application key
verbose "INFO" "Generating application key"
verbose "EXEC" "Running php artisan key:generate"
php artisan key:generate --force
if [ $? -eq 0 ]; then
    verbose "SUCCESS" "Application key generated successfully"
else
    verbose "ERROR" "Failed to generate application key"
    if ! confirm_continue "Continue anyway?"; then
        exit 1
    fi
fi

# Section 14: Configure environment
verbose "INFO" "Configuring environment"
verbose "EXEC" "Running environment setup"
php artisan p:environment:setup
if [ $? -eq 0 ]; then
    verbose "SUCCESS" "Environment configured successfully"
else
    verbose "ERROR" "Failed to configure environment"
    if ! confirm_continue "Continue anyway?"; then
        exit 1
    fi
fi

# Section 15: Configure database environment
verbose "INFO" "Configuring database environment"
verbose "EXEC" "Running database environment setup"
php artisan p:environment:database
if [ $? -eq 0 ]; then
    verbose "SUCCESS" "Database environment configured successfully"
else
    verbose "ERROR" "Failed to configure database environment"
    if ! confirm_continue "Continue anyway?"; then
        exit 1
    fi
fi

# Section 16: Run migrations
verbose "INFO" "Running database migrations"
verbose "EXEC" "Running php artisan migrate --seed"
php artisan migrate --seed --force
if [ $? -eq 0 ]; then
    verbose "SUCCESS" "Database migrations completed successfully"
else
    verbose "ERROR" "Failed to run database migrations"
    if ! confirm_continue "Continue anyway?"; then
        exit 1
    fi
fi

# Section 17: Create first admin user
verbose "INFO" "Creating first administrative user"
verbose "EXEC" "Running user creation command"
php artisan p:user:make
if [ $? -eq 0 ]; then
    verbose "SUCCESS" "Administrative user created successfully"
else
    verbose "ERROR" "Failed to create administrative user"
    if ! confirm_continue "Continue anyway?"; then
        exit 1
    fi
fi

# Section 18: Set proper permissions
verbose "INFO" "Setting proper file permissions"
verbose "EXEC" "Setting www-data as owner"
chown -R www-data:www-data /var/www/pterodactyl/*
if [ $? -eq 0 ]; then
    verbose "SUCCESS" "File permissions set successfully"
else
    verbose "ERROR" "Failed to set file permissions"
    if ! confirm_continue "Continue anyway?"; then
        exit 1
    fi
fi

# Section 19: Configure cron job
verbose "INFO" "Configuring cron job"
verbose "EXEC" "Adding cron entry"
echo "* * * * * php /var/www/pterodactyl/artisan schedule:run >> /dev/null 2>&1" | crontab -u www-data -
if [ $? -eq 0 ]; then
    verbose "SUCCESS" "Cron job configured successfully"
else
    verbose "ERROR" "Failed to configure cron job"
    if ! confirm_continue "Continue anyway?"; then
        exit 1
    fi
fi

# Section 20: Create queue worker service
verbose "INFO" "Creating queue worker service"
verbose "EXEC" "Creating systemd service file"
cat > /etc/systemd/system/pteroq.service << 'EOL'
# Pterodactyl Queue Worker File
# ----------------------------------
[Unit]
Description=Pterodactyl Queue Worker
After=redis-server.service

[Service]
User=www-data
Group=www-data
Restart=always
ExecStart=/usr/bin/php /var/www/pterodactyl/artisan queue:work --queue=high,standard,low --sleep=3 --tries=3
StartLimitInterval=180
StartLimitBurst=30
RestartSec=5s

[Install]
WantedBy=multi-user.target
EOL

if [ $? -eq 0 ]; then
    verbose "SUCCESS" "Queue worker service created successfully"
else
    verbose "ERROR" "Failed to create queue worker service"
    if ! confirm_continue "Continue anyway?"; then
        exit 1
    fi
fi

# Section 21: Configure and enable services
verbose "INFO" "Enabling services"
verbose "EXEC" "Enabling and starting Redis service"
systemctl enable --now redis-server
verbose "EXEC" "Enabling and starting queue worker service"
systemctl enable --now pteroq.service
if [ $? -eq 0 ]; then
    verbose "SUCCESS" "Services enabled and started successfully"
else
    verbose "ERROR" "Failed to enable or start services"
    if ! confirm_continue "Continue anyway?"; then
        exit 1
    fi
fi


# Section 24: Finalize installation
verbose "SUCCESS" "Pterodactyl Panel has been successfully installed!"
verbose "INFO" "Panel URL: https://${FQDN}"
verbose "INFO" "Database Information:"
verbose "INFO" "  - Database: panel"
verbose "INFO" "  - Username: ${DB_USER:-pterodactyl}"
verbose "INFO" "  - Password: ${DB_PASSWORD}"
verbose "WARN" "Make sure to keep your database credentials safe!"
verbose "INFO" "Remember to set up the Wings daemon on your server nodes!"

verbose "INFO" "Would you like a summary of the installation for your records?"
if confirm_continue "Generate installation summary?"; then
    summary_file="/root/pterodactyl_installation_summary.txt"
    echo "Pterodactyl Panel Installation Summary" > $summary_file
    echo "Date: $(date)" >> $summary_file
    echo "Panel URL: https://${FQDN}" >> $summary_file
    echo "Database Information:" >> $summary_file
    echo "  - Database: panel" >> $summary_file
    echo "  - Username: ${DB_USER:-pterodactyl}" >> $summary_file
    echo "  - Password: ${DB_PASSWORD}" >> $summary_file
    echo "" >> $summary_file
    echo "Installation Path: /var/www/pterodactyl" >> $summary_file
    echo "Service Name: pteroq.service" >> $summary_file
    echo "Nginx Config: /etc/nginx/sites-available/pterodactyl.conf" >> $summary_file
    
    verbose "SUCCESS" "Installation summary saved to ${summary_file}"
fi

verbose "INFO" "Thank you for using the Pterodactyl Panel installation script!"