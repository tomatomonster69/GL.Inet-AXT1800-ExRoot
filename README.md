!!!! MAKE SURE TO CREATE ARCHIVE BACKUP BEFORE PROCEEDING. THIS WILL NUKE YOUR ROUTER SETTINGS !!!!


<img width="2074" height="1413" alt="exroot" src="https://github.com/user-attachments/assets/dba9ec11-e7ec-48e4-8226-429054f78122" />




To run simply copy script and save as exroot.sh on /root  
run: 

     chmod +x exroot.sh # this will make file executable
run: 
     
     ./exroot.sh # to run
OR copy direcly and run 

     wget -O exroot.sh https://github.com/tomatomonster69/GL.Inet-AXT1800-ExRoot/blob/main/exroot.sh && chmod +x exroot.sh && ./exroot.sh


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
      ⚠️Removes GL.iNet storage packages that interfere with extroot. Only use if you do not play to run NFS or SMB 

 

SD Card Preparation:

  ##  Detects SD card device (typically /dev/mmcblk0)
  ##  Creates two partitions:
  ##      Partition 1: 1GB swap space
  ##      Partition 2: Remaining space for ext4 root filesystem

 

Configuration:

    Configures fstab for automatic mounting
    Sets appropriate boot delays for GL.iNet firmware
    Copies existing overlay data to new partition 

Troubleshooting #1. Run these commands to nuke the current data on the SD Card if it was previously mounted. 

     lsof /dev/mmcblk0p1 2>/dev/null || echo "No processes found using partition"
     mount | grep mmcblk0p1

     umount /dev/mmcblk0p1 2>/dev/null || true

     swapon --show | grep mmcblk0p1

     swapoff /dev/mmcblk0p1 2>/dev/null || true

     mkswap -f /dev/mmcblk0p1
 

     umount /dev/mmcblk0p1 /dev/mmcblk0p2 2>/dev/null || true

     swapoff -a 2>/dev/null || true

     dd if=/dev/zero of=/dev/mmcblk0 bs=1M count=1
     sync

     # Create new partition table
     fdisk /dev/mmcblk0 <<EOF
     o
     n
     p
     1

     +1024M
     t
     82
     n
     p
     2


     w
     EOF

     sync
     sleep 3

     blockdev --rereadpt /dev/mmcblk0 2>/dev/null || true

     mkswap /dev/mmcblk0p1
     mkfs.ext4 -F /dev/mmcblk0p2
 

Boot Problems:

    If router fails to boot, remove SD card and it will boot from internal storage
    Check that delay_root is set appropriately in fstab

If you experience problems:

     1.Try a different SD card
     2.Use a reputable brand like SanDisk or Samsung

Safety Notes

    ⚠️ Backup Important Data: This process will wipe the SD card
    ⚠️ No Hot-Plug Support: Always insert SD card before powering on 

    ⚠️ Boot Fallback: If SD card fails, remove it to boot from internal storage
    ⚠️ Power Stability: Use a stable power source during the process

_________________________________________________________________________________________________________________________
Contributing

Feel free to submit issues and pull requests. For major changes, please open an issue first to discuss what you would like to change.
License

This project is licensed under the MIT License - see the LICENSE file for details.
References. 


Optimized for GL.iNet AXT1800 hardware specifications 
Addresses known limitations with SD card hot-plug support 

Acknowledgments

    Thanks to the OpenWrt community for extroot documentation
    Inspired by various GL.iNet forum discussions and user experiences
