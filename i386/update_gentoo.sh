mv /etc/make.conf /etc/make.conf.bkup
sed "s/MAKEOPTS=\"-j.*\"/MAKEOPTS=\"-j3\"/g" /etc/make.conf.bkup > /etc/make.conf

emerge --sync

emerge --oneshot portage

emerge --verbose --update --deep --with-bdeps=y --newuse @world

makewhatis -u

cp /usr/src/linux-3.2.21-gentoo/.config /usr/src/linux-3.3.8-gentoo/.config
eselect kernel list
eselect kernel set 3

emerge --depclean

cd /usr/src/linux
yes "" | make oldconfig
make -j3 && make -j3 modules_install
cp -L arch/x86/boot/bzImage /boot/bzImage

mv /etc/make.conf.bkup /etc/make.conf
rm -fR /tmp/*
rm -fR /var/tmp/*
rm -fR /usr/portage/distfiles/*

shutdown -h now

