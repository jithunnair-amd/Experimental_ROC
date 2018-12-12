#!/bin/bash
###############################################################################
# Copyright (c) 2018 Advanced Micro Devices, Inc.
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.
###############################################################################
BASE_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
set -e
trap 'lastcmd=$curcmd; curcmd=$BASH_COMMAND' DEBUG
trap 'errno=$?; print_cmd=$lastcmd; if [ $errno -ne 0 ]; then echo "\"${print_cmd}\" command failed with exit code $errno."; fi' EXIT
source "$BASE_DIR/common/common_options.sh"
parse_args "$@"

# Install pre-reqs. We might need build-essential if nobody ran the
# higher-level build scripts. Definitely need DKMS for the driver.
if [ ${ROCM_LOCAL_INSTALL} = false ] || [ ${ROCM_INSTALL_PREREQS} = true ]; then
    echo "Installing software required to build ROCK kernel driver."
    echo "You will need to have root privileges to do this."
    sudo apt -y install build-essential dkms git
    if [ ${ROCM_INSTALL_PREREQS} = true ] && [ ${ROCM_FORCE_GET_CODE} = false ]; then
        exit 0
    fi
fi

# Set up source-code directory
if [ $ROCM_SAVE_SOURCE = true ]; then
    SOURCE_DIR=${ROCM_SOURCE_DIR}/rock/
    if [ ${ROCM_FORCE_GET_CODE} = true ] && [ -d ${SOURCE_DIR} ]; then
        rm -rf ${SOURCE_DIR}
    fi
    mkdir -p ${SOURCE_DIR}
else
    SOURCE_DIR=`mktemp -d`
fi
cd ${SOURCE_DIR}
mkdir -p install_files/

# Download rocm-dkms source code
if [ ${ROCM_FORCE_GET_CODE} = true ] || [ ! -d ${SOURCE_DIR}/install_files/usr/ ]; then
    echo "Downloading ROCK kernel drivers."
    # One way to download this is to get the already-packaged DKMS and extract
    # the source code from it. Unlike the rest of the ROCm packages, the kernel
    # driver package actually includes the source code, since DKMS modules are
    # rebuilt every time the kernel is updated.
    #wget http://repo.radeon.com/rocm/apt/debian/pool/main/r/rock-dkms/rock-dkms_1.9-307_all.deb
    #ar x rock-dkms_1.9-307_all.deb
    #tar -xf data.tar.xz
    # However, this work below gets our source from github and "recreates" the
    # package. These build scripts carry some of the DKMS files with them
    # so you don't need to download the entire thing from repo.radeon.com
    cd ${SOURCE_DIR}/
    git clone --branch ${ROCM_VERSION_BRANCH} --single-branch --depth 1 https://github.com/RadeonOpenCompute/ROCK-Kernel-Driver.git
    cd ${SOURCE_DIR}/ROCK-Kernel-Driver
    git fetch --depth=1 origin "+refs/tags/${ROCM_VERSION_TAG}:refs/tags/${ROCM_VERSION_TAG}"
    git checkout tags/${ROCM_VERSION_TAG}

    cd ${SOURCE_DIR}/install_files/
    cp -R ${BASE_DIR}/rock_files/* ${SOURCE_DIR}/install_files/

    cd ${SOURCE_DIR}/install_files/usr/src/amdgpu-1.9-307/
    cp -R ${SOURCE_DIR}/ROCK-Kernel-Driver/drivers/gpu/drm/amd ${SOURCE_DIR}/install_files/usr/src/amdgpu-1.9-307/
    cp -R ${SOURCE_DIR}/ROCK-Kernel-Driver/drivers/gpu/drm/amd/dkms/docs ${SOURCE_DIR}/install_files/usr/src/amdgpu-1.9-307/
    cd ${SOURCE_DIR}/install_files/usr/src/amdgpu-1.9-307/
    tar -xJf ${SOURCE_DIR}/install_files/usr/src/amdgpu-1.9-307/firmware.tar.xz
    cd ${SOURCE_DIR}/install_files/
    mkdir -p ${SOURCE_DIR}/install_files/usr/src/amdgpu-1.9-307/include/drm/ttm
    for file in amd_rdma.h gpu_scheduler.h gpu_scheduler_trace.h spsc_queue.h; do
        cp ${SOURCE_DIR}/ROCK-Kernel-Driver/include/drm/${file} ${SOURCE_DIR}/install_files/usr/src/amdgpu-1.9-307/include/drm/
    done
    cp ${SOURCE_DIR}/ROCK-Kernel-Driver/include/drm/ttm/* ${SOURCE_DIR}/install_files/usr/src/amdgpu-1.9-307/include/drm/ttm/
    mkdir -p ${SOURCE_DIR}/install_files/usr/src/amdgpu-1.9-307/include/kcl
    cp ${SOURCE_DIR}/ROCK-Kernel-Driver/include/kcl/* ${SOURCE_DIR}/install_files/usr/src/amdgpu-1.9-307/include/kcl/
    mkdir -p ${SOURCE_DIR}/install_files/usr/src/amdgpu-1.9-307/include/uapi/drm
    cp ${SOURCE_DIR}/ROCK-Kernel-Driver/include/uapi/drm/amdgpu_drm.h ${SOURCE_DIR}/install_files/usr/src/amdgpu-1.9-307/include/uapi/drm/
    mkdir -p ${SOURCE_DIR}/install_files/usr/src/amdgpu-1.9-307/include/uapi/linux
    cp ${SOURCE_DIR}/ROCK-Kernel-Driver/include/uapi/linux/kfd_ioctl.h ${SOURCE_DIR}/install_files/usr/src/amdgpu-1.9-307/include/uapi/linux/
    mkdir -p ${SOURCE_DIR}/install_files/usr/src/amdgpu-1.9-307/radeon/
    cp ${SOURCE_DIR}/ROCK-Kernel-Driver/drivers/gpu/drm/radeon/cik_reg.h ${SOURCE_DIR}/install_files/usr/src/amdgpu-1.9-307/radeon/
    cp -R ${SOURCE_DIR}/ROCK-Kernel-Driver/drivers/gpu/drm/scheduler ${SOURCE_DIR}/install_files/usr/src/amdgpu-1.9-307/
    cp ${SOURCE_DIR}/install_files/usr/src/amdgpu-1.9-307/amd/dkms/sources ${SOURCE_DIR}/install_files/usr/src/amdgpu-1.9-307/
    cp -R ${SOURCE_DIR}/ROCK-Kernel-Driver/drivers/gpu/drm/ttm ${SOURCE_DIR}/install_files/usr/src/amdgpu-1.9-307/
else
    echo "Skipping download of ROCK kernel drivers, since ${SOURCE_DIR}/install_files/usr/ already exists."
fi

if [ ${ROCM_FORCE_GET_CODE} = true ]; then
    echo "Finished downloading ROCK kernel drivers. Exiting."
    exit 0
fi

if [ ${ROCM_FORCE_BUILD_ONLY} = true ]; then
    echo "Nothing to build for ROCK kernel driver unless you are installing. Exiting."
    exit 0
fi

if [ ${ROCM_FORCE_PACKAGE} = true ]; then
    cd ${SOURCE_DIR}/install_files/
    rm -rf ${SOURCE_DIR}/install_files/DEBIAN/
    pushd ${SOURCE_DIR}/install_files/
    find . -type f -printf '%P ' | xargs md5sum > ${SOURCE_DIR}/temp_md5sums
    popd
    mkdir -p ${SOURCE_DIR}/install_files/DEBIAN/
    cp ${SOURCE_DIR}/temp_md5sums ${SOURCE_DIR}/install_files/DEBIAN/md5sums
    for file in conffiles control postinst prerm; do
        cp ${BASE_DIR}/../common/deb_files/rock-${file} ${SOURCE_DIR}/install_files/DEBIAN/${file}
    done
    cd ${SOURCE_DIR}
    cp -R ./install_files ./rock-dkms_1.9-307_all
    dpkg-deb --build rock-dkms_1.9-307_all
    echo "Copying `ls -1 rock-dkms_*.deb` to ${ROCM_PACKAGE_DIR}"
    mkdir -p ${ROCM_PACKAGE_DIR}
    cp rock-dkms_*.deb ${ROCM_PACKAGE_DIR}
    if [ ${ROCM_LOCAL_INSTALL} = false ]; then
        ROCM_PKG_IS_INSTALLED=`dpkg -l rock-dkms | grep '^.i' | wc -l`
        if [ ${ROCM_PKG_IS_INSTALLED} -gt 0 ]; then
            PKG_NAME=`dpkg -l rock-dkms | grep '^.i' | awk '{print $2}'`
            sudo dpkg -r --force-depends ${PKG_NAME}
        fi
        sudo dpkg -i rock-dkms_*.deb
    fi
else
    if [ ${ROCM_LOCAL_INSTALL} = false ]; then
        ${ROCM_SUDO_COMMAND} cp -R ${SOURCE_DIR}/install_files/etc/* /etc/
        ${ROCM_SUDO_COMMAND} cp -R ${SOURCE_DIR}/install_files/usr/* /usr/
        CHECK_INSTALLED=`dkms status amdgpu/1.9-307 | grep installed | wc -l`
        CHECK_BUILT=`dkms status amdgpu/1.9-307 | grep built | wc -l`
        CHECK_ADDED=`dkms status amdgpu/1.9-307 | grep added | wc -l`
        if [ ${CHECK_INSTALLED} -gt 0 ] || [ ${CHECK_BUILT} -gt 0 ] || [ ${CHECK_ADDED} -gt 0 ]; then
            ${ROCM_SUDO_COMMAND} dkms remove amdgpu/1.9-307 --all
        fi
        ${ROCM_SUDO_COMMAND} dkms add amdgpu/1.9-307
        ${ROCM_SUDO_COMMAND} dkms build amdgpu/1.9-307
        ${ROCM_SUDO_COMMAND} dkms install amdgpu/1.9-307
    else
        echo "Skipping build and installation of ROCK drivers for local install."
    fi
fi

if [ $ROCM_SAVE_SOURCE = false ]; then
    rm -rf ${SOURCE_DIR}
fi