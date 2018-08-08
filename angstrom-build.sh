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
#ANGSTROM_VER=v2016.12
#ANGSTROM_VER=v2017.06
ANGSTROM_VER=v2017.12
#ANGSTROM_VER=v2018.06

# https://wiki.yoctoproject.org/wiki/Releases

LAYERS_SUBDIR=layers 
if [ "${ANGSTROM_VER}" = "v2014.12" ]; then
    # does not work with host gcc 5.*
    ANGSTROM_BASE_DIR=setup-scripts
    YOCTO_VER=yocto1.7
    LAYERS_SUBDIR=sources
    echo "DEPRECATED"; exit 1
elif [ "${ANGSTROM_VER}" = "v2015.12" ]; then
    ANGSTROM_BASE_DIR=angstrom-manifest
    YOCTO_VER=yocto2.0
    LAYERS_SUBDIR=sources
    YOCTO_CORE_PROJECT_NAME=jethro
    echo "DEPRECATED"; exit 1
elif [ "${ANGSTROM_VER}" = "v2016.12" ]; then
    ANGSTROM_BASE_DIR=angstrom-manifest
    YOCTO_VER=yocto2.2
    YOCTO_CORE_PROJECT_NAME=morty
    echo "DEPRECATED"; exit 1
elif [ "${ANGSTROM_VER}" = "v2017.06" ]; then
    ANGSTROM_BASE_DIR=angstrom-manifest
    YOCTO_VER=yocto2.3
    YOCTO_CORE_PROJECT_NAME=pyro
    echo "DEPRECATED"; exit 1
elif [ "${ANGSTROM_VER}" = "v2017.12" ]; then
    ANGSTROM_BASE_DIR=angstrom-manifest
    YOCTO_VER=yocto2.4
    YOCTO_CORE_PROJECT_NAME=rocko
elif [ "${ANGSTROM_VER}" = "v2018.06" ]; then
    ANGSTROM_BASE_DIR=angstrom-manifest
    YOCTO_VER=yocto2.5
    YOCTO_CORE_PROJECT_NAME=sumo
else
    echo "ERROR: unsupported angstrom version"
    exit 1
fi

#ENABLE_MTDUTILS_PATCH=$[$(date +%j)%2]
#ENABLE_MTDUTILS_PATCH=1
ENABLE_MTDUTILS_PATCH=0

ENABLE_KRAJ=1

#ENABLE_S10=${ENABLE_S10-1}
ENABLE_S10=${ENABLE_S10-0}

#FORCE=${FORCE-1}
FORCE=${FORCE-0}

ANGSTROM_TOP=$(pwd -P)/${ANGSTROM_BASE_DIR}
ANGSTROM_PUBLISH_DIR=${HOME}/doozynas/www/angstrom/${ANGSTROM_VER}


if [ "${ENABLE_S10}" == "1" ]; then
    ANGSTROM_MACH=stratix10
    ANGSTROM_MACH_BASELINE=stratix10
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
fi

mkdir -p ${ANGSTROM_TOP}
pushd ${ANGSTROM_TOP}


if [ ! -d repo ]; then	
    git clone https://android.googlesource.com/tools/repo
fi
export PATH=$(pwd)/repo:${PATH}

repo init -u git://github.com/Angstrom-distribution/angstrom-manifest -b angstrom-${ANGSTROM_VER}-${YOCTO_CORE_PROJECT_NAME}

if [ "${ENABLE_KRAJ}" = "1" ]; then
    sed -i.orig \
	-e 's,\(<project[ \t]name="kraj/meta-altera"[ \t].*revision=\).*>,\1"__YOCTO_CORE_PROJECT_NAME__"/>,g' \
	-e "s,__YOCTO_CORE_PROJECT_NAME__,${YOCTO_CORE_PROJECT_NAME},g" \
	.repo/manifest.xml
fi
repo sync
MACHINE=${ANGSTROM_MACH} source setup-environment


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
#APPLY_CONNMAN_PATCH=1
if [ "${APPLY_CONNMAN_PATCH}" = "1" ]; then
    # see https://gerrit.automotivelinux.org/gerrit/#/c/5545/
    mkdir -p ${LAYERS_SUBDIR}/meta-altera/recipes-connectivity
    rm -rf ${LAYERS_SUBDIR}/meta-altera/recipes-connectivity/connman
    cp -rvf ${THIS_DIR}/connman/meta-altera/recipes-connectivity/connman ${LAYERS_SUBDIR}/meta-altera/recipes-connectivity/
fi

##############
# Add support for memtool
#if [ -d ~/doozynas/socfpga/memtool/meta-altera/recipes-devtools/memtool ]; then
#    HAVE_MEMTOOL=1
#    mkdir -p ${LAYERS_SUBDIR}/meta-altera/recipes-devtools
#    rm -rf ${LAYERS_SUBDIR}/meta-altera/recipes-devtools/memtool
#    cp -rvf ~/doozynas/socfpga/memtool/meta-altera/recipes-devtools/memtool ${LAYERS_SUBDIR}/meta-altera/recipes-devtools/
#fi

TASK_NATIVE_SDK="gcc-symlinks g++-symlinks cpp cpp-symlinks binutils-symlinks \
make virtual-libc-dev perl-modules flex flex-dev bison gawk sed grep autoconf \
automake make patch diffstat diffutils libstdc++-dev libgcc libgcc-dev libstdc++ \
libstdc++-dev autoconf libgomp libgomp-dev libgomp-staticdev"

PYTHON_PACKAGES="python python-modules python-sqlite3"

BUILD_PACKAGES="${PYTHON_PACKAGES} bash perl gdbserver glibc-utils \
glibc-dev gdb binutils gcc g++ make dtc ldd curl rsync vim"

CONNMAN_PACKAGES="connman connman-client connman-tests connman-tools"

# These packages were removed because they fail with a protobuf fetch issue:
#OPENCV_PACKAGES="opencv opencv-dev opencv-apps"

# This package removed becasue it had a strange warning and
# may be causing strange behaviour:
# oprofile

#removing alsa because 2017.06 doesn't seem to have alsa-lib package
#ALSA_PACKAGES="alsa-lib alsa-utils alsa-tools"

LTTNG_PACKAGES="lttng-tools lttng-modules lttng-ust"

EXTRA_PACKAGES="${TASK_NATIVE_SDK} ${BUILD_PACKAGES} ${CONNMAN_PACKAGES} \
initscripts tcf-agent nfs-utils nfs-utils-client sudo openssl ncurses-dev \
ntpdate ethtool screen tcpdump usbutils wireless-tools \
${ALSA_PACKAGES} ${LTTNG_PACKAGES} \
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


mkdir -p ${LAYERS_SUBDIR}/meta-altera/recipes-images/angstrom
cp -v ../core-image-small.bb ${LAYERS_SUBDIR}/openembedded-core/meta/recipes-core/images
cat > ${LAYERS_SUBDIR}/meta-altera/recipes-images/angstrom/soceds-initramfs.bb <<EOF
require recipes-core/images/core-image-minimal-mtdutils.bb

DESCRIPTION = "Small image suitable for initramfs boot."

IMAGE_INSTALL += "openssh gdbserver uuid mtd-utils connman connman-client"

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

export KBRANCH=socfpga-4.9.78-ltsi
export LINUX_VERSION=4.9.78
export KERNEL_PROVIDER=linux-altera-ltsi

MACHINE=${ANGSTROM_MACH} bitbake console-image

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
