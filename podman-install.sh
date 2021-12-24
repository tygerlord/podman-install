#!/bin/bash


set -eu -o pipefail # fail on error and report it, debug all lines

sudo true 
test $? -eq 0 || exit 1 "you should have sudo privilege to run this script"


echo install packages
sudo apt-get install -y \
  btrfs-progs \
  golang-go \
  go-md2man \
  git \
  iptables \
  libassuan-dev \
  libbtrfs-dev \
  libc6-dev \
  libdevmapper-dev \
  libglib2.0-dev \
  libgpgme-dev \
  libgpg-error-dev \
  libprotobuf-dev \
  libprotobuf-c-dev \
  libseccomp-dev \
  libselinux1-dev \
  libsystemd-dev \
  pkg-config \
  runc \
  uidmap \
  slirp4netns


ROOT=$(pwd)
export GOPATH=$ROOT/go

echo $ROOT $GOPATH 

# go
if [ ! -d "$GOPATH" ]; then
 git clone https://go.googlesource.com/go $GOPATH
 cd $GOPATH
 sudo -v
 cd src
 ./all.bash
fi
export PATH=$GOPATH/bin:$PATH

sudo -v

# conman
cd $ROOT
if [ ! -d "$ROOT/conmon" ]; then
 git clone https://github.com/containers/conmon
 cd conmon
 export GOCACHE="$(mktemp -d)"
 make
 sudo make podman
fi

sudo -v

#--------------------------------------------------------------------------------
#|Build Tag                       |Feature                          |Dependency |
#--------------------------------------------------------------------------------
#|apparmor                        |apparmor support                 |libapparmor|
#|exclude_graphdriver_btrfs       |exclude btrfs                    |libbtrfs   |
#|exclude_graphdriver_devicemapper|exclude device-mapper            |libdm      |
#|libdm_no_deferred_remove        |exclude deferred removal in libdm|libdm      |
#|seccomp                         |syscall filtering                |libseccomp |
#|selinux                         |selinux process and mount        |labeling   | 	 
#|systemd                         |journald logging                 |libsystemd |
#--------------------------------------------------------------------------------

BUILDTAGS="selinux seccomp systemd"
# runc
RUNCPATH="$GOPATH/src/github.com/opencontainers/runc"
if [ ! -d "$RUNCPATH" ]; then
 git clone https://github.com/opencontainers/runc.git $RUNCPATH
 cd $RUNCPATH
 make BUILDTAGS="$BUILDTAGS"
 sudo cp runc /usr/bin/runc
fi

sudo -v

# cni
CNIPATH="$GOPATH/src/github.com/containernetworking/plugins"
if [ ! -d "$CNIPATH" ]; then
 git clone https://github.com/containernetworking/plugins.git $CNIPATH
 cd $CNIPATH
else
 cd $CNIPATH
 git pull
fi
./build_linux.sh
sudo mkdir -p /usr/libexec/cni
sudo cp bin/* /usr/libexec/cni

sudo -v

# dnsname
cd $ROOT
DNSNAMEPATH="$ROOT/dnsname"
if [ ! -d "$DNSNAMEPATH" ]; then
 git clone https://github.com/containers/dnsname.git 
 cd $DNSNAMEPATH
 make
 sudo make install PREFIX=/usr
fi 


# setup network
sudo mkdir -p /etc/cni/net.d
NETWORK="/etc/cni/net.d/99-loopback.conf"
if [ ! -f $NETWORK ]; then
   curl -qsSL https://raw.githubusercontent.com/containers/libpod/master/cni/87-podman-bridge.conflist | sudo tee $NETWORK
fi

# add configuration
SYSCTL="/etc/sysctl.d/14-userns.conf"
if [ ! -f $SYSCTL ]; then
   echo 'kernel.unprivileged_userns_clone=1'  | sudo tee $SYSCTL
fi

REGISTRIES="/etc/containers/registries.conf"
sudo mkdir -p /etc/containers
if [ ! -f $REGISTRIES ]; then
   sudo curl -L -o $REGISTRIES https://src.fedoraproject.org/rpms/containers-common/raw/main/f/registries.conf
fi

POLICY="/etc/containers/policy.json"
if [ ! -f $POLICY ]; then
   sudo curl -L -o $POLICY https://src.fedoraproject.org/rpms/containers-common/raw/main/f/default-policy.json
fi

sudo -v

# podman
PODPATH="$ROOT/podman"
cd $ROOT
if [ ! -d "$PODPATH" ]; then
 git clone https://github.com/containers/podman/
 cd $PODPATH
else
 cd $PODPATH
 git pull
fi
 
make BUILDTAGS="$BUILDTAGS"
sudo make install PREFIX=/usr

sudo -v

# bash completion
sudo podman completion -f /etc/bash_completion.d/podman bash

