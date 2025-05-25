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

# Include helper functions
source migration-libs.sh

# --- Main Script Execution ---

# Ensure script is running with root privileges
check_root

# Exit immediately if a command exits with a non-zero status.
set -e

# Change to the working directory. All subsequent relative paths will be
# interpreted from here.
cd "/home/christian/"

# Migrate .cache to be a nested subvolume because I don't want to have this inside my snapshots.
migrate_folder_to_nested_subvolume .cache

# Show the list of all Btrfs subvolumes after the migration operations.
show_subvolumes
