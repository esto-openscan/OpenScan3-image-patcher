#!/bin/bash
# OpenScan3 First Boot Setup Script
# This script automatically installs OpenScan3 on first boot

# Check if script has already run
LOCK_FILE="/var/lock/openscan_setup_complete"
if [ -f "$LOCK_FILE" ]; then
    echo "Setup has already been completed. Exiting."
    exit 0
fi

# Log file for debugging
LOG_FILE="/var/log/openscan_setup.log"

# Function to log messages
log_message() {
    echo "$(date): $1" | tee -a $LOG_FILE
}

# Create log file
sudo touch $LOG_FILE
sudo chmod 666 $LOG_FILE
log_message "Starting OpenScan3 first boot setup"

# Check if pi user exists and set password
if id -u pi &>/dev/null; then
    log_message "Pi user exists, setting password..."
    echo "pi:raspberry" | sudo chpasswd
    log_message "Password for pi user set to 'raspberry'"
else
    # Create pi user if it doesn't exist
    log_message "Creating pi user..."
    sudo useradd -m -s /bin/bash -G sudo pi
    echo "pi:raspberry" | sudo chpasswd
    # Add pi to required groups
    sudo usermod -a -G adm,dialout,cdrom,sudo,audio,video,plugdev,games,users,input,netdev,gpio,i2c,spi pi
    log_message "User pi created with password 'raspberry'"
fi

# Wait on systemd-timesyncd to synchronize system time
if systemctl is-active --quiet systemd-timesyncd; then
    log_message "Waiting on synchronisation of system time..."
    while true; do
        if timedatectl show --property=NTPSynchronized --value | grep -q 'yes'; then
            log_message "Time synchronised."
            break
        fi
        sleep 1
    done
else
    echo "Error: systemd-timesyncd is not active."
    exit 1
fi

# Configure network for discovery
log_message "Configuring network for discovery..."
# Enable avahi-daemon for .local discovery
sudo apt-get install -y avahi-daemon 2>&1 | tee -a "$LOG_FILE"
sudo systemctl enable avahi-daemon
sudo systemctl start avahi-daemon

# Set hostname to openscan
sudo hostnamectl set-hostname openscan3-alpha
echo "127.0.1.1 openscan3-alpha" | sudo tee -a /etc/hosts

# Update system packages
log_message "Updating system packages..."
sudo apt-get update && sudo apt-get upgrade -y 2>&1 | tee -a "$LOG_FILE"

# Install dependencies
log_message "Installing dependencies..."
sudo apt-get install git libgphoto2-dev libcap-dev python3-dev python3-libcamera python3-kms++ python3-opencv -y 2>&1 | tee -a "$LOG_FILE"

# Install libcamera-drivers
log_message "Installing libcamera-drivers..."
cd /tmp
wget -O install_pivariety_pkgs.sh https://github.com/ArduCAM/Arducam-Pivariety-V4L2-Driver/releases/download/install_script/install_pivariety_pkgs.sh
chmod +x install_pivariety_pkgs.sh
sudo ./install_pivariety_pkgs.sh -p libcamera_dev
sudo ./install_pivariety_pkgs.sh -p libcamera_apps

# Clone the OpenScan3 repository
log_message "Cloning OpenScan3 repository..."
cd /home/pi
# Ensure we're running as pi user for git operations
if [ "$(whoami)" != "pi" ]; then
    sudo -u pi git clone https://github.com/OpenScan-org/OpenScan3.git 2>&1 | tee -a "$LOG_FILE"
    cd OpenScan3
    sudo -u pi git checkout develop
else
    git clone https://github.com/OpenScan-org/OpenScan3.git 2>&1 | tee -a "$LOG_FILE"
    cd OpenScan3
    git checkout develop
fi

# Fix ownership of the repository
sudo chown -R pi:pi /home/pi/OpenScan3

# Setup virtual environment
log_message "Setting up virtual environment..."
if [ "$(whoami)" != "pi" ]; then
    sudo -u pi python3 -m venv --system-site-packages .venv
    # Source the virtual environment and install dependencies
    sudo -u pi bash -c "source .venv/bin/activate && pip install -r requirements.txt" 2>&1 | tee -a "$LOG_FILE"
else
    python3 -m venv --system-site-packages .venv
    source .venv/bin/activate
    pip install -r requirements.txt 2>&1 | tee -a "$LOG_FILE"
fi

# Create autostart service
log_message "Creating autostart service..."
cat > /tmp/openscan3.service << EOF
[Unit]
Description=OpenScan3 Service
After=network.target

[Service]
User=pi
WorkingDirectory=/home/pi/OpenScan3
Environment="PYTHONPATH=/home/pi/OpenScan3"
ExecStart=/home/pi/OpenScan3/.venv/bin/python /home/pi/OpenScan3/app/main.py
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

sudo mv /tmp/openscan3.service /etc/systemd/system/
sudo systemctl enable openscan3.service

# Disable the first boot service to prevent running on subsequent boots
log_message "Disabling first boot service..."
sudo systemctl disable openscan-firstboot.service
sudo rm -f /etc/systemd/system/multi-user.target.wants/openscan-firstboot.service

# Create lock file to prevent re-running
log_message "Creating lock file to prevent re-running..."
sudo touch "$LOCK_FILE"

# Start the service
log_message "Starting OpenScan3 service..."
sudo systemctl start openscan3.service

log_message "OpenScan3 setup completed successfully!"

# Reboot to ensure everything is properly initialized
log_message "Rebooting system..."
sudo reboot
