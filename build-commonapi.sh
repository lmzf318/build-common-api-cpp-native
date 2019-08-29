#!/bin/bash -x

# This script is based on the detailed instructions from GENIVI public wiki
# written by Juergen Gehring.
# "CommonAPI C++ D-Bus in 10 minutes (from scratch)"
# https://at.projects.genivi.org/wiki/pages/viewpage.action?pageId=5472316
#
# (C) 2016,2018 Gunnar Andersson <gand@acm.org>
# Purpose: Download and native compilation of CommonAPI C++ DBus
#
# License: http://creativecommons.org/licenses/by-sa/4.0/
# ( since the material was taken from GENIVI Public Wiki:
#  "Except where otherwise noted, content on this site is licensed under a
#  Creative Commons Attribution-ShareAlike 4.0 International License" )


# According to web page:
# "Valid for CommonAPI 3.1.3 and vsomeip 1.3.0"

# SETTINGS

VSOMEIP_VERSION=2.14.16
BOOST_DL_DIR_VERSION=1.65.0
BOOST_TAR_VERSION=1_65_0

ARCH=$(uname -m)

# Get absolute path to base dir
MYDIR=$(dirname "$0")
cd "$MYDIR"
BASEDIR="$PWD"

try() { $@ || fail "Command $* failed -- check above for details" ;}

# Either sudo must exist, or script must run as root
which sudo >/dev/null
if [ $? -ne 0 ] ; then
   if [ $(id -u) -ne 0 ] ; then
      fail "No sudo command exists in your system.  (You could install it (recommended) or run as root instead)"
   else
      # Running as root - define sudo as empty
      sudo=
   fi
else
   # sudo exists
   sudo=sudo
fi

fail() {
   set +x # Turn off command listing now, if it's on
   echo "FAILED!  Message follows:"
   echo $@
   echo "Halted, hit return to continue, or give up..."
   read x

}

git_clone() {
   # This is so we don't fail if directory already exists
   # but still, if a new clone is attempted and fails, then fail
   d="$(basename $1)" # repo/directory name
   d="${d%.git}"      # Strip off ".git" if it is there
   if [ -d $d ] ; then
      echo "Directory $d exists, no git clone attempted"
   else
      try git clone $1
   fi
}

check_expected() {
for f in $@ ; do
   [ -e $f ] || fail "Expected result file $f not present (not built)!"
done
}

check_os(){

    result=`lsb_release -i`
    # If lsb_release binary does not exist
    if [ -z "$result" ] ; then
       fgrep -qi fedora /etc/os-release && os=fedora
       fgrep -qi ubuntu /etc/os-release && os=ubuntu
       fgrep -qi centos /etc/os-release && os=centos
       fgrep -qi debian /etc/os-release && os=debian
       fgrep -qi apertis /etc/os-release && os=apertis
    else
      os=`echo $result |awk -F":" '{print $2}' |tr A-Z a-z`
    fi

    if [[ $os =~ "ubuntu" || $os =~ "debian" || $os =~ "apertis" || $os =~ "centos" || $os =~ "redhat" || $os =~ "fedora" ]] ; then
      echo "OK, recognized distro as $os ..."
    else
      echo "***"
      echo "*** WARNING: Unsupported OS/distro.  This might fail later on."
      echo "***"
    fi
}

install_prerequisites() {
  check_os

  java -version || {
    echo "Java not installed?  (Could not check version)"
    echo "Please install a Java interpreter (JRE)"
    echo "This is not done by the script because it would need to force the java version and this may interfere with the system"
    echo "In addition, the java packages have different names"
    fail "No java JRE is installed"
  }

  # This is very rough, but just the bare minimum to support
  # different distros.  Might be buggy on some, try and see.
  dnf -v >/dev/null 2>&1 && dnf=true || dnf=false
  $dnf || yum -v >/dev/null 2>&1 && yum=true || yum=false
  apt -v >/dev/null 2>&1 && apt=true || apt=false

  echo dnf $dnf yum $yum apt $apt

  if [ ! -f .installed_packages ] ; then
    $dnf && $sudo dnf install -y unzip git make jexpat-devel cmake gcc gcc-c++ automake autoconf wget pkg-config
    $yum && $sudo yum install -y unzip git make jexpat-devel cmake gcc gcc-c++ automake autoconf wget pkg-config
    $apt && $sudo apt install -y unzip git make libexpat1-dev cmake gcc g++ automake autoconf wget pkg-config
  fi
  touch .installed_packages
}

apply_patch() {
  # Use forward to avoid questions if patch had been applied already (second run)
  # Answer proposed by Tom Hale, reference:
  # https://stackoverflow.com/questions/21928344/how-to-not-break-the-makefile-if-patch-skips-the-patch
  if patch --dry-run --reverse --force < "$1" >/dev/null 2>&1; then
    echo "Patch already applied - skipping."
  else # patch not yet applied
    echo "Patching..."
    patch -Ns < "$1" || echo "Patch failed" >&2 && return 1
  fi
}

install_prerequisites

# Build Boost
cd "$BASEDIR" || fail
try wget -c https://dl.bintray.com/boostorg/release/${BOOST_DL_DIR_VERSION}/source/boost_${BOOST_TAR_VERSION}.tar.gz
try tar -xzf boost_${BOOST_TAR_VERSION}.tar.gz
# OK, so it's now under boost_ and the version in the same way it is written in the *TAR* file
cd boost_${BOOST_TAR_VERSION} || fail "Expected boost to be in $BOOST_TAR_VERSION/ after unpacking!"
try ./bootstrap.sh
BOOST_ROOT=`realpath $PWD/../install`
mkdir -p $BOOST_ROOT
try ./b2 -d+2 --prefix=$BOOST_ROOT link=shared threading=multi toolset=gcc -j$(nproc) install

# Build vsomeip
cd "$BASEDIR" || fail
VSOMEIP_INSTALL=`realpath $PWD/install`
git_clone https://github.com/GENIVI/vsomeip.git
cd vsomeip
git checkout $VSOMEIP_VERSION || fail "vsomeip: Failed git checkout of $VSOMEIP_VERSION"
mkdir -p build
cd build || fail
try cmake -DCMAKE_INSTALL_PREFIX="$VSOMEIP_INSTALL" -DBOOST_ROOT=${BOOST_ROOT} -DENABLE_SIGNAL_HANDLING=1 ..
try make -j$(nproc)
try make install


cd "$BASEDIR" || fail
echo "Checking a few results (were libraries compiled and installed?)"
test -f install/lib/libboost_log.so|| fail "Could not find libboost_log.so in install/lib?  Something probably went wrong"
test -f install/lib/libvsomeip.so  || fail "Could not find libvsomeip.so in install/lib?  Something probably went wrong"

