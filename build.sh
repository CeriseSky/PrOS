#!/bin/sh

# PrOS build script
#   Copyright (C) 2024 Gabriel Jickells
#
#   This program is free software: you can redistribute it and/or modify
#   it under the terms of the GNU General Public License as published by
#   the Free Software Foundation, either version 3 of the License, or
#   (at your option) any later version.
#
#   This program is distributed in the hope that it will be useful,
#   but WITHOUT ANY WARRANTY; without even the implied warranty of
#   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
#   GNU General Public License for more details.
#
#   You should have received a copy of the GNU General Public License
#   along with this program. If not, see <https://www.gnu.org/licenses/>.

# run as privileged user

set -e

mkdir -p bin/tmp

# bootloader
nasm -f bin -o bin/tmp/boot.bin src/boot.asm
nasm -f bin -o bin/tmp/menu.bin src/menu.asm

# disk
dd if=/dev/zero of=bin/disk.img bs=1024 count=160
loop_device=$(losetup -f)
losetup $loop_device bin/disk.img

# install
mkfs.fat -f 2 -F 12 -r 16 -s 1 $loop_device
dd if=bin/tmp/boot.bin of=$loop_device conv=notrunc
mount $loop_device bin/files --mkdir
mkdir -p bin/files/SYSTEM/BOOT/
cp bin/tmp/menu.bin bin/files/SYSTEM/BOOT/BOOT.COM

# cleanup
umount $loop_device
losetup -d $loop_device
rm -r bin/files bin/tmp

