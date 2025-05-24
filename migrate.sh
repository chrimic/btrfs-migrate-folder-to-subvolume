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

# Function to check if script is run as root
check_root() {
  if [ "$EUID" -ne 0 ]; then
    echo "This script must be run as root"
    exit 1
  fi
}

# Function to display all Btrfs subvolumes in the current directory.
show_subvolumes() {
  echo
  echo "Subvolume list:"
  btrfs subvolume list .
}

# Function to check btrfs inode type.
# Reference: https://stackoverflow.com/questions/25908149/how-to-test-if-location-is-a-btrfs-subvolume
check_btrfs_inode() {
  local dir=$1
  local expected_inode=$2

  # Controlla se il filesystem è btrfs
  [ "$(stat -f --format="%T" "$dir")" == "btrfs" ] || return 1
  # Ottieni il numero inode della directory
  local inode
  inode="$(stat --format="%i" "$dir")"
  [ "$inode" -eq "$expected_inode" ]
}

# Function to check if a given path is a Btrfs subvolume.
# A Btrfs subvolume has a specific inode number (256 for regular subvolumes).
is_btrfs_subvolume() {
   check_btrfs_inode "$1" 256
}

# Function to check if a given path is an "old" Btrfs subvolume.
is_btrfs_old_subvolume() {
   check_btrfs_inode "$1" 2
}

# Function to create a Btrfs snapshot (clone) of a source subvolume.
# Arguments:
#   $1: Source subvolume path
#   $2: Destination directory where the snapshot will be created
clone_subvolume() {
  local SRC="$1"
  local NEW="$2"
  
  if [ ! -d "$SRC" ]; then
    echo "WARNING | Source directory $SRC does not exist."
    return 1
  fi
  
  if [ -d "$NEW" ]; then
    echo "NO-OP   | Destination directory $NEW already exists."
    return 1
  fi
  
  btrfs subvolume snapshot "$SRC" "$NEW"/
}

# Function to move (copy) files and directories, preserving attributes.
# Uses rsync for efficient copying.
# Arguments:
#   $1: Source path
#   $2: Destination path
move() {
  local SRC="$1"
  local DST="$2"
  # rsync options:
  # -a: archive mode (preserves permissions, ownership, timestamps, symlinks, etc.)
  # -A: preserve ACLs (Access Control Lists)
  # -X: preserve extended attributes
  # -H: preserve hard links
  # -S: handle sparse files efficiently
  rsync -aAXHS "$SRC" "$DST"
}

# Migrate owner, permissions, and SELinux context from the old directory to the new temp subvolume
migrate_permissions() {
  local source=$1
  local target=$2
  chown --reference="$source" "$target"
  chmod --reference="$source" "$target"
  chcon --reference="$source" "$target"
}

# Function to update etc/fstab with a new subvolume entry
# Arguments:
#   $1: etc/fstab location
#   $2: New mount point path (e.g., "/home")
#   $3: Subvolume name (e.g., "@home")
add_fstab_entry() {
  local fstab="$1"
  local mount_point="$2"
  local subvol_name="$3"

  # Find the line with UUID, path "/" and filesystem "btrfs"
  local source_line
  source_line=$(grep "UUID=$BTRFS_UUID.*btrfs" "$fstab" | grep " / ")
  
  if [ -n "$source_line" ]; then
    # Create new line by replacing mount point and adding subvol
    local new_line
    new_line=$(echo "$source_line" | sed "s| / | $mount_point |" | sed "s/subvol=[^,]*/subvol=$subvol_name/")
    
    # Append the new line to fstab if it doesn't exist
    if ! grep -q " $mount_point " "$fstab"; then
      echo "$new_line" >> "$fstab"
      echo "Added new entry to $fstab for $mount_point with subvol=$subvol_name"
    else
      echo "Entry for $mount_point already exists in $fstab"
    fi
  else
    echo "Could not find source entry with UUID=$BTRFS_UUID in $fstab"
  fi
}

# Function to migrate a regular folder into a nested Btrfs subvolume.
# This function handles three scenarios for the SOURCE directory:
# 1. If it's already a regular Btrfs subvolume (inode 256), do nothing.
# 2. If it's an "old" Btrfs subvolume (inode 2),
#    it will be deleted and recreated as a regular subvolume,
#    with ownership/permissions migrated.
# 3. If it's a regular directory, it will be moved to a temporary location,
#    a new subvolume will be created in its place, and the contents
#    will be moved into the new subvolume. Ownership, permissions, and
#    SELinux context are preserved. The temporary directory is then removed.
# Arguments:
#   $1: The source directory to be migrated.
migrate_folder_to_nested_subvolume() {
  local SOURCE="$WD/$1"

  if [ -d "$SOURCE" ]; then
    if (is_btrfs_subvolume "$SOURCE"); then
      echo "NO-OP   | $SOURCE is already a btrfs subvolume. Nothing to be done."
    elif (is_btrfs_old_subvolume "$SOURCE"); then
      echo "WARNING | $SOURCE is btrfs old subvolume (inode 2). I'm deleting it and recreating."
      # Create a temporary subvolume
      btrfs subvolume create "$SOURCE"_temp
      # Migrate owner, permissions, and SELinux context from the old directory to the new temp subvolume
      migrate_permissions "$SOURCE" "${SOURCE}_temp"
      # Remove the old directory (which was an old subvolume)
      rm -r "$SOURCE"
      # Rename the temporary subvolume to the original source name
      mv "$SOURCE"_temp "$SOURCE"
    else # $SOURCE should be a regular folder
      # If it's a regular directory, move it to a temporary name
      mv "$SOURCE" "$SOURCE"_temp || (echo "skipping $SOURCE" && return 0)
      # Create a new Btrfs subvolume at the original source path
      btrfs subvolume create "$SOURCE"
      # Move the contents from the temporary directory into the new subvolume
      move "$SOURCE"_temp/ "$SOURCE"/
      # Migrate owner, permissions, and SELinux context from the temporary directory to the new subvolume
      chown --reference="$SOURCE"_temp "$SOURCE"
      chmod --reference="$SOURCE"_temp "$SOURCE"
      chcon --reference="$SOURCE"_temp "$SOURCE"
      echo "deleting $SOURCE"_temp
      # Remove the temporary directory
      rm -r "$SOURCE"_temp
    fi
  else
    echo "WARNING | Directory $SOURCE does not exist. Cannot create a subvolume."
  fi
}

# Function to migrate a regular folder to a top-level (flat) Btrfs subvolume.
# This function assumes the new subvolume will be created directly under $WD
# and then the original folder's content will be moved into it.
# It also creates an empty directory at the original source path and reminds
# the user to update fstab.
# Remember to add subvol=$2 to fstab to mount the new top-level subvolume.
# Arguments:
#   $1: The source directory to be migrated (e.g., "home").
#   $2: The name of the new top-level subvolume (e.g., "@home").
migrate_folder_to_flat_subvolume() {
  local SUBVOL="$WD/$2" # Construct the full path for the new top-level subvolume
  local SOURCE="$1"

  if [ -d "$SUBVOL" ] && (is_btrfs_subvolume "$SUBVOL"); then
      echo "NO-OP   | $SUBVOL is already a btrfs subvolume. Nothing to be done."
    return 0
  fi

  if [ -d "$SOURCE" ]; then
    if (is_btrfs_subvolume "$SOURCE"); then
      echo "WARNING | $SOURCE is btrfs subvolume. Nothing to be done."
    elif (is_btrfs_old_subvolume "$SOURCE"); then
      echo "WARNING | $SOURCE is btrfs old subvolume (inode 2)."
      # Move the original directory to a temporary name
      mv "$SOURCE" "$SOURCE"_temp
      # Create the new top-level Btrfs subvolume
      btrfs subvolume create "$SUBVOL"
      # Create an empty directory at the original source path.
      # This directory will serve as the mount point for the new top-level subvolume.
      mkdir "$SOURCE"
      # Migrate owner, permissions, and SELinux context from the temporary directory to the new empty directory
      migrate_permissions "${SOURCE}_temp" "$SOURCE"
      echo "deleting $SOURCE"_temp
      # Remove the temporary directory
      rm -r "$SOURCE"_temp
    else # $SOURCE should be a regular folder
      # Move the original directory to a temporary name
      mv "$SOURCE" "$SOURCE"_temp
      # Create the new top-level Btrfs subvolume
      btrfs subvolume create "$SUBVOL"
      # Move the contents from the temporary directory into the new top-level subvolume
      move "$SOURCE"_temp/ "$SUBVOL"/
      # Create an empty directory at the original source path.
      # This directory will serve as the mount point for the new top-level subvolume.
      mkdir "$SOURCE"
      # Migrate owner, permissions, and SELinux context from the temporary directory to the new empty directory
      chown --reference="$SOURCE"_temp "$SOURCE"
      chmod --reference="$SOURCE"_temp "$SOURCE"
      chcon --reference="$SOURCE"_temp "$SOURCE"
      echo "deleting $SOURCE"_temp
      # Remove the temporary directory
      rm -r "$SOURCE"_temp
    fi
  else
    echo "WARNING | Directory $SOURCE does not exist. Cannot create a subvolume."
  fi
}



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
read -rp "Please, review $WD/@/etc/fstab. Press Enter to continue..."

$EDITOR "$WD/@/etc/fstab"

