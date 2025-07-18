#!/bin/bash

# Global config vars - these will be filled in by partition.sh
BOOT_MODE=""         # "UEFI" or "BIOS"
DISK=""              # Target disk
PART_SCHEME=""       # "single", "separate_home", "home_on_other_disk"
USE_SWAP=false
SWAP_SIZE=""         # e.g. "2G"
ROOT_SIZE=""         # Only if using separate partitions
HOME_SIZE=""         # Optional
ROOT_FS="ext4"
HOME_FS="ext4"
EXISTING_HOME_PART="" # If user wants to reuse /home
