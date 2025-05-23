# btrfs-migrate-folder-to-subvolume

---

A Bash script designed to assist in **migrating existing directories into Btrfs subvolumes**. This script handles the creation of both nested and flat subvolumes, includes initial Btrfs filesystem setup with snapshots, and ensures proper attribute migration.

## ⚠️ Disclaimer

**I am not responsible for any data loss or system instability that may occur from using this script.** This script performs destructive operations on a Btrfs filesystem. **It is CRITICAL that you understand what each command does and have a full backup of your data before executing it.** Read the script thoroughly and test it in a safe environment before running it on production data.

## Features

* **Btrfs Subvolume Detection:** Functions to check if a path is a regular Btrfs subvolume (inode 256) or an "old" subvolume (inode 2).
* **Subvolume Cloning:** Ability to create snapshots of existing subvolumes.
* **Directory Migration:** Migrates standard directories into new Btrfs subvolumes, preserving permissions, ownership, extended attributes, and hard links using `rsync`.
* **Nested Subvolumes:** Supports creating subvolumes nested within other subvolumes.
* **Flat (Top-Level) Subvolumes:** Handles migration to top-level subvolumes, reminding the user to update `/etc/fstab` for mounting.
* **Attribute Preservation:** Uses `chown`, `chmod`, and `chcon` to ensure ownership, permissions, and SELinux contexts are retained during migration.
* **Idempotent Operations:** Includes warnings and skips for directories already identified as Btrfs subvolumes to prevent accidental reprocessing.

## Prerequisites

* A Linux system with **Btrfs filesystem tools** installed.
* **`rsync`** utility installed.
* **Root privileges** to perform Btrfs operations and mount filesystems.
* **A Btrfs filesystem** already formatted and available.
* **Crucially: A full backup of your data.**

## Usage

1.  **Save the script:** Save the script content to a file, for example, `migrate_btrfs.sh`.
2.  **Check the content** and edit it as your needs. You need to provide the UUID of your Btrfs filesystem. You can find your Btrfs UUID using `sudo blkid` or `lsblk -f` or check your current `/etc/fstab`.

3.  **Make it executable:**
    ```bash
    chmod +x migrate.sh
    ```
4.  **Run the script with the Btrfs filesystem UUID:**

    ```bash
    sudo ./migrate.sh
    ```

    The script expects the Btrfs filesystem to be mounted at `/mnt` before it starts its operations (or it will attempt to mount `subvolid=5` to `/mnt`). The migration process will then create subvolumes and move data as defined within the script.

## Script Overview

The script performs the following key steps:

* **Initial Setup:**
    * Sets `WD=/mnt` as the working directory.
    * Requires the Btrfs UUID as a command-line argument.
    * Mounts the Btrfs filesystem (`subvolid=5`) to `/mnt` using the provided UUID.
* **Subvolume Cloning:**
    * Clones the `root` subvolume to `@` (common for Btrfs root setups).
    * Clones the `root` subvolume to `root_bak` as a safety measure.
* **Directory Migrations (within the `@` subvolume):**
    * Migrates `home` to a flat subvolume (`@home`). **Remember to update your `/etc/fstab` for `@home` after migration.**
    * Migrates `opt` and `srv` to nested subvolumes.
    * Navigates into `var` and migrates `abs`, `cache`, `tmp`, `spool` to nested subvolumes.
    * Navigates into `var/lib` and migrates `machines`, `docker`, `postgres`, `mysql` to nested subvolumes.
* **Final Step:** Lists all subvolumes after the migration to show the new structure.

## Important Considerations

* **Modify with Caution:** The paths and migration targets (`home`, `opt`, `srv`, `var/lib/docker`, etc.) are hardcoded in the script. **Review and modify these paths** within the script to match your specific directory structure and desired Btrfs layout.
* **`fstab` Update:** For flat subvolumes like `home` (migrated to `@home`), you **MUST** update your `/etc/fstab` to properly mount the new subvolume at boot.
* **SELinux/AppArmor:** The script attempts to preserve SELinux contexts with `chcon --reference`. Ensure this is sufficient for your system, or make additional adjustments if needed.
* **Read the comments:** The script is heavily commented. Read through the comments to understand the exact purpose of each function and command before execution.

## License

This project is licensed under the MIT License - see the `LICENSE` file for details.
