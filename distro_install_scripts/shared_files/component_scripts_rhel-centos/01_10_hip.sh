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
source scl_source enable devtoolset-7
BASE_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
set -e
trap 'lastcmd=$curcmd; curcmd=$BASH_COMMAND' DEBUG
trap 'errno=$?; print_cmd=$lastcmd; if [ $errno -ne 0 ]; then echo "\"${print_cmd}\" command failed with exit code $errno."; fi' EXIT
source "$BASE_DIR/common/common_options.sh"
parse_args "$@"

# Install pre-reqs. We might need cmake and git if nobody ran the higher-level
# build scripts. Also libelf is needed for HIP. wget needed in order to get the
# updated version of cmake.
if [ ${ROCM_LOCAL_INSTALL} = false ] || [ ${ROCM_INSTALL_PREREQS} = true ]; then
    echo "Installing software required to build HIP."
    echo "You will need to have root privileges to do this."
    sudo yum -y install cmake pkgconfig git elfutils-libelf wget patch rpm-build
    if [ ${ROCM_INSTALL_PREREQS} = true ] && [ ${ROCM_FORCE_GET_CODE} = false ]; then
        exit 0
    fi
fi
# If we are going to build this as a package and then try to install it, then
# we need to install the things it relies on or the rpm installation will fail
if [ ${ROCM_LOCAL_INSTALL} = false ] && [ ${ROCM_FORCE_PACKAGE} = true ]; then
    sudo yum -y install perl
fi

# Set up source-code directory
if [ $ROCM_SAVE_SOURCE = true ]; then
    SOURCE_DIR=${ROCM_SOURCE_DIR}
    if [ ${ROCM_FORCE_GET_CODE} = true ] && [ -d ${SOURCE_DIR}/HIP ]; then
        rm -rf ${SOURCE_DIR}/HIP
    fi
    mkdir -p ${SOURCE_DIR}
else
    SOURCE_DIR=`mktemp -d`
fi
cd ${SOURCE_DIR}

# Download HIP
if [ ${ROCM_FORCE_GET_CODE} = true ] || [ ! -d ${SOURCE_DIR}/HIP ]; then
    # We require a new version of cmake to build HIP on CentOS, so get it here.
    source "$BASE_DIR/common/get_updated_cmake.sh"
    get_cmake "${SOURCE_DIR}"
    git clone -b ${ROCM_VERSION_BRANCH} https://github.com/ROCm-Developer-Tools/HIP.git
    cd HIP
    git checkout tags/${ROCM_VERSION_TAG}
    patch -p1 < ${BASE_DIR}/patches/01_10_hip.patch
else
    echo "Skipping download of HIP, since ${SOURCE_DIR}/HIP already exists."
fi

if [ ${ROCM_FORCE_GET_CODE} = true ]; then
    echo "Finished downloading HIP. Exiting."
    exit 0
fi

cd ${SOURCE_DIR}/HIP
mkdir -p build
cd build
${SOURCE_DIR}/cmake/bin/cmake .. -DHIP_PLATFORM=hcc -DHCC_HOME=${ROCM_INPUT_DIR}/hcc/ -DHSA_PATH=${ROCM_INPUT_DIR} -DCMAKE_BUILD_TYPE=${ROCM_CMAKE_BUILD_TYPE} -DCMAKE_INSTALL_PREFIX=${ROCM_OUTPUT_DIR}/hip/ -DCPACK_PACKAGING_INSTALL_PREFIX=${ROCM_OUTPUT_DIR}/ -DCPACK_GENERATOR=RPM ${ROCM_CPACK_RPM_PERMISSIONS}
make -j `nproc`

if [ ${ROCM_FORCE_BUILD_ONLY} = true ]; then
    echo "Finished building HIP. Exiting."
    exit 0
fi

if [ ${ROCM_FORCE_PACKAGE} = true ]; then
    make package
    for pkg in base doc hcc samples; do
        echo "Copying `ls -1 hip_${pkg}-*.rpm` to ${ROCM_PACKAGE_DIR}"
        mkdir -p ${ROCM_PACKAGE_DIR}
        cp ./hip_${pkg}-*.rpm ${ROCM_PACKAGE_DIR}
    done
    if [ ${ROCM_LOCAL_INSTALL} = false ]; then
        for pkg in base doc hcc samples; do
            ROCM_PKG_IS_INSTALLED=`rpm -qa | grep hip_${pkg} | wc -l`
            if [ ${ROCM_PKG_IS_INSTALLED} -gt 0 ]; then
                PKG_NAME=`rpm -qa | grep hip_${pkg} | head -n 1`
                sudo rpm -e --nodeps ${PKG_NAME}
            fi
        done
        for pkg in base doc hcc samples; do
            sudo rpm -i ./hip_${pkg}-*.rpm
        done
    fi
else
    ${ROCM_SUDO_COMMAND} make install

    # Fix up files into the locations they s/hcc/hould be installed into
    ${ROCM_SUDO_COMMAND} mkdir -p ${ROCM_OUTPUT_DIR}/bin/
    ${ROCM_SUDO_COMMAND} bash -c 'for i in .hipVersion ca findcode.sh finduncodep.sh hipcc hipcc_cmake_linker_helper hipconfig hipconvertinplace-perl.sh hipconvertinplace.sh hipdemangleatp hipexamine-perl.sh hipexamine.sh hipify-cmakefile hipify-perl lpl; do ln -sf '"${ROCM_OUTPUT_DIR}"'/hip/bin/${i} '"${ROCM_OUTPUT_DIR}"'/bin/${i}; done'
    ${ROCM_SUDO_COMMAND} ln -sf ${ROCM_OUTPUT_DIR}/hip/bin/.hipVersion ${ROCM_OUTPUT_DIR}/bin/.hipVersion
    ${ROCM_SUDO_COMMAND} mkdir -p ${ROCM_OUTPUT_DIR}/include/
    if [ ! -d  ${ROCM_OUTPUT_DIR}/include/hip ]; then
        ${ROCM_SUDO_COMMAND} ln -sf ${ROCM_OUTPUT_DIR}/hip/include/hip ${ROCM_OUTPUT_DIR}/include/hip
    fi
    ${ROCM_SUDO_COMMAND} mkdir -p ${ROCM_OUTPUT_DIR}/lib/
    ${ROCM_SUDO_COMMAND} bash -c 'for i in .hipInfo hip_hc.ll libhip_device.a libhip_hcc.so libhip_hcc_static.a; do ln -sf '"${ROCM_OUTPUT_DIR}"'/hip/lib/${i} '"${ROCM_OUTPUT_DIR}"'/lib/${i}; done'
    ${ROCM_SUDO_COMMAND} mkdir -p ${ROCM_OUTPUT_DIR}/hip/lib/cmake/hip/
    sed -i 's#/opt/rocm/#'${ROCM_OUTPUT_DIR}/'#' ${SOURCE_DIR}/HIP/packaging/hip-targets.cmake
    sed -i 's#/opt/rocm/#'${ROCM_OUTPUT_DIR}/'#' ${SOURCE_DIR}/HIP/packaging/hip-targets-release.cmake
    ${ROCM_SUDO_COMMAND} cp -f ${SOURCE_DIR}/HIP/packaging/*.cmake ${ROCM_OUTPUT_DIR}/hip/lib/cmake/hip/

    # hip_samples packages:
    ${ROCM_SUDO_COMMAND} cp -R ${SOURCE_DIR}/HIP/samples ${ROCM_OUTPUT_DIR}/hip/
fi

if [ $ROCM_SAVE_SOURCE = false ]; then
    rm -rf ${SOURCE_DIR}
fi
