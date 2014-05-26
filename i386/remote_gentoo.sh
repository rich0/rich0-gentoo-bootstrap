
#-------------------------------------------------------------------------------
# i386/remote_gentoo.sh
#-------------------------------------------------------------------------------
# Copyright 2012 Dowd and Associates
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#-------------------------------------------------------------------------------

[ -e /tmp/plugin ] && . /tmp/plugin

echo "mkfs -t ext4 /dev/xvdf"
mkfs -t ext4 /dev/xvdf
echo "mkdir -p /mnt/gentoo"
mkdir -p /mnt/gentoo

mount /dev/xvdf /mnt/gentoo

cd /tmp
echo "Download stage3"
curl -O http://gentoo.mirrors.pair.com/releases/x86/autobuilds/`curl --silent http://gentoo.mirrors.pair.com/releases/x86/autobuilds/latest-stage3-i686.txt | grep stage3-i686`
#echo "Download portage"
#curl -O http://gentoo.mirrors.pair.com/snapshots/portage-latest.tar.bz2
echo "Unpack stage3"
tar -xjpf /tmp/stage3-*.tar.bz2 -C /mnt/gentoo

echo "Setup files"

echo "/etc/portage/make.conf"
cat <<'EOF'>/mnt/gentoo/etc/portage/make.conf
# These settings were set by the catalyst build script that automatically
# built this stage.
# Please consult /usr/share/portage/config/make.conf.example for a more
# detailed example.
CFLAGS="-O2 -march=i686 -mno-tls-direct-seg-refs -pipe"
CXXFLAGS="${CFLAGS}"
# WARNING: Changing your CHOST is not something that should be done lightly.
# Please consult http://www.gentoo.org/doc/en/change-chost.xml before changing.
CHOST="i686-pc-linux-gnu"
MAKEOPTS="-j3"
EMERGE_DEFAULT_OPTS="--jobs=2 --load-average=4.0"
EOF

mkdir -p /mnt/gentoo/etc/portage

echo "/etc/resolv.conf"
cp -L /etc/resolv.conf /mnt/gentoo/etc/resolv.conf

echo "/usr/src/linux/.config"
mkdir -p /mnt/gentoo/tmp
cp /tmp/.config /mnt/gentoo/tmp/.config

mkdir -p /mnt/gentoo/var/lib/portage
echo "/var/lib/portage/world"
cat <<'EOF'>/mnt/gentoo/var/lib/portage/world
app-admin/logrotate
app-admin/sudo
app-admin/syslog-ng
app-arch/unzip
app-editors/nano
app-editors/vim
app-misc/screen
app-portage/gentoolkit
dev-vcs/git
net-misc/curl
net-misc/dhcpcd
net-misc/ntp
sys-fs/lvm2
sys-fs/mdadm
sys-kernel/gentoo-sources
sys-process/fcron
sys-process/atop
sys-apps/ec2-shim
EOF

echo "/tmp/build.sh"

cat <<'EOF'>/mnt/gentoo/tmp/build.sh
#!/bin/bash

env-update
source /etc/profile

emerge-webrsync

cp /usr/share/zoneinfo/GMT /etc/localtime

# install layman when overlay needed
emerge layman 
USE="-cgi -curl -emacs -gtk -iconv -perl -python -tk -webdav -xinetd -cvs -subversion" emerge git
echo "source /var/lib/layman/make.conf" >> /etc/portage/make.conf
layman -f -a rich0

emerge -u portage

emerge --update --deep --with-bdeps=y --newuse --keep-going world

cd /usr/src/linux
mv /tmp/.config ./.config
yes "" | make oldconfig
make -j4 && make -j4 modules_install
cp -L arch/x86/boot/bzImage /boot/bzImage

groupadd sudo
useradd -r -m -s /bin/bash ec2-user

ln -s /etc/init.d/net.lo /etc/init.d/net.eth0

rc-update add net.eth0 default
rc-update add sshd default
rc-update add syslog-ng default
rc-update add fcron default
rc-update add ntpd default
rc-update add lvm boot
rc-update add mdraid boot

mv /etc/portage/make.conf /etc/portage/make.conf.bkup
sed "s/MAKEOPTS=\"-j.*\"/MAKEOPTS=\"-j2\"/g" /etc/portage/make.conf.bkup > /etc/portage/make.conf
rm /etc/portage/make.conf.bkup

etc-update --automode -5

EOF

plugin_prebuild
prebstat=$?

chmod 755 /mnt/gentoo/tmp/build.sh

mount -t proc none /mnt/gentoo/proc
mount --rbind /dev /mnt/gentoo/dev
mount --rbind /dev/pts /mnt/gentoo/dev/pts

chroot /mnt/gentoo /tmp/build.sh
bdstat=$?

plugin_postbuild
pstbstat=$?

rm -fR /mnt/gentoo/tmp/*
rm -fR /mnt/gentoo/var/tmp/*
rm -fR /mnt/gentoo/usr/portage/distfiles/*

[[ $prebstat -eq 0 ]] && [[ $bdstat -eq 0 ]] && [[ $pstbstat -eq 0 ]] && shutdown -h now
