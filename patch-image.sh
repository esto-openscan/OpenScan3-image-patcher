#!/bin/bash
# patch_image.sh - Script to patch a Raspberry Pi OS image with OpenScan3 first boot setup
# Usage: ./patch_image.sh <image_file.img[.xz]> [--compress] [--enable-ssh]

COMPRESS=false
ENABLE_SSH=false

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --compress)
            COMPRESS=true
            shift
            ;;
        --enable-ssh)
            ENABLE_SSH=true
            shift
            ;;
        *)
            ORIGINAL_IMAGE="$1"
            shift
            ;;
    esac
done

# Check if image file is provided
if [ -z "$ORIGINAL_IMAGE" ]; then
    echo "Error: Missing image file argument"
    echo "Usage: ./patch_image.sh <image_file.img[.xz]> [--compress] [--enable-ssh]"
    exit 1
fi

IMAGE_FILE="${ORIGINAL_IMAGE%.xz}"
BASE_FILENAME=$(basename "$IMAGE_FILE")
OUTPUT_IMAGE="OpenScan_${BASE_FILENAME}"

# Check if image file exists
if [ ! -f "$ORIGINAL_IMAGE" ]; then
    echo "Error: Image file '$ORIGINAL_IMAGE' not found"
    exit 1
fi

# Check if first_boot_setup.sh exists
if [ ! -f "first_boot_setup.sh" ]; then
    echo "Error: first_boot_setup.sh not found in current directory"
    exit 1
fi

echo "Starting image patching process for $ORIGINAL_IMAGE..."

# Decompress the image if it's compressed
if [[ "$ORIGINAL_IMAGE" == *.xz ]]; then
    echo "Decompressing image file (this may take a while)..."
    xz -dk "$ORIGINAL_IMAGE"
    if [ $? -ne 0 ]; then
        echo "Error: Failed to decompress image file"
        exit 1
    fi
    echo "Image decompressed to $IMAGE_FILE"
fi

# Create mount points
echo "Creating mount points..."
mkdir -p mnt/boot mnt/rootfs

# Find the next available loop device
LOOP_DEV=$(losetup -f)
echo "Using loop device: $LOOP_DEV"

# Mount the image
echo "Mounting image file..."
losetup -P "$LOOP_DEV" "$IMAGE_FILE"

if [ $? -ne 0 ]; then
    echo "Error: Failed to mount image file"
    rm -rf mnt
    exit 1
fi

# Wait a moment for the partitions to be recognized
echo "Waiting for partitions to be recognized..."
sleep 2

# Check if partitions exist
if [ ! -e "${LOOP_DEV}p1" ] || [ ! -e "${LOOP_DEV}p2" ]; then
    echo "Error: Partitions not found. This might not be a valid Raspberry Pi OS image."
    losetup -d "$LOOP_DEV"
    rm -rf mnt
    exit 1
fi

# Mount partitions
echo "Mounting partitions..."
mount "${LOOP_DEV}p1" mnt/boot
mount "${LOOP_DEV}p2" mnt/rootfs

# Enable SSH if requested
if [ "$ENABLE_SSH" = true ]; then
    echo "Enabling SSH service..."
    touch mnt/boot/ssh
    echo "SSH has been enabled for first boot"
fi

# Create directories in the image
echo "Creating directories in the image..."
mkdir -p mnt/rootfs/home/pi/scripts

# Copy first boot setup script
echo "Copying first boot setup script..."
cp first_boot_setup.sh mnt/rootfs/home/pi/scripts/
chmod +x mnt/rootfs/home/pi/scripts/first_boot_setup.sh

# Create systemd service file
echo "Creating systemd service file..."
cat > openscan-firstboot.service << EOF
[Unit]
Description=OpenScan First Boot Setup
After=network-online.target
Wants=network-online.target
ConditionPathExists=!/var/lock/openscan_setup_complete

[Service]
Type=oneshot
User=root
ExecStart=/home/pi/scripts/first_boot_setup.sh
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF


# Copy and enable the service
echo "Installing and enabling the service..."
mkdir -p mnt/rootfs/etc/systemd/system/multi-user.target.wants/
cp openscan-firstboot.service mnt/rootfs/etc/systemd/system/
ln -sf /etc/systemd/system/openscan-firstboot.service mnt/rootfs/etc/systemd/system/multi-user.target.wants/openscan-firstboot.service

# Clean up temporary files
rm -f openscan-firstboot.service

# Sync to ensure all writes are complete
echo "Syncing file system..."
sync

# Unmount everything
echo "Unmounting partitions..."
umount mnt/boot
umount mnt/rootfs

# Detach loop device
echo "Detaching loop device..."
losetup -d "$LOOP_DEV"

# Remove mount points
echo "Removing mount points..."
rm -rf mnt

# Copy the patched image with the OpenScan prefix
echo "Creating OpenScan image..."
cp "$IMAGE_FILE" "$OUTPUT_IMAGE"

# Remove the original decompressed image if it was originally compressed
if [[ "$ORIGINAL_IMAGE" == *.xz ]]; then
    echo "Removing temporary decompressed image..."
    rm -f "$IMAGE_FILE"
fi

# Compress the image if requested
FINAL_IMAGE="$OUTPUT_IMAGE"
if [ "$COMPRESS" = true ]; then
    echo "Compressing patched image (this may take a while)..."
    xz -f "$OUTPUT_IMAGE"
    FINAL_IMAGE="${OUTPUT_IMAGE}.xz"
    echo "Image compressed to $FINAL_IMAGE"
fi

echo "Image patching completed successfully!"
echo "Your patched image is ready: $FINAL_IMAGE"
if [ "$ENABLE_SSH" = true ]; then
    echo "SSH has been enabled for headless setup"
fi
echo "You can now write this image to an SD card and boot your Raspberry Pi"
echo "The OpenScan3 setup will run automatically on first boot"
