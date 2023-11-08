#!/bin/bash
#
#	https://github.com/bztsrc/raspi3-tutorial
#   https://www.qemu.org/docs/master/system/arm/raspi.html
#

if [ "$SHELL" != "/bin/bash" ]; then
  echo "Dieses Skript erfordert die Bash-Shell zum Ausführen."
  exit 1
fi

if [ "$(ps -p $$ -o comm=)" = "bash" ]; then
	echo "Das Skript wurde mit bash gestartet."
else
	echo "Dieses Skript erfordert die Bash-Shell zum Ausführen."
	exit 1
fi

json=$(cat infos.json)
for key in $(echo "$json" | jq -r 'keys[]'); do
	value=$(echo "$json" | jq -r ".$key")
        echo "$key=$value" 
	export $key="$value"
done



KERNEL_VERS=6.5.10
if [[ $CONFIG_KERNEL_ARCH == "cris" ]] ; then
	KERNEL_VERS=4.9.156
fi


print_status(){
	 echo -e "\033[01;33m------------------------------  \033[01;32m $1 \033[01;33m ---------------------------------------\033[00m"
}

prepare_kernel(){
	if [ ! -e linux-$KERNEL_VERS.tar.xz ] ; then
		print_status "download Kernel"
		wget https://cdn.kernel.org/pub/linux/kernel/v6.x/linux-$KERNEL_VERS.tar.xz -O linux-$KERNEL_VERS.tar.xz.dl
		mv linux-$KERNEL_VERS.tar.xz.dl linux-$KERNEL_VERS.tar.xz
	
	fi
	
	if [ ! -e linux-$KERNEL_VERS ] ; then
		print_status "extract Kernel"
		tar -xaf linux-$KERNEL_VERS.tar.xz
	fi
}

conf_kernel(){
	
	prepare_kernel
	
	print_status "conf_kernel"
	
	make -C linux-$KERNEL_VERS ARCH=$CONFIG_KERNEL_ARCH CROSS_COMPILE=$CONFIG_GCC_PREFIX menuconfig
}


build_kernel(){

	prepare_kernel
	
	print_status "build Kernel"
	
	#make -C linux-$KERNEL_VERS ARCH=$CONFIG_KERNEL_ARCH CROSS_COMPILE=$CONFIG_GCC_PREFIX defconfig
	
	make -C linux-$KERNEL_VERS ARCH=$CONFIG_KERNEL_ARCH CROSS_COMPILE=$CONFIG_GCC_PREFIX -j20
	
	if [[ $CONFIG_KERNEL_ARCH == "arc" ]] ; then 
		make -C linux-$KERNEL_VERS ARCH=$CONFIG_KERNEL_ARCH CROSS_COMPILE=$CONFIG_GCC_PREFIX uImage
	fi
	
	if [[ $CONFIG_KERNEL_ARCH == "sparc64" ]] ; then ${CONFIG_GCC_PREFIX}objcopy  -S linux-$KERNEL_VERS/vmlinux kernel.img ; fi
	
	if [[ $CONFIG_KERNEL_ARCH == "powerpc" ]] ; then ${CONFIG_GCC_PREFIX}objcopy  -S linux-$KERNEL_VERS/vmlinux kernel.img ; fi

}

para_kernel(){
	
	prepare_kernel
	
	make -C linux-$KERNEL_VERS ARCH=$CONFIG_KERNEL_ARCH CROSS_COMPILE=$CONFIG_GCC_PREFIX $2
}



oldconf_kernel(){
	
	prepare_kernel

	make -C linux-$KERNEL_VERS ARCH=$CONFIG_KERNEL_ARCH CROSS_COMPILE=$CONFIG_GCC_PREFIX oldconfig
}


upload_kernel(){
	
	print_status "upload_kernel"
	
	if [ ! -e uclibc-ng-qemu-imgs ] ; then
		git clone git@github.com:lordrasmus/uclibc-ng-qemu-imgs.git
	fi
	
	if [ $# -ne 2 ] ; then
		echo "kernel name angeben"
		exit 1
	fi
	
	echo "Kernel Name : $2"
	
	cp linux-$KERNEL_VERS/arch/$CONFIG_KERNEL_ARCH/boot/bzImage uclibc-ng-qemu-imgs/$2.img
	cp linux-$KERNEL_VERS/.config uclibc-ng-qemu-imgs/$2.config
	
	( cd uclibc-ng-qemu-imgs; git status )
	
	
}


fill_sysroot(){
	if [ ! -e sysroot ] ; then
		tar -xf sysroot.tar
	fi
	cp $CONFIG_TOOLCHAIN/sysroot/usr/lib/libatomic* sysroot/usr/lib
	cp $CONFIG_TOOLCHAIN/sysroot/usr/lib/libgcc* sysroot/usr/lib
	
}

build_rootfs(){

	print_status "build_rootfs"
	
	rm -rf rootfs
	mkdir rootfs
	mkdir -p rootfs/usr/lib/
	
	
	cp -r sysroot/lib/ rootfs/ 
    cp sysroot/usr/lib/*.so* rootfs/usr/lib/
    #cp sysroot/usr/lib/libatomic* rootfs/usr/lib/
    #cp sysroot/usr/lib/libgcc* rootfs/usr/lib/
	
	if [ ! -e sysroot/usr/include/linux/limits.h ] ; then
		tar -xaf linux-$CONFIG_KERNEL_VERS.tar.xz
		make -C linux-$CONFIG_KERNEL_VERS/ INSTALL_HDR_PATH=$(pwd)/sysroot/usr/ headers_install ARCH=$CONFIG_KERNEL_ARCH
	fi
	
	if [ ! -e uclibc-ng-test ] ; then
		git clone https://cgit.uclibc-ng.org/cgi/cgit/uclibc-ng-test.git/
	fi
	
	cat uclibc-ng-config | grep SHAR
	
	echo "" > tests_disable
	if grep -q '# UCLIBC_HAS_LOCALE is not set' uclibc-ng-config; then echo "export NO_LOCALE=1 " >> tests_disable; fi
	if grep -q 'HAS_NO_THREADS=y' uclibc-ng-config;               then echo "export NO_THREADS=1  NO_NPTL=1  NO_TLS=1 "  >> tests_disable ; fi
	if grep -q 'CONFIG_SH2=y' uclibc-ng-config;                   then echo "export NO_MATH=1" >> tests_disable; fi
	if grep -q 'TARGET_alpha=y' uclibc-ng-config;                 then echo "export NO_MATH=1" >> tests_disable; fi
	if grep -q '# UCLIBC_HAS_OBSOLETE_BSD_SIGNAL is not set' uclibc-ng-config;  then echo "export  NO_NPTL=1 "  >> tests_disable ; fi
	

	#exit 1

	. tests_disable
	CROSS_COMPILE=$CONFIG_GCC_PREFIX CFLAGS="--sysroot=$(pwd)/sysroot/" LDFLAGS="--sysroot=$(pwd)/sysroot/ "   make -C uclibc-ng-test -j20
	if [ $? -ne 0 ] ; then
		exit 1
	fi
	CROSS_COMPILE=$CONFIG_GCC_PREFIX CFLAGS="--sysroot=$(pwd)/sysroot/" LDFLAGS="--sysroot=$(pwd)/sysroot/ "   make -C uclibc-ng-test install DESTDIR=../rootfs > /dev/null 2>&1

	#exit 1

	#rm -rf busybox*

	if [ ! -e busybox-1.36.1 ] ; then
		wget https://busybox.net/downloads/busybox-1.36.1.tar.bz2
		tar -xaf busybox-1.36.1.tar.bz2
	fi

	

	make -C busybox-1.36.1/ defconfig > /dev/null

	sed -i 's/CONFIG_CROSS_COMPILER_PREFIX=""/CONFIG_CROSS_COMPILER_PREFIX="'$CONFIG_GCC_PREFIX'"/' busybox-1.36.1/.config
	sed -i 's|CONFIG_SYSROOT=""|CONFIG_SYSROOT="'$(pwd)'/sysroot/"|' busybox-1.36.1/.config
	sed -i 's|CONFIG_PREFIX="./_install"|CONFIG_PREFIX="../rootfs"|'  busybox-1.36.1/.config
	sed -i 's|CONFIG_FEATURE_EJECT_SCSI=y|# CONFIG_FEATURE_EJECT_SCSI is not set|'  busybox-1.36.1/.config
	
	
	# no MMU fixes
	if [[ $UCLIBC_MMU == "No" ]] ; then
		sed -i 's|CONFIG_SHELL_ASH=y|# CONFIG_SHELL_ASH is not set|'  busybox-1.36.1/.config
		sed -i 's|CONFIG_ASH=y|# CONFIG_ASH is not set|'  busybox-1.36.1/.config
		sed -i 's|CONFIG_SH_IS_ASH=y|# CONFIG_SH_IS_ASH is not set|'  busybox-1.36.1/.config
		sed -i 's|# CONFIG_SH_IS_HUSH is not set|CONFIG_SH_IS_HUSH=y|'  busybox-1.36.1/.config
		sed -i 's|# CONFIG_NOMMU is not set|CONFIG_NOMMU=y|'  busybox-1.36.1/.config
	fi
	
	sed -i 's|# CONFIG_STATIC is not set|CONFIG_STATIC=y|'  busybox-1.36.1/.config
	

	#make -C busybox-1.36.1 oldconfig

	#exit 1

	make -C busybox-1.36.1 -j20

	make -C busybox-1.36.1/ install


	( cd rootfs ; ln -s /sbin/init init )
	( cd rootfs ; mkdir dev; mkdir etc; mkdir proc; mkdir sys; mkdir tmp )
	echo "::sysinit:/bin/mount -t devtmpfs none /dev" >  rootfs/etc/inittab
	echo "::sysinit:/bin/mount -t proc none /proc" >> rootfs/etc/inittab
	echo "::sysinit:/bin/mount -t sysfs none /sys" >> rootfs/etc/inittab
	echo "::sysinit:/bin/dmesg -n1" >>  rootfs/etc/inittab
	echo "::sysinit:/bin/echo 'test console' > /dev/console" >> rootfs/etc/inittab
	echo "::sysinit:/bin/echo 'test ttyS0' > /dev/ttyS0" >> rootfs/etc/inittab
	#echo "::sysinit:/bin/echo 'test ttyS1' > /dev/ttyS1" >> rootfs/etc/inittab
	#echo "::sysinit:/bin/echo 'test ttyS2' > /dev/ttyS2" >> rootfs/etc/inittab
	#echo "::sysinit:/bin/echo 'test ttyS3' > /dev/ttyS3" >> rootfs/etc/inittab
	echo "console::sysinit:/bin/run_tests.sh" >> rootfs/etc/inittab
	echo "console::respawn:/bin/sh" >> rootfs/etc/inittab
	echo "08:00:20:00:61:CA  pal" > rootfs/etc/ethers
	echo "08:00:20:00:61:CB  192.168.11.2" >> rootfs/etc/ethers
	echo "08:00:20:00:61:CC  teeth" >> rootfs/etc/ethers
	echo "root:x:0:" > rootfs/etc/group
	echo "root:x:0:0:root:/root:/bin/sh" > rootfs/etc/passwd
	
	echo "#!/bin/sh"                                                           >  rootfs/bin/run_tests.sh
	echo "cd /usr/lib/uclibc-ng-test/test/"                                    >> rootfs/bin/run_tests.sh
	echo "echo '-------------------- tests_start ------------------------'"    >> rootfs/bin/run_tests.sh
	echo "sh uclibcng-testrunner.sh"                                           >> rootfs/bin/run_tests.sh
	echo "echo '-------------------- tests_end --------------------------'"    >> rootfs/bin/run_tests.sh
	chmod 777 rootfs/bin/run_tests.sh
          
	( cd rootfs ; find . | sort | cpio -o -H newc ) > rootfs.img
	rm -f rootfs.img.xz
	xz -k --check=crc32 rootfs.img
}




export PATH=$PATH:$(pwd)/$CONFIG_TOOLCHAIN/usr/bin

if [ ! -e $CONFIG_TOOLCHAIN ] ; then
	tar -xaf ${CONFIG_TOOLCHAIN}.tar.xz
fi


if [ $# -eq 0 ] ; then
	echo ""
	echo "build_kernel oder build_rootfs angeben"
	echo ""
	exit 1
fi

if [[ $1 == "build_kernel" ]] ;  then build_kernel   ; exit 0 ; fi
if [[ $1 == "conf_kernel" ]]  ;  then conf_kernel    ; exit 0 ; fi
if [[ $1 == "para_kernel" ]]  ;  then para_kernel  $@  ; exit 0 ; fi
if [[ $1 == "oldconf_kernel" ]]; then oldconf_kernel ; exit 0 ; fi

if [[ $1 == "upload_kernel" ]]; then upload_kernel $@ ; exit 0 ; fi

if [[ $1 == "build_rootfs" ]] ; then 
	fill_sysroot 
	build_rootfs
	exit 0
fi


echo ""
echo "build_kernel oder build_rootfs angeben"
echo ""
exit 1


qemu-system-sparc64 -M sun4u -kernel qemu-sparc64-initramfs-kernel -nographic
