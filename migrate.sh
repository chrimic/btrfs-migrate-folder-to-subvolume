#!/bin/bash

# MIT License
#
# Copyright (c) 2025 Christian Micocci
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.

# DISCLAIMER: I am not responsible for any data loss or system instability
# that may occur from using this script. This script performs destructive
# operations on a Btrfs filesystem. It is CRITICAL that you understand
# what each command does and have a full backup of your data before
# executing it. Read the script thoroughly before running.

# Define the working directory. This is where the Btrfs filesystem is expected
# to be mounted or where operations will be performed relative to.
WD="/mnt"

# Define the BTRFS partition UUID (check your current file /etc/fstab)
BTRFS_UUID="95f7571f-4ddd-4d1e-80fb-61f62ac56191"

# Define the editor for editing the /etc/fstab.
EDITOR="nano"

source migration-libs.sh

# --- Main Script Execution ---

# Ensure script is running with root privileges
check_root

# Mount the Btrfs filesystem using the provided UUID.
# The subvolid=5 typically refers to the default top-level subvolume.
mount UUID="$BTRFS_UUID" -o subvolid=5 "$WD"

# Change to the working directory. All subsequent relative paths will be
# interpreted from here.
cd "$WD"

# Clone the 'root' subvolume to '@'. This typically creates the main
# system subvolume for a Btrfs root setup.
clone_subvolume root @

# Clone the 'root' subvolume to 'root_bak'. This serves as a backup
# of the original root state.
clone_subvolume root root_bak

# Set @ as default subvolume
btrfs subvolume set-default "$WD/@"

# Exit immediately if a command exits with a non-zero status.
set -e

# Migrate the 'home' folder to a flat (top-level) subvolume named '@home'.
# This means /mnt/@/home will become a mount point for /mnt/@home.
migrate_folder_to_flat_subvolume @/home @home
add_fstab_entry @/etc/fstab /home @home

# Migrate the 'opt' folder to a nested subvolume within '@'.
# This means /mnt/@/opt will become a subvolume itself.
migrate_folder_to_nested_subvolume @/opt

# Migrate the 'srv' folder to a nested subvolume within '@'.
migrate_folder_to_nested_subvolume @/srv

# Migrate various subdirectories within 'var' to nested subvolumes.
migrate_folder_to_nested_subvolume @/var/abs
migrate_folder_to_nested_subvolume @/var/cache
migrate_folder_to_nested_subvolume @/var/tmp
migrate_folder_to_nested_subvolume @/var/spool

# Migrate various subdirectories within 'var/lib' to nested subvolumes.
migrate_folder_to_nested_subvolume @/var/lib/machines
migrate_folder_to_nested_subvolume @/var/lib/docker
migrate_folder_to_nested_subvolume @/var/lib/postgres
migrate_folder_to_nested_subvolume @/var/lib/mysql

# Show the list of all Btrfs subvolumes after the migration operations.
show_subvolumes

echo
# TODO Automatic change / subvol.
read -rp "Please, review $WD/@/etc/fstab. Remember to change / subvol. Press Enter to continue..."

$EDITOR "$WD/@/etc/fstab"

# Now, reboot your system, in grub menu edit the first entry and change the parameter subvol.
# Execute this function after reboot your system:
# Reference: https://fedoraproject.org/wiki/GRUB_2#Instructions_for_UEFI-based_systems
fedora_update_grub() {
  rm /boot/efi/EFI/fedora/grub.cfg
  rm /boot/grub2/grub.cfg
  dnf reinstall shim-* grub2-efi-* grub2-common
}