#!/usr/bin/env bash
set -euo pipefail

# Mount points
PARITY_MOUNT_POINTS=(
    "/mnt/parity1"
)

DATA_MOUNT_POINTS=(
    "/mnt/disk1"
    "/mnt/disk2"
    "/mnt/disk3"
)

# Corresponding WWN-partition IDs
PARITY_DISK_IDS=(
    "wwn-0x5000c500a4be17b7-part1"
)
DATA_DISK_IDS=(
    "wwn-0x5000c500a4be3c57-part1"
    "wwn-0x5000c500a4be8ca0-part1"
    "wwn-0x50014ee20ad6d6a7-part1"
)

# Ensure mount points exist
for mp in "${PARITY_MOUNT_POINTS[@]}"; do
    mkdir -p "$mp"
done
for mp in "${DATA_MOUNT_POINTS[@]}"; do
    mkdir -p "$mp"
done

# Add entries to fstab if they don't already exist
for i in "${!PARITY_MOUNT_POINTS[@]}"; do
    mp="${PARITY_MOUNT_POINTS[$i]}"
    disk="/dev/disk/by-id/${PARITY_DISK_IDS[$i]}"

    if ! grep -q "$disk" /etc/fstab; then
        echo "$disk    $mp    xfs    defaults,noatime    0 0" >> /etc/fstab
        echo "Added $disk -> $mp to /etc/fstab"
    else
        echo "Entry for $disk already exists in /etc/fstab"
    fi
done
for i in "${!DATA_MOUNT_POINTS[@]}"; do
    mp="${DATA_MOUNT_POINTS[$i]}"
    disk="/dev/disk/by-id/${DATA_DISK_IDS[$i]}"

    if ! grep -q "$disk" /etc/fstab; then
        echo "$disk    $mp    xfs    defaults,noatime    0 0" >> /etc/fstab
        echo "Added $disk -> $mp to /etc/fstab"
    else
        echo "Entry for $disk already exists in /etc/fstab"
    fi
done

# create mergerfs storage
MERGERFS_MP="/mnt/storage"
mkdir -p "$MERGERFS_MP"

MERGERFS_OPTIONS="defaults,allow_other,category.create=epmfs,moveonenospc=true,cache.files=off,func.getattr=newest,dropcacheonclose=false,fsname=storage"

# Build the list of source drives for mergerfs
MERGERFS_SOURCES=$(printf "/mnt/disk%d:" $(seq 1 ${#DATA_MOUNT_POINTS[@]}))
MERGERFS_SOURCES="${MERGERFS_SOURCES::-1}" # Remove trailing colon

# Add mergerfs entry if missing
if ! grep -q "$MERGERFS_MP" /etc/fstab; then
    echo "$MERGERFS_SOURCES    $MERGERFS_MP    fuse.mergerfs    $MERGERFS_OPTIONS    0 0" >> /etc/fstab
    echo "Added mergerfs pool: $MERGERFS_SOURCES -> $MERGERFS_MP"
else
    echo "Mergerfs pool entry already exists in fstab"
fi

# Mount all drives immediately
mount -a
