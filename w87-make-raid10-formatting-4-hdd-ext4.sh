#!/usr/bin/env bash
# A stepwise Bash utility to wipe specified disks, partition them, create a RAID10 array, format it with ext4, mount it at specified directory, persist the configuration, run final checks and tune read-ahead.
# 
# @package   w87-make-raid10-formatting-4-hdd-ext4.sh
# @see       https://app.w87.eu/codeTag?file=w87-make-raid10-formatting-4-hdd-ext4.sh&project=w87-make-raid10-formatting-4-hdd-ext4.sh
# @version   2026.02.23
# @author    Walerian Walawski <bash@w87.eu>
# @link      https://w87.eu/
# @license   https://creativecommons.org/licenses/by-nc-sa/4.0/ Attribution-NonCommercial-ShareAlike 4.0 International
# @copyright 2026 w87.eu Walerian Walawski © all rights reserved.
# @category  bash

if [[ "$EUID" -ne 0 ]]; then
    echo "Please run as root"
    exit 1

elif [[ -z "$1" || "$1" == "--help" || "$1" == "-h" ]]; then
    echo "Usage: $0 <step1|step2|step3|step4|step5|step6|step7>"
    echo "Steps:"
    echo " → step1: Wipe disks"
    echo " → step2: Create partitions on disks"
    echo " → step3: Create RAID10 array"
    echo " → step4: Format and mount"
    echo " → step5: Make RAID persistent"
    echo " → step6: Final check and status"
    echo -e " → step7: Set RAID read-ahead settings\n\nABOUT THIS SCRIPT:\nThis script is designed to be run step-by-step, allowing you to execute each phase of the RAID10 setup process separately. This approach provides better control and allows you to verify each step before proceeding to the next one.\n\nPlease ensure you have backups of any important data before running this script, as it will wipe the specified disks and create a new RAID array.\n\nMake sure to run this script on a Debian-based system with the necessary tools installed (e.g., mdadm, parted, smartmontools).\n"
    grep -E "^# @" "$0" | sed 's/# @\(.*\)/ → \1/'

elif [[ "$1" == "step1" ]]; then
    echo "Step 1: Wiping disks: /dev/sda, /dev/sdb, /dev/sdc, /dev/sdd"
    for disk in /dev/sd{a,b,c,d}; do
        echo "Wiping $disk..."
        wipefs -a $disk
        mdadm --zero-superblock $disk 2>/dev/null
    done

elif [[ "$1" == "step2" ]]; then
    echo "Step 2: Creating partitions on disks"
    for disk in /dev/sd{a,b,c,d}; do
        echo "Creating partition on $disk"
        parted -s $disk mklabel gpt
        parted -s $disk mkpart primary 0% 100%
        parted -s $disk set 1 raid on
    done

    echo "Should have sda1, sdb1, sdc1, sdd1 now. Here’s the current partition layout:"
    ls -l /dev/sd{a,b,c,d}1 2>/dev/null || echo "No partitions found"

elif [[ "$1" == "step3" ]]; then
    echo "Step 3: Creating RAID10 array /dev/md0 with partitions sda1, sdb1, sdc1, sdd1"
    mdadm --create /dev/md0 \
        --level=10 \
        --raid-devices=4 \
        --layout=n2 \
        --bitmap=internal \
        /dev/sd[a-d]1

    echo "Waiting for RAID array to initialize..."
    while ! mdadm --detail /dev/md0 | grep -q "State : active"; do
        sleep 1
        cat /proc/mdstat
        # echo -n "."
    done
    echo "RAID10 array /dev/md0 is active!"
    cat /proc/mdstat

elif [[ "$1" == "step4" ]]; then
    echo "Step 4: Formatting /dev/md0 with ext4 and mounting to /var/www"
    mkfs.ext4 -L www \
        -E stride=128,stripe-width=256 \
        -O dir_index,filetype \
        -m 0 \
        /dev/md0

    [ -d '/var/www' ] && mv -v /var/www /var/www_backup
    mkdir -p /var/www
    mount -v -o noatime,nodiratime,commit=60 /dev/md0 /var/www

elif [[ "$1" == "step5" ]]; then
    echo "Step 5: Making RAID10 persistent "
    mdadm --detail --scan >> /etc/mdadm/mdadm.conf
    update-initramfs -u

    echo -e "Verify file contains something like:\nARRAY /dev/md0 ...\nHere is the file contents:\n"
    cat /etc/mdadm/mdadm.conf

    sleep 4

    echo "Get UUID:"
    blkid /dev/md0
    echo "Add to /etc/fstab..."
    echo "UUID=$(blkid -s UUID -o value /dev/md0) /var/www ext4 defaults,noatime,nodiratime,commit=60  0  2" >> /etc/fstab
    echo "Here is the current /etc/fstab contents:"
    cat /etc/fstab

elif [[ "$1" == "step6" ]]; then
    echo "Step 6: Final check and status"
    mount -a
    mdadm --detail /dev/md0
    df -h

    systemctl enable smartd || systemctl enable smartmontools.service
    systemctl start smartd
    systemctl status smartd

    echo "Check disks:"
    for disk in /dev/sd{a,b,c,d}; do
        echo "Checking $disk..."
        smartctl -a $disk
    done

elif [[ "$1" == "step7" ]]; then

    echo "Step 7: Increasing read-ahead for /dev/md0"
    echo "Current read-ahead value:"
    blockdev --getra /dev/md0
    
    echo -e "\nStep 7: Increasing read-ahead and saving settings for /dev/md0"
    blockdev --setra 4096 /dev/md0
    echo "Current read-ahead value:"
    blockdev --getra /dev/md0

    echo 'ACTION=="add|change", KERNEL=="md0", ATTR{bdi/read_ahead_kb}="2048"' >> /etc/udev/rules.d/99-md0-read-ahead.rules
    cat /etc/udev/rules.d/99-md0-read-ahead.rules
    udevadm control --reload
    udevadm trigger --name-match=md0
    echo -e "\nCurrent read-ahead value after udev rule applied:"
    blockdev --getra /dev/md0

fi
