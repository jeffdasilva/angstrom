#!/bin/bash -e

# prerequisites
# sudo apt-get install gawk texinfo chrpath git g++ repo p7zip-full mtd-utils

THIS_DIR=$(cd "$(dirname "${0}")" && echo "$(pwd 2>/dev/null)")
THIS_SCRIPT=$(basename ${0})

# baseline your PATH (doesn't actually make a difference)
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

####
#This is what i do:
#git clone git://github.com/Angstrom-distribution/setup-scripts.git
#cd  setup-scripts
#git checkout -b angstrom-v2014.12-yocto1.7 remotes/origin/angstrom-v2014.12-yocto1.7
#Mod the sources to add the altera layers, my patch is attached.
# old way
# see http://rocketboards.org/foswiki/Documentation/AngstromOnSoCFPGA_1
####

#ANGSTROM_VER=v2014.12
ANGSTROM_VER=v2015.12

if [ "${ANGSTROM_VER}" = "v2014.12" ]; then
    # does not work with host gcc 5.*
    ANGSTROM_BASE_DIR=setup-scripts
    YOCTO_VER=yocto1.7
else
    # work in progress - does not work yet
    ANGSTROM_BASE_DIR=angstrom-manifest
    YOCTO_VER=yocto2.0
fi


ENABLE_MTDUTILS_PATCH=$[$(date +%j)%2]

ANGSTROM_TOP=$(pwd -P)/${ANGSTROM_BASE_DIR}
#ANGSTROM_MACH=socfpga_cyclone5
ANGSTROM_MACH=socfpga
ANGSTROM_MACH_BASELINE=cyclone5
ANGSTROM_PUBLISH_DIR=${HOME}/doozynas/www/angstrom/${ANGSTROM_VER}

if [ "${ENABLE_MTDUTILS_PATCH}" = "1" ]; then
    ANGSTROM_PUBLISH_DIR=${ANGSTROM_PUBLISH_DIR}.patched
fi

if [ -f "${ANGSTROM_PUBLISH_DIR}/${THIS_SCRIPT}" ]; then
    diff ${ANGSTROM_PUBLISH_DIR}/${THIS_SCRIPT} ${THIS_DIR}/${THIS_SCRIPT} || true
fi 

FORCE=${FORCE-1}
#FORCE=

echo "Welcome to Angstrom Build"
date
echo Process ID: $$

if [ "${FORCE}" = "1" ] || [ ! -d ${ANGSTROM_BASE_DIR} ]; then
    echo "FORCE SYNC & GIT CLONE"
    rm -rf ${ANGSTROM_BASE_DIR}.delete
    if [ -d ${ANGSTROM_BASE_DIR} ]; then
	mv ${ANGSTROM_BASE_DIR} ${ANGSTROM_BASE_DIR}.delete || true
	rm -rf ${ANGSTROM_BASE_DIR}.delete &
    fi

    if [ "${ANGSTROM_VER}" = "v2014.12" ]; then
	git clone git://github.com/Angstrom-distribution/${ANGSTROM_BASE_DIR}.git
	pushd ${ANGSTROM_BASE_DIR}
	git checkout -b soceds-angstrom-${ANGSTROM_VER}-${YOCTO_VER} remotes/origin/angstrom-${ANGSTROM_VER}-${YOCTO_VER}
    
	if [ -z "$(grep 'meta-altera' sources/layers.txt 2>/dev/null)" ]; then
	    echo "meta-altera,https://github.com/altera-opensource/meta-altera.git,angstrom-${ANGSTROM_VER}-${YOCTO_VER},HEAD" >> sources/layers.txt
	    echo "meta-altera-refdes,https://github.com/altera-opensource/meta-altera-refdes.git,master,HEAD" >> sources/layers.txt
	fi

	if [ -z "$(grep 'meta-altera' conf/bblayers.conf 2>/dev/null)" ]; then
	    echo >> conf/bblayers.conf
	    echo 'BASELAYERS += "${TOPDIR}/sources/meta-altera"' >> conf/bblayers.conf
	    echo >> conf/bblayers.conf
	fi
   

	# create this patch with
	#   cd ${ANGSTROM_BASE_DIR}
	#   git diff > ../altera-mods-patch.diff
	#   subract stuff altera echo stuff from above
	PATCH_FILE=../altera-mods-patch.diff
	if [ -f "${PATCH_FILE}" ]; then
	    echo "Apply Patch ${PATCH_FILE}"
	    git apply ${PATCH_FILE}
	fi
	popd
    fi

else
    if [ "${ANGSTROM_VER}" = "v2014.12" ]; then
	echo "GIT PULL"
	pushd ${ANGSTROM_TOP}
	git pull
	popd
    fi
fi

mkdir -p ${ANGSTROM_TOP}
pushd ${ANGSTROM_TOP}


if [ "${ANGSTROM_VER}" = "v2014.12" ]; then
    ##############
    #  1/ Configure the build environment
    # run twice because of /bin/bash /bin/dash symlink issues
    MACHINE=${ANGSTROM_MACH} bash ./oebb.sh config ${ANGSTROM_MACH} || bash ./oebb.sh config ${ANGSTROM_MACH}
    ##############
else
    repo init -u git://github.com/Angstrom-distribution/angstrom-manifest -b angstrom-${ANGSTROM_VER}-${YOCTO_VER}
    sed -i.orig -e 's,\(<project[ \t]name="kraj/meta-altera"[ \t].*revision=\).*>,\1"jethro"/>,g' .repo/manifest.xml
    repo sync
    MACHINE=${ANGSTROM_MACH} source setup-environment
fi


# Case:241717
rm -f sources/meta-altera/conf/machine/socfpga.conf
cp -v sources/meta-altera/conf/machine/${ANGSTROM_MACH_BASELINE}.conf sources/meta-altera/conf/machine/socfpga.conf

if [ "${ANGSTROM_VER}" = "v2014.12" ]; then
    # JDS added because I read this --> http://en.wikipedia.org/wiki/User:WillWare/Angstrom_and_Beagleboard
    MACHINE=${ANGSTROM_MACH} bash ./oebb.sh update
fi

##############
#  ...and add a bunch more stuff as well.
#if [ ! -f "sources/meta-altera/conf/machine/include/socfpga.inc.orig" ]; then
#    cp sources/meta-altera/conf/machine/include/socfpga.inc sources/meta-altera/conf/machine/include/socfpga.inc.orig
#fi

##############
# Add support for memtool
if [ -d ~/doozynas/socfpga/memtool/meta-altera/recipes-devtools/memtool ]; then
    mkdir -p sources/meta-altera/recipes-devtools
    rm -rf sources/meta-altera/recipes-devtools/memtool
    cp -rvf ~/doozynas/socfpga/memtool/meta-altera/recipes-devtools/memtool sources/meta-altera/recipes-devtools/
fi

# http://www.gumstix.org/compile-code-on-my-gumstix.html#angstrom
#
#
# Add Python and Perl to default angstrom image [case:209303, case:210453]
# new packages
# task-native-sdk - oct 3 -- doesn't work anymore
# glibc-utils - oct3
# glibc-dev - oct3
# ncurses-dev - nov5
# ntpdate - nov5
# mosh - jan18
# mosh-server - jan18
# ethtool - feb10
# alsa-lib alsa-utils alsa-tools - feb11
# python-modules python-sqlite3 - feb11
# connman connman-client connman-tests connman-tools - feb 12
# screen tcpdump usbutils wireless-tools - feb12
# lttng-tools lttng-modules lttng-ust - Mar2
# memtool - mar17
# mtd-utils - april11
# i2c-tools - may 11
# gator - sept 8
# libgomp stuff - sept22 - https://community.freescale.com/thread/327612
# uuid for uefi - aug 22, 2016

# opencv stuff added on march 29 -- https://www.pathpartnertech.com/how-to-build-angstrom-linux-distribution-for-altera-soc-fpga-with-open-cv-camera-driver-support/

# tested
# strongswan - jan18 (just a test) --> works

TASK_NATIVE_SDK="gcc-symlinks g++-symlinks cpp cpp-symlinks binutils-symlinks \
make virtual-libc-dev perl-modules flex flex-dev bison gawk sed grep autoconf \
automake make patch diffstat diffutils libstdc++-dev libgcc libgcc-dev libstdc++ \
libstdc++-dev autoconf libgomp libgomp-dev libgomp-staticdev"

echo "IMAGE_INSTALL += \"bash python perl gator ${TASK_NATIVE_SDK} gdbserver glibc-utils glibc-dev gdb binutils \
gcc g++ make dtc ldd curl rsync initscripts tcf-agent vim nfs-utils nfs-utils-client sudo openssl iperf \
ncurses-dev ntpdate mosh mosh-server ethtool alsa-lib alsa-utils alsa-tools python-modules python-sqlite3 \
connman connman-client connman-tests connman-tools screen tcpdump usbutils wireless-tools lttng-tools \
lttng-modules lttng-ust mtd-utils i2c-tools sysfsutils pciutils net-tools \
opencv opencv-samples opencv-dev opencv-apps opencv-samples-dev \
oprofile uuid memtool\"" >> sources/meta-altera/conf/machine/socfpga.conf

# task-native-sdk
# task-proper-tools (not replaced)
# patchutils
# gcc-symlinks g++-symlinks cpp cpp-symlinks binutils-symlinks
# make virtual-libc-dev
# task-proper-tools perl-modules flex flex-dev bison gawk sed grep autoconf automake make
# patch patchutils diffstat diffutils libstdc++-dev
# libgcc libgcc-dev libstdc++ libstdc++-dev

#https://groups.google.com/forum/#!topic/beagleboard/HV02lnB3P5c
#
# packages that cause trouble
# git
# netperf - feb11 -- fails because it has a restricted license
#
# packages that just don't really work
# emacs

# packages that don't exist
# connman-init-systemd

# https://wiki.yoctoproject.org/wiki/Tracing_and_Profiling
# Don't strip symbols
#echo 'INHIBIT_PACKAGE_STRIP = "1"' >> sources/meta-altera/conf/machine/include/socfpga.inc

# Add debug features
#echo 'EXTRA_IMAGE_FEATURES = "debug-tweaks dbg-pkgs"' >> sources/meta-altera/conf/machine/include/socfpga.inc

# Aug 22, 2016 to fix sshd issue
echo 'EXTRA_IMAGE_FEATURES = "debug-tweaks"' >> sources/meta-altera/conf/machine/include/socfpga.inc


##############

# Fix Gator init.d [case:208846]
# sed -i -e 's,\(^[.][ \t]*/etc/init.d/functions.*\),if [ -f /etc/init.d/functions ]; then \1; fi,g' sources/meta-linaro/meta-linaro/recipes-kernel/gator/gator/gator.init

GATOR_GIT_TAG="$(wget -q -O - "https://git.linaro.org/?p=arm/ds5/gator.git" | grep '/arm/ds5/gator.git/commit/' | head -n1 | sed -e 's,.*/arm/ds5/gator.git/commit/\([0-9a-zA-Z]*\).*,\1,g' 2>/dev/null)"

#Old Gator Git tag for 5.19 I think...
#GATOR_GIT_TAG="ba783f1443773505231ac2808c9a3716c3c2f3ae"
#5.19.1
#GATOR_GIT_TAG="5e3cabe778188543611a71a59094292fb34c49df"

#echo "GATOR_GIT_TAG is ${GATOR_GIT_TAG}"
#if [ -z "${GATOR_GIT_TAG}" ]; then
#    echo "ERROR: GATOR_GIT_TAG not discovered"
#    exit 1
#fi

#sed -i -e "s,^SRCREV=.*,SRCREV=\"${GATOR_GIT_TAG}\"," sources/meta-altera/recipes-devtools/gator/gator_1.0.bb
if [ -f "sources/meta-linaro/meta-linaro/recipes-kernel/gator/gator_git.bb" ]; then
    sed -i -e "s,^SRCREV[ \t]*=.*,SRCREV = \"${GATOR_GIT_TAG}\"," sources/meta-linaro/meta-linaro/recipes-kernel/gator/gator_git.bb
fi

if [ -f "sources/meta-altera/recipes-devtools/gator/gator_1.0.bb" ]; then
    sed -i \
	-e 's,^SRCREV[ \t]*=.*,SRCREV = "${AUTOREV}",' \
	-e 's,git://git.linaro.org/git-ro/arm/ds5/gator.git;protocol=http,https://github.com/ARM-software/gator.git;protocol=https,g' \
	sources/meta-altera/recipes-devtools/gator/gator_1.0.bb
fi

#sed -i \
#    sources/meta-linaro/meta-linaro/recipes-kernel/gator/gator_git.bb
#     -e 's,^SRCREV[ \t]*=.*,SRCREV = "${AUTOREV}",' \
#     -e 's,git://git.linaro.org/arm/ds5/gator.git;protocol=http;branch=linaro,https://github.com/ARM-software/gator.git;protocol=https,g' \
#    -e 's,^PV[ \t]*=[ \t]*"5.*,,' \

# Looks like LICENSE file got renamed to COPYING... probably in a newer version of gator
find . -name 'gator*.bb' | xargs -n1 -i sed -i.orig -e 's,^\(LIC_FILES_CHKSUM[ \t]*=.*driver/\)LICENSE,\1COPYING,g' {} 


if [ "${ANGSTROM_VER}" = "v2014.12" ]; then
    # Fix connman boot from NFS issue
    # http://www.ptrackapp.com/apclassys-notes/embedded-linux-using-connma/
    # http://developer.toradex.com/software-resources/arm-family/linux/linux-booting
    #  fix it as documented in http://rocketboards.org/foswiki/Documentation/AngstromOnSoCFPGA_1 [case:209754]
    sed -i -e 's,\(sed -i.*ExecStart.*\)$,\1\n\tsed -i "s#\\(ExecStart=/usr/sbin/connmand -n\\)\\\$#\\1 -I eth0#" \${S}/src/connman.service,' sources/openembedded-core/meta/recipes-connectivity/connman/connman.inc
else
    #    sed -i.orig -e 's,\(sed -i.*ExecStart.*\)$,\1\n\tsed -i "s#\\(ExecStart=.*/connmand -n\\)\\\$#\\1 -I eth0#" \${S}/src/connman.service.in,' sources/openembedded-core/meta/recipes-connectivity/connman/connman.inc
    sed -i.orig -e 's,\(sed -i.*ExecStart.*\)$,\1\n\tsed -i "s#\\(ExecStart=.*/connmand -n\\)\\\$#\\1 -I eth0#" \${B}/src/connman.service,' sources/openembedded-core/meta/recipes-connectivity/connman/connman.inc
fi

# qspi boot on rocketboards says to add this
# require recipes-images/angstrom/console-image.bb

# 
# add soceds initramfs image
# core-image-minimal replaced with core-image-small, see:
#https://www.safaribooksonline.com/library/view/embedded-linux-projects/9781784395186/ch03s13.html
# initscripts removed - Nov 2
# connman connman-client - Nov 6th
# aug 16 swich from core-imaga-small.bb to core image-minimal-mtdutils.bb

mkdir -p sources/meta-altera/recipes-images/angstrom
cp -v ../core-image-small.bb sources/openembedded-core/meta/recipes-core/images
cat > sources/meta-altera/recipes-images/angstrom/soceds-initramfs.bb <<EOF
require recipes-core/images/core-image-minimal-mtdutils.bb

DESCRIPTION = "Small image suitable for initramfs boot."

IMAGE_INSTALL += "openssh gdbserver uuid mtd-utils gator connman connman-client"

ROOTFS_POSTPROCESS_COMMAND += "unset_root_password;"

unset_root_password() {
    sed -e 's%^root:[^:]*:%root::%' \\
        < \${IMAGE_ROOTFS}/etc/shadow \\
        > \${IMAGE_ROOTFS}/etc/shadow.new;\\
    mv \${IMAGE_ROOTFS}/etc/shadow.new \${IMAGE_ROOTFS}/etc/shadow ;
}

EOF

# could also do this to set password to root
# inherit extrausers
# EXTRA_USERS_PARAMS = "useradd -P root root;"

if [ "${ANGSTROM_VER}" = "v2014.12" ]; then
    #  2/ Setup the Shell Environment
    source environment-angstrom-${ANGSTROM_VER}
fi

#MACHINE=${ANGSTROM_MACH} bitbake -c clean virtual/kernel
#MACHINE=${ANGSTROM_MACH} bitbake virtual/kernel

if [ "${ENABLE_MTDUTILS_PATCH}" = "1" ]; then
    pushd sources/meta-altera
    git apply ../../../fb_381598_mtd_utils.patch
    popd
fi

MACHINE=${ANGSTROM_MACH} bitbake console-image

#MACHINE=${ANGSTROM_MACH} bitbake -c clean console-image
#MACHINE=${ANGSTROM_MACH} bitbake -c clean virtual/kernel
#rm -rf deploy/glibc/images/socfpga/README_-_DO_NOT_DELETE_FILES_IN_THIS_DIRECTORY.txt
#rm -rf deploy/glibc/images/socfpga/*.dtb

echo "[JDS] about to bitbake soceds-initramfs"

#MACHINE=${ANGSTROM_MACH} bitbake core-image-minimal

MACHINE=${ANGSTROM_MACH} bitbake soceds-initramfs

echo "[JDS] done bitbake soceds-initramfs"

#MACHINE=${ANGSTROM_MACH} bitbake -c clean soceds-initramfs
#MACHINE=${ANGSTROM_MACH} bitbake -c clean virtual/kernel

# this fails and we can't ignore yet
#MACHINE=${ANGSTROM_MACH} bitbake meta-toolchain meta-toolchain-sdk meta-ide-support || true

# this fails but we ignore
#MACHINE=${ANGSTROM_MACH} bitbake systemd-gnome-image || true

# kde-wallpapers-4.8.0.tar.bz2????
#MACHINE=${ANGSTROM_MACH} bitbake angstrom-kde-desktop-image

# Doesn't work
#MACHINE=${ANGSTROM_MACH} bitbake development-xfce-image


IMG=Angstrom-console-image
#IMG=Angstrom-core-image-minimal
#IMG=Angstrom-soceds-initramfs
#IMG=Angstrom-systemd-GNOME-image

ANGSTROM_IMAGE_DIR=deploy/glibc/images/${ANGSTROM_MACH}

cp -fv deploy/glibc/licenses/${ANGSTROM_MACH}/${IMG}-*/license.manifest angstrom-rootfs-license.manifest
cp -vf deploy/glibc/images/${ANGSTROM_MACH}/${IMG}-*.rootfs.tar.xz angstrom-rootfs.tar.xz
7z x angstrom-rootfs.tar.xz
tar --delete -f angstrom-rootfs.tar ./lib/modules || true

# this prevents opkg update from working see http://rocketboards.org/foswiki/Documentation/AngstromOnSoCFPGA_1
# there is another fb case on this
tar --delete -f angstrom-rootfs.tar ./etc/opkg/socfpga-feed.conf || true

# add lib/firmware dir
mkdir -p lib/firmware
tar --append -f angstrom-rootfs.tar lib/firmware
rmdir lib/firmware
rmdir lib

rm -rf angstrom-rootfs.tar.gz
gzip angstrom-rootfs.tar

mkdir -p ${ANGSTROM_PUBLISH_DIR}
rm -f ${ANGSTROM_PUBLISH_DIR}/angstrom-rootfs.tar.gz
cp -vf angstrom-rootfs.tar.gz ${ANGSTROM_PUBLISH_DIR}/angstrom-rootfs.tar.gz
cp -vf angstrom-rootfs-license.manifest ${ANGSTROM_PUBLISH_DIR}/angstrom-rootfs-license.manifest


IMG_MINIMAL=Angstrom-soceds-initramfs
cp -vf ${ANGSTROM_IMAGE_DIR}/${IMG_MINIMAL}-*.rootfs.tar.xz angstrom-minimal-rootfs.tar.xz
7z x angstrom-minimal-rootfs.tar.xz
tar --delete -f angstrom-minimal-rootfs.tar ./lib/modules || true
tar --delete -f angstrom-minimal-rootfs.tar ./etc/opkg/socfpga-feed.conf || true

mkdir -p lib/firmware
tar --append -f angstrom-minimal-rootfs.tar lib/firmware
rmdir lib/firmware
rmdir lib

rm -rf angstrom-minimal-rootfs.tar.gz
gzip angstrom-minimal-rootfs.tar
cp -vf angstrom-minimal-rootfs.tar.gz ${ANGSTROM_PUBLISH_DIR}/angstrom-minimal-rootfs.tar.gz

rm -rf mnt angstrom-minimal-rootfs.jffs2 angstrom-minimal-rootfs.without_sumtool.jffs2
mkdir -p mnt
pushd mnt
tar xzf ../angstrom-minimal-rootfs.tar.gz 
popd
mkfs.jffs2 --squash --root=mnt --pagesize=256 --eraseblock=64KiB --output=angstrom-minimal-rootfs.without_sumtool.jffs2 --little-endian --no-cleanmarkers
rm -rf mnt

sumtool --eraseblock=64KiB --littleendian --no-cleanmarkers -i angstrom-minimal-rootfs.without_sumtool.jffs2 -o angstrom-minimal-rootfs.jffs2

rm -f angstrom-minimal-rootfs.without_sumtool.jffs2

cp -vf angstrom-minimal-rootfs.jffs2 ${ANGSTROM_PUBLISH_DIR}/angstrom-minimal-rootfs.jffs2

popd

cp -vf ${THIS_SCRIPT} ${ANGSTROM_PUBLISH_DIR}
