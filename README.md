# OpenScan3 Raspberry Pi Image Patcher

This repository contains scripts to patch a standard Raspberry Pi OS image, automating the setup and installation of the [OpenScan3](https://github.com/OpenScan-org/OpenScan3) software. The goal is to create a ready-to-flash SD card image that configures itself on the first boot.

## Features

*   Automatically installs OpenScan3 and its dependencies.
*   Sets up required system services (Avahi for network discovery, OpenScan3 autostart).
*   Configures the hostname to `openscan3-alpha`.
*   Optionally enables SSH for headless access.
*   Optionally compresses the final image using XZ.

## Prerequisites

To use the `patch_image.sh` script, you need:

*   A Linux environment.
*   Required tools: `bash`, `xz-utils`, `losetup`, `mount`, `parted`. You can usually install these via your package manager (e.g., `sudo apt update && sudo apt install xz-utils coreutils mount parted`).
*   A Raspberry Pi OS image file (e.g., downloaded from the [official Raspberry Pi website](https://www.raspberrypi.com/software/operating-systems/)). Lite version is recommended.

## Files

*   `patch_image.sh`: The main script that mounts the Raspberry Pi OS image, copies necessary files, and sets up the first boot service.
*   `first_boot_setup.sh`: The script that runs automatically *inside* the Raspberry Pi on its first boot after being flashed with the patched image. It handles package updates, dependency installation, cloning the OpenScan3 repository, setting up the virtual environment, and enabling the OpenScan3 service.

## Usage

1.  **Download** a Raspberry Pi OS image (e.g., `YYYY-MM-DD-raspios-bullseye-armhf-lite.img.xz`).
2.  **Place** the downloaded image file, `patch_image.sh`, and `first_boot_setup.sh` in the same directory.
3.  **Make `patch_image.sh` executable**: `chmod +x patch_image.sh`
4.  **Run the script**:

    ```bash
    sudo ./patch_image.sh <path_to_your_image.img.xz> [OPTIONS]
    ```

    *   `<path_to_your_image.img.xz>`: Replace with the actual path to your downloaded Raspberry Pi OS image file (can be `.img` or `.img.xz`).
    *   **Options:**
        *   `--compress`: Compresses the final patched image using XZ (reduces file size but takes longer). The output file will be named `OpenScan_...img.xz`.
        *   `--enable-ssh`: Creates an empty `ssh` file in the boot partition, enabling the SSH server on the first boot.

    **Example:**

    ```bash
    # Patch the image, enable SSH, and compress the output
    sudo ./patch_image.sh 2024-11-19-raspios-bookworm-armhf-lite.img.xz --enable-ssh --compress
    ```

5.  **Flash the output image** (e.g., `OpenScan_2024-11-19-raspios-bookworm-armhf-lite.img` or `OpenScan_2024-11-19-raspios-bookworm-armhf-lite.img`) to an SD card using tools like Raspberry Pi Imager or `dd`.

## First Boot Process

When you boot your Raspberry Pi with the flashed SD card for the first time:

1.  The Raspberry Pi will boot normally.
2.  The `first_boot_setup.sh` script will run automatically in the background. This can take several minutes as it updates packages, installs dependencies, and clones the OpenScan3 repository.
3.  During this process, the default user `pi` password will be set to `raspberry`.
4.  The hostname will be set to `openscan3-alpha`.
5.  Once the setup is complete, the script will automatically disable itself and start the `openscan3.service`.
6.  The Raspberry Pi will **reboot automatically** one final time.

After the final reboot, OpenScan3 should be running.

## Accessing OpenScan3

*   **Hostname:** `openscan3-alpha`
*   **Web Interface:** Currently there is only API documentation available. Open a web browser on a device on the same network and navigate to `http://openscan3-alpha:8000/docs` or to `http://openscan3-alpha:8000/latest/docs` for a cleaner overview of API-Endpoints
*   **SSH (if enabled):** `ssh pi@openscan3-alpha` (Password: `raspberry`)

## First Steps After Boot

Once the Raspberry Pi has completed its final reboot and OpenScan3 is running, you need to load a device configuration specific to your hardware setup. By default, no specific configuration is loaded.

There are two ways to load a configuration:

**Method 1: Using the API (Recommended)**

1.  Navigate to the API documentation (usually accessible via a link like `/docs` or `/redoc` on the web interface, so `http://openscan3-alpha:8000/latest/docs`).
3.  Find the **Device** Section and the **PUT** endpoint `/latest/device/configurations/current`.
4.  Use the "Try it out" feature.
5.  In the **Request body**, enter the name of the configuration file you want to load. For example, for an OpenScan Mini with a Greenshield, use:
    ```json
    {
      "config_file": "default_mini_greenshield.json"
    }
    ```
    *(You can find available default configuration files in the `/home/pi/OpenScan3/app/config/hardware_configurations` directory on the Raspberry Pi)*
6.  Execute the request. If successful, you should receive a `200 OK` response, and the hardware corresponding to the configuration should initialize.

**Method 2: Manual File Copy**

1.  Connect to your Raspberry Pi via SSH: `ssh pi@openscan3-alpha` (Password: `raspberry`).
2.  Navigate to the OpenScan3 directory: `cd /home/pi/OpenScan3/`
3.  List the available default configurations: `ls settings/`
4.  Choose the configuration file that matches your hardware (e.g., `default_mini_greenshield.json`).
5.  Copy the chosen configuration file to `device_config.json` in the main OpenScan3 directory:
    ```bash
    cp settings/default_mini_greenshield.json device_config.json
    ```
6.  Restart the OpenScan3 service for the changes to take effect:
    ```bash
    sudo systemctl restart openscan3.service
    ```
    Alternatively, you can simply reboot the Raspberry Pi: `sudo reboot`

After loading the correct configuration, your OpenScan hardware should be ready to use via the web interface.

## Notes

*   The first boot setup requires an active internet connection on the Raspberry Pi to download packages and clone the repository.
*   It will take some time until the Raspberry Pi is reachable and even more time until everythin is installed, grab a coffee.
*   The setup logs can be found in `/var/log/openscan_setup.log` on the Raspberry Pi after the first boot completes. You can monitor the installation progress if you run `tail -f /var/log/openscan_setup.log`
*   The OpenScan3 code will be located in `/home/pi/OpenScan3` and running from the `develop` branch.
*   OpenScan3 runs as systemd service `sudo systemctl status openscan3.service`
*   In case something breaks you can either restart the Raspberry Pi or the systemd service.
