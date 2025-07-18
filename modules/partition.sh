#!/bin/bash
set -e
source ../config.sh

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
read -rp "Partition automatically or manually? [y/M]: " MODE
if [[ "$MODE" != "M" ]]; then
  echo "Manual mode not implemented yet. Exiting."
  exit 1
fi

### Ask if swap should be created
read -rp "Use swap partition? [y/N]: " use_swap
if [[ "$use_swap" =~ ^[Yy]$ ]]; then
  USE_SWAP=true

  while true; do
    read -rp "Enter swap size (e.g. 2G, 2048MB): " input_size
    mib=$(parse_size_to_mib "$input_size") && break
    echo "❌ Invalid format. Try again."
  done

  SWAP_SIZE="${mib}M"
fi


parse_size_to_mib() {
  local input=$(echo "$1" | tr '[:upper:]' '[:lower:]')
  
  if [[ "$input" =~ ^([0-9]+)g$ ]]; then
    echo $(( ${BASH_REMATCH[1]} * 1024 ))
  elif [[ "$input" =~ ^([0-9]+)mb?$ ]]; then
    echo "${BASH_REMATCH[1]}"
  elif [[ "$input" =~ ^([0-9]+)k$ ]]; then
    echo $(( ${BASH_REMATCH[1]} / 1024 ))
  elif [[ "$input" =~ ^[0-9]+$ ]]; then
    echo "$input"  # Assume MB if no unit
  else
    echo "Invalid size format: $1" >&2
    return 1
  fi
}


echo "✅ Disk setup complete. Ready for base install."
