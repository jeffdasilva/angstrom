SUMMARY = "A small image just capable of allowing a device to boot."

#sysvinit removed
#consider adding packagegroup-core-boot???
IMAGE_INSTALL = "base-files base-passwd busybox initscripts ${ROOTFS_PKGMANAGE_BOOTSTRAP} ${CORE_IMAGE_EXTRA_INSTALL}"

IMAGE_LINGUAS = " "

LICENSE = "MIT"

inherit core-image

IMAGE_ROOTFS_SIZE ?= "8192"

