#!/bin/bash

git clone https://github.com/microsoft/WSL2-Linux-Kernel.git --depth=1 -b linux-msft-wsl-6.1.y
sudo apt update -y
sudo apt install build-essential flex bison libssl-dev libelf-dev bc python3 pahole
cd WSL2-Linux-Kernel
make -j$(nproc) KCONFIG_CONFIG=../config/wsl/.config
# sudo make modules_install headers_install