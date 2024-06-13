#!/bin/bash

# Follow this: https://learn.microsoft.com/en-us/community/content/wsl-user-msft-kernel-v6

git clone https://github.com/microsoft/WSL2-Linux-Kernel.git --depth=1 -b linux-msft-wsl-6.1.y
sudo apt update -y
sudo apt install build-essential flex bison libssl-dev libelf-dev bc python3 pahole
cd WSL2-Linux-Kernel
make -j$(nproc) KCONFIG_CONFIG=../config/wsl/.config
# sudo make modules_install headers_install

# Load the following kernel modules before launching docker instances:
# kvm
# kvm_intel
# xt_connmark
# ebtables
# openvswitch
# nsh
# nf_conncount
# br_netfilter
# bridge
# stp
# llc
# sudo modprobe kvm kvm_intel xt_connmark ebtables openvswitch nsh nf_conncount br_netfilter bridge stp llc

# may need to change wsl docker-desktop instance
## cat /etc/wsl.conf
#[automount]
#root = /mnt/host
#crossDistro = true
#enabled=true
#options="metadata,umask=22,fmask=11"
#[network]
#generateResolvConf = false

# Then recreate /etc/resolv.conf
# nameserver 8.8.8.8
# nameserver 8.8.4.4 