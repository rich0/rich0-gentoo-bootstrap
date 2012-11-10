
#-------------------------------------------------------------------------------
# x86_64/remote_gentoo.sh
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
curl -O http://gentoo.mirrors.pair.com/releases/amd64/autobuilds/`curl --silent http://gentoo.mirrors.pair.com/releases/amd64/autobuilds/latest-stage3-amd64.txt | grep stage3-amd64`
echo "Download portage"
curl -O http://gentoo.mirrors.pair.com/snapshots/portage-latest.tar.bz2
echo "Unpack stage3"
tar -xjpf /tmp/stage3-*.tar.bz2 -C /mnt/gentoo
echo "Unpack portage"
tar -xjf /tmp/portage*.tar.bz2 -C /mnt/gentoo/usr

echo "Setup files"

mkdir -p /mnt/gentoo/boot/grub
echo "/boot/grub/menu.lst"
cat <<'EOF'>/mnt/gentoo/boot/grub/menu.lst
default 0
timeout 3
title EC2
root (hd0)
kernel /boot/bzImage root=/dev/xvda1 rootfstype=ext4
EOF

echo "/etc/fstab"
cat <<'EOF'>/mnt/gentoo/etc/fstab
/dev/xvda1 / ext4 defaults 1 1
/dev/xvda3 none swap sw 0 0
none /dev/pts devpts gid=5,mode=620 0 0
none /dev/shm tmpfs defaults 0 0
none /proc proc defaults 0 0
none /sys sysfs defaults 0 0
EOF

mkdir -p /mnt/gentoo/etc/local.d
echo "/etc/local.d/killall_nash-hotplug.start"
cat <<'EOF'>/mnt/gentoo/etc/local.d/killall_nash-hotplug.start
# /etc/local.d/killall_nash-hotplug.start

killall nash-hotplug
EOF
chmod 755 /mnt/gentoo/etc/local.d/killall_nash-hotplug.start

echo "/etc/local.d/public-keys.start"
cat <<'EOF'>/mnt/gentoo/etc/local.d/public-keys.start
# /etc/local.d/public-keys.start

[ ! -e /home/ec2-user ] && cp -r /etc/skel /home/ec2-user && chown -R ec2-user /home/ec2-user && chgrp -R ec2-user /home/ec2-user
if [ ! -d /home/ec2-user/.ssh ] ; then
mkdir -p /home/ec2-user/.ssh
chmod 700 /home/ec2-user/.ssh
chown ec2-user /home/ec2-user/.ssh
chgrp ec2-user /home/ec2-user/.ssh
fi
curl http://169.254.169.254/latest/meta-data/public-keys/0/openssh-key > /tmp/my-key
if [ $? -eq 0 ] ; then
cat /tmp/my-key >> /home/ec2-user/.ssh/authorized_keys
chmod 600 /home/ec2-user/.ssh/authorized_keys
chown ec2-user /home/ec2-user/.ssh/authorized_keys
chgrp ec2-user /home/ec2-user/.ssh/authorized_keys
rm /tmp/my-key
fi
EOF
chmod 755 /mnt/gentoo/etc/local.d/public-keys.start

echo "/etc/local.d/public-keys.stop"
cat <<'EOF'>/mnt/gentoo/etc/local.d/public-keys.stop
# /etc/local.d/public-keys.stop

rm -f /home/ec2-user/.ssh/authorized_keys
EOF
chmod 755 /mnt/gentoo/etc/local.d/public-keys.stop

echo "/etc/portage/make.conf"
cat <<'EOF'>/mnt/gentoo/etc/portage/make.conf
# These settings were set by the catalyst build script that automatically
# built this stage.
# Please consult /usr/share/portage/config/make.conf.example for a more
# detailed example.
CFLAGS="-O2 -pipe"
CXXFLAGS="${CFLAGS}"
# WARNING: Changing your CHOST is not something that should be done lightly.
# Please consult http://www.gentoo.org/doc/en/change-chost.xml before changing.
CHOST="x86_64-pc-linux-gnu"
# These are the USE flags that were used in addition to what is provided by the
# profile used for building.
USE="mmx sse sse2"
MAKEOPTS="-j3"
EMERGE_DEFAULT_OPTS="--jobs=2 --load-average=4.0"
EOF

mkdir -p /mnt/gentoo/etc/portage

echo "/etc/resolv.conf"
cp -L /etc/resolv.conf /mnt/gentoo/etc/resolv.conf

mkdir -p /mnt/gentoo/etc/sudoers.d
echo "/etc/sudoers.d/ec2-user"
cat <<'EOF'>/mnt/gentoo/etc/sudoers.d/ec2-user
ec2-user  ALL=(ALL) NOPASSWD:ALL
EOF
chmod 440 /mnt/gentoo/etc/sudoers.d/ec2-user

echo "/etc/sudoers.d/_sudo"
cat <<'EOF'>/mnt/gentoo/etc/sudoers.d/_sudo
%sudo     ALL=(ALL) ALL
EOF
chmod 440 /mnt/gentoo/etc/sudoers.d/_sudo

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
EOF

echo "/tmp/build.sh"

cat <<'EOF'>/mnt/gentoo/tmp/build.sh
#!/bin/bash

env-update
source /etc/profile

emerge --sync

cp /usr/share/zoneinfo/GMT /etc/localtime

emerge --update --deep --with-bdeps=y --newuse --keep-going world

cd /usr/src/linux
mv /tmp/.config ./.config
yes "" | make oldconfig
make -j4 && make -j4 modules_install
cp -L arch/x86_64/boot/bzImage /boot/bzImage

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

EOF

plugin_prebuild

chmod 755 /mnt/gentoo/tmp/build.sh

mount -t proc none /mnt/gentoo/proc
mount --rbind /dev /mnt/gentoo/dev
mount --rbind /dev/pts /mnt/gentoo/dev/pts

chroot /mnt/gentoo /tmp/build.sh

plugin_postbuild

rm -fR /mnt/gentoo/tmp/*
rm -fR /mnt/gentoo/var/tmp/*
rm -fR /mnt/gentoo/usr/portage/distfiles/*

shutdown -h now
