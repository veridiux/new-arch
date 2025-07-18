#!/bin/bash
set -e
source ./config.sh

### Detect Boot Mode
if [ -d /sys/firmware/efi ]; then
  BOOT_MODE="UEFI"
else
  BOOT_MODE="BIOS"
fi
echo "Detected boot mode: $BOOT_MODE"

### Ask for disk
lsblk
read -rp "Enter target disk (e.g. /dev/sda): " DISK

### Ask for AUTOMATIC or MANUAL
read -rp "Partition automatically or manually? [a/m]: " MODE
if [[ "$MODE" != "a" ]]; then
  echo "Manual mode not implemented yet. Exiting."
  exit 1
fi

### Ask if swap should be created
read -rp "Use swap partition? [y/N]: " use_swap
if [[ "$use_swap" =~ ^[Yy]$ ]]; then
  USE_SWAP=true
  read -rp "Enter swap size (e.g. 2G): " SWAP_SIZE
fi

### Ask for partition layout
echo "Select partitioning scheme:"
echo "1) Single / partition"
echo "2) Separate / and /home partitions"
echo "3) Use existing /home partition (no format)"
read -rp "Choice: " scheme_choice

case $scheme_choice in
  1)
    PART_SCHEME="single"
    ;;
  2)
    PART_SCHEME="separate_home"
    read -rp "Enter root (/) size (e.g. 40G): " ROOT_SIZE
    read -rp "Enter home (/home) size (e.g. 100G): " HOME_SIZE
    ;;
  3)
    PART_SCHEME="existing_home"
    read -rp "Enter root (/) size (e.g. 40G): " ROOT_SIZE
    read -rp "Enter existing /home partition path (e.g. /dev/sdb1): " EXISTING_HOME_PART
    ;;
  *)
    echo "Invalid choice"
    exit 1
    ;;
esac

### Ask for filesystems
read -rp "Choose filesystem for root (/): " ROOT_FS
if [[ "$PART_SCHEME" != "single" ]]; then
  read -rp "Choose filesystem for /home: " HOME_FS
fi

### Confirm before proceeding
echo "You are about to partition and format: $DISK"
read -rp "Proceed? [yes/NO]: " confirm
if [[ "$confirm" != "yes" ]]; then
  echo "Aborted."
  exit 1
fi

### Partition Disk
echo "Partitioning $DISK..."
sgdisk -Z "$DISK"

# EFI or BIOS boot partition
if [[ "$BOOT_MODE" == "UEFI" ]]; then
  sgdisk -n 1:0:+512M -t 1:ef00 -c 1:EFI "$DISK"
  EFI_PART="${DISK}1"
elif [[ "$BOOT_MODE" == "BIOS" ]]; then
  sgdisk -n 1:0:+1M -t 1:ef02 -c 1:BIOSBOOT "$DISK"
fi

# Index for next partitions
INDEX=2

# Swap
if $USE_SWAP; then
  sgdisk -n $INDEX:0:+$SWAP_SIZE -t $INDEX:8200 -c $INDEX:SWAP "$DISK"
  SWAP_PART="${DISK}${INDEX}"
  INDEX=$((INDEX + 1))
fi

# Root
sgdisk -n $INDEX:0:+${ROOT_SIZE:-100%} -t $INDEX:8300 -c $INDEX:ROOT "$DISK"
ROOT_PART="${DISK}${INDEX}"
INDEX=$((INDEX + 1))

# Home (optional)
if [[ "$PART_SCHEME" == "separate_home" ]]; then
  sgdisk -n $INDEX:0:+$HOME_SIZE -t $INDEX:8300 -c $INDEX:HOME "$DISK"
  HOME_PART="${DISK}${INDEX}"
elif [[ "$PART_SCHEME" == "existing_home" ]]; then
  HOME_PART="$EXISTING_HOME_PART"
fi

### Format Partitions
echo "Formatting..."
[[ "$BOOT_MODE" == "UEFI" ]] && mkfs.fat -F32 "$EFI_PART"
[[ "$USE_SWAP" == true ]] && mkswap "$SWAP_PART" && swapon "$SWAP_PART"
mkfs."$ROOT_FS" "$ROOT_PART"
[[ "$PART_SCHEME" == "separate_home" ]] && mkfs."$HOME_FS" "$HOME_PART"

### Mount Partitions
mount "$ROOT_PART" /mnt
[[ "$BOOT_MODE" == "UEFI" ]] && mkdir -p /mnt/boot && mount "$EFI_PART" /mnt/boot
if [[ "$PART_SCHEME" == "separate_home" || "$PART_SCHEME" == "existing_home" ]]; then
  mkdir -p /mnt/home
  mount "$HOME_PART" /mnt/home
fi

echo "✅ Disk setup complete. Ready for base install."
