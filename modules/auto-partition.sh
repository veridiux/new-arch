#!/bin/bash
set -e
source "$(dirname "$0")/../config.sh"

parse_size_to_mib() {
  local input=$(echo "$1" | tr '[:upper:]' '[:lower:]')

  if [[ "$input" =~ ^([0-9]+)g$ ]]; then
    local num="${BASH_REMATCH[1]}"
    echo $(( num * 1024 ))
  elif [[ "$input" =~ ^([0-9]+)(m|mb)$ ]]; then
    local num="${BASH_REMATCH[1]}"
    echo "$num"
  elif [[ "$input" =~ ^([0-9]+)k$ ]]; then
    local num="${BASH_REMATCH[1]}"
    echo $(( num / 1024 ))
  elif [[ "$input" =~ ^[0-9]+$ ]]; then
    echo "$input"
  else
    echo "❌ Invalid format: $1" >&2
    return 1
  fi
}



choose_filesystem() {
  local part_name=$1
  echo "Choose filesystem for $part_name partition:"
  echo "1) ext4"
  echo "2) btrfs"
  echo "3) xfs"
  echo "4) f2fs"
  read -rp "Enter choice [1-4] (default: 1): " choice

  case "$choice" in
    2) echo "btrfs" ;;
    3) echo "xfs" ;;
    4) echo "f2fs" ;;
    *) echo "ext4" ;;
  esac
}

echo "==== Manual Partitioning ===="

lsblk
read -rp "Enter target disk (e.g. /dev/sda): " DISK

read -rp "⚠️  This will WIPE all data on $DISK. Proceed? (yes/no): " confirm
[[ "$confirm" != "yes" ]] && { echo "Aborting."; exit 1; }

sgdisk -Z "$DISK"

PART_NUM=1

if [[ "$BOOT_MODE" == "UEFI" ]]; then
  sgdisk -n $PART_NUM:0:+512M -t $PART_NUM:ef00 -c $PART_NUM:EFI "$DISK"
  EFI_PART="${DISK}${PART_NUM}"
  PART_NUM=$((PART_NUM + 1))
elif [[ "$BOOT_MODE" == "BIOS" ]]; then
  sgdisk -n $PART_NUM:0:+1M -t $PART_NUM:ef02 -c $PART_NUM:BIOSBOOT "$DISK"
  PART_NUM=$((PART_NUM + 1))
fi

echo "Partition layout options:"
echo "1) Use entire remaining disk for root (/)"
echo "2) Specify size for root (/) and optionally /home"
read -rp "Select layout option [1/2]: " layout

if [[ "$layout" == "1" ]]; then
  ROOT_PART="${DISK}${PART_NUM}"
  sgdisk -n $PART_NUM:0:0 -t $PART_NUM:8300 -c $PART_NUM:ROOT "$DISK"
  PART_NUM=$((PART_NUM + 1))
elif [[ "$layout" == "2" ]]; then
  read -rp "Enter size for root (/), e.g. 40G: " root_input
  root_mib=$(parse_size_to_mib "$root_input")
  ROOT_SIZE="+${root_mib}M"

  ROOT_PART="${DISK}${PART_NUM}"
  sgdisk -n $PART_NUM:0:$ROOT_SIZE -t $PART_NUM:8300 -c $PART_NUM:ROOT "$DISK"
  PART_NUM=$((PART_NUM + 1))

  read -rp "Do you want a separate /home partition? [y/N]: " home_yn
  if [[ "$home_yn" =~ ^[Yy]$ ]]; then
    read -rp "Enter size for /home, e.g. 100G (or leave blank to use all remaining space minus swap): " home_input
    if [[ -z "$home_input" ]]; then
      HOME_PART="${DISK}${PART_NUM}"
      HOME_SIZE="remaining"
    else
      home_mib=$(parse_size_to_mib "$home_input")
      HOME_SIZE="+${home_mib}M"
      HOME_PART="${DISK}${PART_NUM}"
      sgdisk -n $PART_NUM:0:$HOME_SIZE -t $PART_NUM:8300 -c $PART_NUM:HOME "$DISK"
      PART_NUM=$((PART_NUM + 1))
    fi
  fi
else
  echo "Invalid selection. Exiting."
  exit 1
fi

read -rp "Use swap partition at end of disk? [y/N]: " swap_yn
if [[ "$swap_yn" =~ ^[Yy]$ ]]; then
  USE_SWAP=true
  while true; do
    read -rp "Enter swap size (e.g. 2G, 2048MB): " swap_input
    swap_mib=$(parse_size_to_mib "$swap_input") && break
    echo "❌ Invalid format. Try again."
  done
  SWAP_SIZE="${swap_mib}M"
fi

# Create home partition if "remaining"
if [[ "$HOME_SIZE" == "remaining" && "$USE_SWAP" == true ]]; then
  HOME_PART="${DISK}${PART_NUM}"
  sgdisk -n $PART_NUM:0:-$SWAP_SIZE -t $PART_NUM:8300 -c $PART_NUM:HOME "$DISK"
  PART_NUM=$((PART_NUM + 1))
elif [[ "$HOME_SIZE" == "remaining" ]]; then
  HOME_PART="${DISK}${PART_NUM}"
  sgdisk -n $PART_NUM:0:0 -t $PART_NUM:8300 -c $PART_NUM:HOME "$DISK"
  PART_NUM=$((PART_NUM + 1))
fi

# Create swap partition last if used
if [[ "$USE_SWAP" == true ]]; then
  SWAP_PART="${DISK}${PART_NUM}"
  sgdisk -n $PART_NUM:-$SWAP_SIZE:0 -t $PART_NUM:8200 -c $PART_NUM:SWAP "$DISK"
fi

echo "Select filesystems for partitions:"

ROOT_FS=$(choose_filesystem "root")

if [[ -n "$HOME_PART" ]]; then
  HOME_FS=$(choose_filesystem "/home")
fi

# Formatting partitions
echo "Formatting partitions..."

# EFI formatting
if [[ "$BOOT_MODE" == "UEFI" ]]; then
  mkfs.fat -F32 "$EFI_PART"
fi

# Root partition
mkfs_cmd="mkfs.$ROOT_FS"
echo "Formatting root partition ($ROOT_PART) with $ROOT_FS"
$mkfs_cmd "$ROOT_PART"

# Home partition if exists
if [[ -n "$HOME_PART" ]]; then
  mkfs_cmd="mkfs.$HOME_FS"
  echo "Formatting /home partition ($HOME_PART) with $HOME_FS"
  $mkfs_cmd "$HOME_PART"
fi

# Swap partition if used
if [[ "$USE_SWAP" == true ]]; then
  echo "Setting up swap on $SWAP_PART"
  mkswap "$SWAP_PART"
  swapon "$SWAP_PART"
fi

echo "Manual partitioning and formatting complete."
echo "Partitions and filesystems:"
lsblk "$DISK" -o NAME,FSTYPE,SIZE,MOUNTPOINT,LABEL
