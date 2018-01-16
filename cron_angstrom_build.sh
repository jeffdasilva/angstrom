#!/bin/bash -e

#########################################################
# Init & Sanity Checks

THIS_DIR=$(cd "$(dirname "${0}")" && echo "$(pwd 2>/dev/null)")
THIS_SCRIPT=$(basename ${0})
THIS_SCRIPT_SDUG=$(echo ${THIS_SCRIPT} | sed -e 's,[.],_,g' -e 's,__,_,g')

ANGSTROM_SH=${THIS_DIR}/angstrom-build.sh

if [ ! -f "${ANGSTROM_SH}" ]; then
    echo "ERROR: ${ANGSTROM_SH} does not exist" 1>&2
    exit
fi

LOGDIR=${THIS_DIR}/log
mkdir -p ${LOGDIR}
mkdir -p ${LOGDIR}/archive/$(date +%Y)
mv ${LOGDIR}/*.log ${LOGDIR}/archive/$(date +%Y) || true

LOGFILE=${LOGDIR}/${THIS_SCRIPT_SDUG}_$(date +%m%d%y_%H%M%S).log

cd ${THIS_DIR}
#########################################################


#########################################################
# Get LOCK File
LOCKFILE=/tmp/${THIS_SCRIPT_SDUG}.lock

mkdir ${LOCKFILE} 2>/dev/null || {
    echo "ERROR: Angstrom Script already running" 1>&2
    exit
}
SIGS=$(seq 0 34)
trap "rmdir ${LOCKFILE}" ${SIGS}
#########################################################


exec 6>&1           # Link file descriptor #6 with stdout.
                    # Saves stdout.

exec > ${LOGFILE}   # stdout replaced with file logfile

date
echo "Angstrom Build Start: $(date)" > ~/angstrom_build.log

echo "About to run \"${ANGSTROM_SH}\""
sleep 5

FORCE=1 ENABLE_S10=0 ${ANGSTROM_SH} 2>&1
FORCE=0 ENABLE_S10=1 ${ANGSTROM_SH} 2>&1

date
echo "Angstrom Build End: $(date)" >> ~/angstrom_build.log

echo DONE

exec 1>&6 6>&-      # Restore stdout and close file descriptor #6
