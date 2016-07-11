echo "****************************************************"
echo "****************************************************"
echo ""
echo "Sitara Example Flashing Script - 02/11/2014"
echo ""

STARTTIME=$(date +%s)

##---------Start of variables---------------------##

## Set Server IP here
SERVER_IP="192.168.100.1"

## Names of the images to grab from TFTP server
BOOT_PARTITION="boot_partition.tar.gz"

## Rename rootfs as needed depending on use of tar or img
ROOTFS_PARTITION="rootfs_partition.tar.gz"
## ROOTFS_PARTITION="rootfs_partition.img.gz"

## Declare eMMC device name here
DRIVE="/dev/mmcblk0"

##----------End of variables-----------------------##

## TFTP files from host.  Edit the files and host IP address for your application.
## We are grabbing two files, one an archive with files to populate a FAT partion,
## which we will create.  Another for a filesystem image to 'dd' onto an unmounted partition.
## Using a compressed tarball can be easier to implement, however, with a large file system
## with a lot of small files, we recommend a 'dd' image of the partition to speed up writes.
echo "Getting files from server: ${SERVER_IP}"
time tftp -b 4096 -g -r ${BOOT_PARTITION} ${SERVER_IP} &
boot_pid=$!
time tftp -b 4096 -g -r ${ROOTFS_PARTITION} ${SERVER_IP} &
rootfs_pid=$!


## Kill any partition info that might be there
dd if=/dev/zero of=$DRIVE bs=4k count=1
sync
sync

## Figure out how big the eMMC is in bytes
SIZE=`fdisk -l $DRIVE | grep Disk | awk '{print $5}'`

## Translate size into segments, which traditional tools call Cylinders. eMMC is not a spinning disk.
## We are basically ignoring what FDISK and SFDISK are reporting because it is not really accurate.
## we are translating this info to something that makes more sense for eMMC.
CYLINDERS=`echo $SIZE/255/63/512 | bc`

## Check to see if the eMMC partitions have automatically loaded from the old MBR.
## This might have occured during the boot process if the kernel detected a filesystem
## before we killed the MBR. We will need to unmount and kill them by writing 4k zeros to the
## partitions that were found.

check_mounted(){
  is_mounted=$(grep ${DRIVE}p /proc/mounts | awk '{print $2}')

  if grep -q ${DRIVE}p /proc/mounts; then
      echo "Found mounted partition(s) on " ${DRIVE}": " $is_mounted
      umount $is_mounted
      counter=1
      for i in $is_mounted; do \
          echo "4k erase on ${DRIVE}p${counter}"; 
          dd if=/dev/zero of=${DRIVE}p${counter} bs=4k count=1;
          counter=$((counter+1));
      done
  else
      echo "No partition found. Continuing."
  fi
}

check_mounted;

## Partitioning the eMMC using information gathered.
## Here is where you can add/remove partitions.
## We are building 2 partitions:
##  1. FAT, size = 9 cylinders * 255 heads * 63 sectors * 512 bytes/sec = ~70MB
##  2. EXT3, size = 223 ($CYLINDERS-[9 for fat]) cylinders * 255 heads * 63 sectors * 512 bytes/sec = ~1l.7GB
##
## You will need to change the lines ",9,0c0C,*", "10,,,-" to suit your needs.  Adding is similar,
## but you will need to be aware of partition sizes and boundaries.  Use the man page for sfdisk.
echo "Partitioning the eMMC..."
sfdisk -D -H 255 -S 63 -C $CYLINDERS $DRIVE << EOF
,9,0x0C,*
10,,,-
EOF

## This sleep is necessary as there is a service which attempts
## to automount any filesystems that it finds as soon as sfdisk
## finishes partitioning.  We sleep to let it run.  May need to
## be lengthened if you have more partitions.
sleep 2

## Check here if there has been a partition that automounted.
##  This will eliminate the old partition that gets
##  automatically found after the sfdisk command.  It ONLY
##  gets found if there was a previous file system on the same
##  partition boundary.  Happens when running this script more than once.
##  To fix, we just unmount and write some zeros to it.
check_mounted;

## Clean up the dos (FAT) partition as recommended by SFDISK
dd if=/dev/zero of=${DRIVE}p1 bs=512 count=1

## Make sure posted writes are cleaned up
sync
sync

## Format the eMMC into 2 partitions
echo "Formatting the eMMC into 2 partitions..."

## Format the boot partition to fat32
mkfs.vfat -F 32 -n "boot" ${DRIVE}p1

## Format the rootfs to ext3 (or ext4, etc.) if using a tar file.
## We DO NOT need to format this partition if we are 'dd'ing an image
## Comment out this line if using 'dd' of an image.
mkfs.ext3 -L "rootfs" ${DRIVE}p2

## Make sure posted writes are cleaned up
sync
sync
echo "Formatting done."

## Make temp directories for mountpoints
mkdir tmp_boot

## Comment this line out if using 'dd' of an image. It is not needed.
mkdir tmp_rootfs

## Mount partitions for tarball extraction. NOT for 'dd'.
mount -t vfat ${DRIVE}p1 tmp_boot

## If 'dd'ing the rootfs, there is no need to mount it. Comment out the below.
mount -t ext3 ${DRIVE}p2 tmp_rootfs

## Wait for boot to finish tftp
wait $boot_pid
echo "Copying Files..."
time tar -xf ${BOOT_PARTITION} -C tmp_boot
sync
sync
umount ${DRIVE}p1
rm ${BOOT_PARTITION}
echo "Boot partition done."

## Wait for rootfs to finish tftp
wait $rootfs_pid
## If using a tar archive, untar it with the below.
## If using 'dd' of an img, comment these lines out and use the below.
time tar -xf ${ROOTFS_PARTITION} -C tmp_rootfs
sync
sync
umount ${DRIVE}p2
rm ${ROOTFS_PARTITION}
echo "RootFS partition done."

## If using 'dd' of an img, uncomment these lines.
## If using a tar archive, comment out these lines and use the above.
## time gunzip -c ${ROOTFS_PARTITION} | dd of=${DRIVE}p2 bs=4k
## sync
## sync
## echo "Rootfs partition done."

## The block below is only necessary if using 'dd'. 
## Force check the filesystem for consistency and fix errors if any.
## Resize partition to the length specified by the MBR.
## /sbin/e2fsck -fy ${DRIVE}p2
## /sbin/resize2fs ${DRIVE}p2

ENDTIME=$(date +%s)
echo "It took $(($ENDTIME - $STARTTIME)) seconds to complete this task..."
## Reboot
echo ""
echo "********************************************"
echo "Sitara Example Flash Script is complete."
echo ""



