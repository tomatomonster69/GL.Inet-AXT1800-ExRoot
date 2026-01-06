!!!! MAKE SURE TO CREATE ARCHIVE BACKUP BEFORE PROCEEDING. THIS WILL NUKE YOUR ROUTER SETTINGS !!!!

The script will:

     Verify your router model
     Remove conflicting packages 

     Detect and prepare the SD card
     Create partitions (1GB swap + remaining space for root)
     Format partitions
     Configure fstab for extroot
     Copy current overlay to SD card
     Prompt for reboot

What the Script Does

     

    Package Management:
        Installs required packages: block-mount, kmod-fs-ext4, e2fsprogs, fdisk, swap-utils
        Removes GL.iNet storage packages that interfere with extroot 

 

SD Card Preparation:

    Detects SD card device (typically /dev/mmcblk0)
    Creates two partitions:
        Partition 1: 1GB swap space
        Partition 2: Remaining space for ext4 root filesystem

 

Configuration:

    Configures fstab for automatic mounting
    Sets appropriate boot delays for GL.iNet firmware
    Copies existing overlay data to new partition 

Troubleshooting
Common Issues

     

    SD Card Not Detected:
        Ensure SD card was inserted before powering on 

Try a different SD card (some cards have compatibility issues) 

    Check dmesg output for SD card errors

 

Partitioning Failures:

    The script will attempt to recreate partition table if needed
    Manual intervention may be required for severely corrupted cards

 

Boot Problems:

    If router fails to boot, remove SD card and it will boot from internal storage
    Check that delay_root is set appropriately in fstab


    SD Card Compatibility

While most SD cards should work, some users have reported issues with certain brands/models 

. If you experience problems:

    Try a different SD card
    Use a reputable brand like SanDisk or Samsung
    Avoid very large cards (1TB+) which may have compatibility issues 

Safety Notes

    ⚠️ Backup Important Data: This process will wipe the SD card
    ⚠️ No Hot-Plug Support: Always insert SD card before powering on 

    ⚠️ Boot Fallback: If SD card fails, remove it to boot from internal storage
    ⚠️ Power Stability: Use a stable power source during the process

Post-Setup Benefits

With extroot configured, you can:

    Install additional packages that require more storage 

Store Docker containers and images (if using Docker) 

    Run applications that need more disk space
    Enjoy significantly expanded storage capacity

Contributing

Feel free to submit issues and pull requests. For major changes, please open an issue first to discuss what you would like to change.
License

This project is licensed under the MIT License - see the LICENSE file for details.
References

    Based on OpenWrt extroot configuration documentation 

Optimized for GL.iNet AXT1800 hardware specifications 
Addresses known limitations with SD card hot-plug support 

Acknowledgments

    Thanks to the OpenWrt community for extroot documentation
    Inspired by various GL.iNet forum discussions and user experiences
