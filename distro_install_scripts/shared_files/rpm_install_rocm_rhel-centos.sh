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

echo "Preparing to set up ROCm requirements. You must be root/sudo for this."
sudo yum install -y epel-release
sudo yum install -y dkms kernel-headers-`uname -r` kernel-devel-`uname -r`
sudo sh -c "echo [ROCm] > /etc/yum.repos.d/rocm.repo"
sudo sh -c "echo name=ROCm >> /etc/yum.repos.d/rocm.repo"
sudo sh -c "echo baseurl=http://repo.radeon.com/rocm/yum/rpm >> /etc/yum.repos.d/rocm.repo"
sudo sh -c "echo enabled=1 >> /etc/yum.repos.d/rocm.repo"
sudo sh -c "echo gpgcheck=0 >> /etc/yum.repos.d/rocm.repo"

OS_VERSION_NUM=`cat /etc/redhat-release | sed -rn 's/[^0-9]*([0-9]+\.*[0-9]*).*/\1/p'`
OS_VERSION_MAJOR=`echo ${OS_VERSION_NUM} | awk -F"." '{print $1}'`
OS_VERSION_MINOR=`echo ${OS_VERSION_NUM} | awk -F"." '{print $2}'`
if [ ${OS_VERSION_MAJOR} -ne 7 ]; then
    echo "Attempting to run on an unsupported OS version: ${OS_VERSION_MAJOR}"
    exit 1
fi
if [ ${OS_VERSION_MINOR} -eq 4 ] || [ ${OS_VERSION_MINOR} -eq 5 ] || [ ${OS_VERSION_MINOR} -eq 6 ]; then
    # On older versions of CentOS/RHEL 7, we should install the DKMS kernel module
    # as well as all of the user-level utilities
    sudo yum install -y rocm-dkms rocm-cmake atmi rocm_bandwidth_test
else
    echo "Attempting to run on an unsupported OS version: ${OS_VERSION_NUM}"
    exit 1
fi

# Detect if you are actually logged into the system or not.
# Containers, for instance, may not have you as a user with
# a meaningful value for logname
num_users=`who am i | wc -l`
if [ ${num_users} -gt 0 ]; then
    sudo usermod -a -G video `logname`
else
    echo ""
    echo "Was going to attempt to add your user to the 'video' group."
    echo "However, it appears that we cannot determine your username."
    echo "Perhaps you are running inside a container?"
    echo ""
fi

if [ ${ROCM_FORCE_YES} = true ]; then
    ROCM_RUN_NEXT_SCRIPT=true
elif [ ${ROCM_FORCE_NO} = true ]; then
    ROCM_RUN_NEXT_SCRIPT=false
else
    echo ""
    echo "The next script will set up users on the system to have GPU access."
    read -p "Do you want to automatically run the next script now? (y/n)? " answer
    case ${answer:0:1} in
        y|Y )
            ROCM_RUN_NEXT_SCRIPT=true
            echo 'User chose "yes". Running next setup script.'
        ;;
        * )
            echo 'User chose "no". Not running the next script.'
        ;;
    esac
fi

if [ ${ROCM_RUN_NEXT_SCRIPT} = true ]; then
    ${BASE_DIR}/02_setup_rocm_users.sh "$@"
fi
