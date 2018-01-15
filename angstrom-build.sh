#!/bin/bash -e

# prerequisites
# sudo apt-get install gawk texinfo chrpath git g++ repo p7zip-full mtd-utils

THIS_DIR=$(cd "$(dirname "${0}")" && echo "$(pwd 2>/dev/null)")
THIS_SCRIPT=$(basename ${0})

# baseline your PATH (doesn't actually make a difference)
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

####
# Instructions scripted are found here:
# see http://rocketboards.org/foswiki/Documentation/AngstromOnSoCFPGA_1
####

#ANGSTROM_VER=v2014.12
#ANGSTROM_VER=v2015.12
ANGSTROM_VER=v2016.12
#ANGSTROM_VER=v2017.06

# https://wiki.yoctoproject.org/wiki/Releases

LAYERS_SUBDIR=layers 
if [ "${ANGSTROM_VER}" = "v2014.12" ]; then
    # does not work with host gcc 5.*
    ANGSTROM_BASE_DIR=setup-scripts
    YOCTO_VER=yocto1.7
    LAYERS_SUBDIR=sources
elif [ "${ANGSTROM_VER}" = "v2015.12" ]; then
    ANGSTROM_BASE_DIR=angstrom-manifest
    YOCTO_VER=yocto2.0
    LAYERS_SUBDIR=sources
    YOCTO_CORE_PROJECT_NAME=jethro
elif [ "${ANGSTROM_VER}" = "v2016.12" ]; then
    ANGSTROM_BASE_DIR=angstrom-manifest
    YOCTO_VER=yocto2.2
    YOCTO_CORE_PROJECT_NAME=morty
elif [ "${ANGSTROM_VER}" = "v2017.06" ]; then
    ANGSTROM_BASE_DIR=angstrom-manifest
    YOCTO_VER=yocto2.3
    YOCTO_CORE_PROJECT_NAME=pyro
else
    echo "ERROR: unsupported angstrom version"
    exit 1
fi

#ENABLE_MTDUTILS_PATCH=$[$(date +%j)%2]
#ENABLE_MTDUTILS_PATCH=1
ENABLE_MTDUTILS_PATCH=0

ENABLE_KRAJ=1

ENABLE_S10=${ENABLE_S10-1}
#ENABLE_S10=${ENABLE_S10-0}

FORCE=${FORCE-1}
#FORCE=${FORCE-0}

ANGSTROM_TOP=$(pwd -P)/${ANGSTROM_BASE_DIR}
ANGSTROM_PUBLISH_DIR=${HOME}/doozynas/www/angstrom/${ANGSTROM_VER}

if [ "${ENABLE_S10}" == "1" ]; then
    ANGSTROM_MACH=stratix10swvp
    ANGSTROM_MACH_BASELINE=stratix10swvp
    ANGSTROM_PUBLISH_DIR=${ANGSTROM_PUBLISH_DIR}/s10
else
    ANGSTROM_MACH=socfpga
    ANGSTROM_MACH_BASELINE=cyclone5
fi

if [ "${ENABLE_MTDUTILS_PATCH}" = "1" ]; then
    ANGSTROM_PUBLISH_DIR=${ANGSTROM_PUBLISH_DIR}.patched
fi

if [ -f "${ANGSTROM_PUBLISH_DIR}/${THIS_SCRIPT}" ]; then
    diff ${ANGSTROM_PUBLISH_DIR}/${THIS_SCRIPT} ${THIS_DIR}/${THIS_SCRIPT} || true
fi 

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
    
	if [ -z "$(grep 'meta-altera' ${LAYERS_SUBDIR}/layers.txt 2>/dev/null)" ]; then
	    echo "meta-altera,https://github.com/altera-opensource/meta-altera.git,angstrom-${ANGSTROM_VER}-${YOCTO_VER},HEAD" >> ${LAYERS_SUBDIR}/layers.txt
	    echo "meta-altera-refdes,https://github.com/altera-opensource/meta-altera-refdes.git,master,HEAD" >> ${LAYERS_SUBDIR}/layers.txt
	fi

	if [ -z "$(grep 'meta-altera' conf/bblayers.conf 2>/dev/null)" ]; then
	    echo >> conf/bblayers.conf
	    echo 'BASELAYERS += "${TOPDIR}/${LAYERS_SUBDIR}/meta-altera"' >> conf/bblayers.conf
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

    if [ ! -d repo ]; then	
	git clone https://android.googlesource.com/tools/repo
    fi
    export PATH=$(pwd)/repo:${PATH}
    
    repo init -u git://github.com/Angstrom-distribution/angstrom-manifest -b angstrom-${ANGSTROM_VER}-${YOCTO_VER}
    if [ "${ENABLE_KRAJ}" = "1" ]; then
	sed -i.orig \
	    -e 's,\(<project[ \t]name="kraj/meta-altera"[ \t].*revision=\).*>,\1"__YOCTO_CORE_PROJECT_NAME__"/>,g' \
	    -e "s,__YOCTO_CORE_PROJECT_NAME__,${YOCTO_CORE_PROJECT_NAME},g" \
	    .repo/manifest.xml
    fi
    repo sync
    MACHINE=${ANGSTROM_MACH} source setup-environment
fi

if [ "${ANGSTROM_MACH}" != "${ANGSTROM_MACH_BASELINE}" ]; then
    # Case:241717
    rm -f ${LAYERS_SUBDIR}/meta-altera/conf/machine/${ANGSTROM_MACH}.conf
    cp -v ${LAYERS_SUBDIR}/meta-altera/conf/machine/${ANGSTROM_MACH_BASELINE}.conf ${LAYERS_SUBDIR}/meta-altera/conf/machine/${ANGSTROM_MACH}.conf
fi

if [ "${ANGSTROM_VER}" = "v2014.12" ]; then
    # JDS added because I read this --> http://en.wikipedia.org/wiki/User:WillWare/Angstrom_and_Beagleboard
    MACHINE=${ANGSTROM_MACH} bash ./oebb.sh update
fi

##############
#  ...and add a bunch more stuff as well.
#if [ ! -f "${LAYERS_SUBDIR}/meta-altera/conf/machine/include/socfpga.inc.orig" ]; then
#    cp ${LAYERS_SUBDIR}/meta-altera/conf/machine/include/socfpga.inc ${LAYERS_SUBDIR}/meta-altera/conf/machine/include/socfpga.inc.orig
#fi

##############
# Add support for memtool
if [ -d ~/doozynas/socfpga/memtool/meta-altera/recipes-devtools/memtool ]; then
    HAVE_MEMTOOL=1
    mkdir -p ${LAYERS_SUBDIR}/meta-altera/recipes-devtools
    rm -rf ${LAYERS_SUBDIR}/meta-altera/recipes-devtools/memtool
    cp -rvf ~/doozynas/socfpga/memtool/meta-altera/recipes-devtools/memtool ${LAYERS_SUBDIR}/meta-altera/recipes-devtools/
fi

# http://www.gumstix.org/compile-code-on-my-gumstix.html#angstrom
#
# Add Python and Perl to default angstrom image [case:209303, case:210453]
# new packages
# task-native-sdk - oct 3 -- doesn't work anymore
# glibc-utils - oct3
# glibc-dev - oct3
# ncurses-dev - nov5
# ntpdate - nov5
# mosh - jan18 - removed 12/19/2017
# mosh-server - jan18 - removed 12/19/2017
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
# devmem2 - mar 20, 2017
# opencv stuff added on mar 29, 2017
# iperf removed - 12/3/2017

TASK_NATIVE_SDK="gcc-symlinks g++-symlinks cpp cpp-symlinks binutils-symlinks \
make virtual-libc-dev perl-modules flex flex-dev bison gawk sed grep autoconf \
automake make patch diffstat diffutils libstdc++-dev libgcc libgcc-dev libstdc++ \
libstdc++-dev autoconf libgomp libgomp-dev libgomp-staticdev"

PYTHON_PACKAGES="python python-modules python-sqlite3"

BUILD_PACKAGES="${PYTHON_PACKAGES} bash perl gator gdbserver glibc-utils \
glibc-dev gdb binutils gcc g++ make dtc ldd curl rsync vim"

#CONNMAN_PACKAGES="connman connman-client connman-tests connman-tools"

# These packages were removed because they fail with a protobuf fetch issue:
#OPENCV_PACKAGES="opencv opencv-dev opencv-apps"

# This package removed becasue it had a strange warning and
# may be causing strange behaviour:
# oprofile

ALSA_PACKAGES="alsa-lib alsa-utils alsa-tools"

LTTNG_PACKAGES="lttng-tools lttng-modules lttng-ust"

EXTRA_PACKAGES="${TASK_NATIVE_SDK} ${BUILD_PACKAGES} initscripts tcf-agent \
nfs-utils nfs-utils-client sudo openssl ncurses-dev ntpdate ethtool \
screen tcpdump usbutils wireless-tools ${ALSA_PACKAGES} ${LTTNG_PACKAGES} \
mtd-utils i2c-tools sysfsutils pciutils net-tools"

EXTRA_PACKAGES="${EXTRA_PACKAGES} uuid devmem2"

if [ "${HAVE_MEMTOOL}" == "1" ]; then
    EXTRA_PACKAGES="${EXTRA_PACKAGES} memtool"
fi

ADD_EXTRA_PACKAGES=1

if [ "${ADD_EXTRA_PACKAGES}" == "1" ]; then
    echo "IMAGE_INSTALL += \"${EXTRA_PACKAGES}\""  >> ${LAYERS_SUBDIR}/meta-altera/conf/machine/${ANGSTROM_MACH}.conf
fi

# https://wiki.yoctoproject.org/wiki/Tracing_and_Profiling
# Don't strip symbols
#echo 'INHIBIT_PACKAGE_STRIP = "1"' >> ${LAYERS_SUBDIR}/meta-altera/conf/machine/include/socfpga.inc

# Add debug features
#echo 'EXTRA_IMAGE_FEATURES = "debug-tweaks dbg-pkgs"' >> ${LAYERS_SUBDIR}/meta-altera/conf/machine/include/socfpga.inc

# Aug 22, 2016 to fix sshd issue
# Sept 13, 2016 allow-empty-password added

if [ "${ENABLE_S10}" = "1" ]; then
    echo 'EXTRA_IMAGE_FEATURES = "allow-empty-password debug-tweaks"' >> ${LAYERS_SUBDIR}/meta-altera/conf/machine/${ANGSTROM_MACH}.conf
else
    echo 'EXTRA_IMAGE_FEATURES = "allow-empty-password debug-tweaks"' >> ${LAYERS_SUBDIR}/meta-altera/conf/machine/include/socfpga.inc
fi

##############

if [ "${ANGSTROM_VER}" = "v2014.12" ]; then
    # Fix connman boot from NFS issue
    # http://www.ptrackapp.com/apclassys-notes/embedded-linux-using-connma/
    # http://developer.toradex.com/software-re${LAYERS_SUBDIR}/arm-family/linux/linux-booting
    #  fix it as documented in http://rocketboards.org/foswiki/Documentation/AngstromOnSoCFPGA_1 [case:209754]
    sed -i -e 's,\(sed -i.*ExecStart.*\)$,\1\n\tsed -i "s#\\(ExecStart=/usr/sbin/connmand -n\\)\\\$#\\1 -I eth0#" \${S}/src/connman.service,' ${LAYERS_SUBDIR}/openembedded-core/meta/recipes-connectivity/connman/connman.inc
else
    #    sed -i.orig -e 's,\(sed -i.*ExecStart.*\)$,\1\n\tsed -i "s#\\(ExecStart=.*/connmand -n\\)\\\$#\\1 -I eth0#" \${S}/src/connman.service.in,' ${LAYERS_SUBDIR}/openembedded-core/meta/recipes-connectivity/connman/connman.inc
    #sed -i.orig -e 's,\(sed -i.*ExecStart.*\)$,\1\n\tsed -i "s#\\(ExecStart=.*/connmand -n\\)\\\$#\\1 -I eth0#" \${B}/src/connman.service,' ${LAYERS_SUBDIR}/openembedded-core/meta/recipes-connectivity/connman/connman.inc

    # as documented in [case:404248]
    sed -i.orig -e 's,\(sed -i.*ExecStart.*\)$,\1\n\tsed -i "s#\\(Wants=network.target.*\\)\\\$#\\1\\nConditionKernelCommandLine=!root=/dev/nfs#" \${B}/src/connman.service,' ${LAYERS_SUBDIR}/openembedded-core/meta/recipes-connectivity/connman/connman.inc

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

mkdir -p ${LAYERS_SUBDIR}/meta-altera/recipes-images/angstrom
cp -v ../core-image-small.bb ${LAYERS_SUBDIR}/openembedded-core/meta/recipes-core/images
cat > ${LAYERS_SUBDIR}/meta-altera/recipes-images/angstrom/soceds-initramfs.bb <<EOF
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

EXTRA_IMAGE_FEATURES += "allow-empty-password"

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
    pushd ${LAYERS_SUBDIR}/meta-altera
    git apply ../../../fb_381598_mtd_utils.patch
    popd
fi

export KBRANCH=socfpga-4.1.33-ltsi
#export KBRANCH=socfpga-4.9.51-ltsi
export KERNEL_PROVIDER=linux-altera-ltsi

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
tar --delete -f angstrom-rootfs.tar ./lib/modules 2>/dev/null || true

# this prevents opkg update from working see http://rocketboards.org/foswiki/Documentation/AngstromOnSoCFPGA_1
# there is another fb case on this
tar --delete -f angstrom-rootfs.tar ./etc/opkg/socfpga-feed.conf 2>/dev/null || true

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
tar --delete -f angstrom-minimal-rootfs.tar ./lib/modules 2>/dev/null || true
tar --delete -f angstrom-minimal-rootfs.tar ./etc/opkg/socfpga-feed.conf 2>/dev/null || true

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
