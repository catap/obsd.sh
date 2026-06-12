#!/bin/sh
#
# Copyright (c) 2026 Kirill A. Korinsky <kirill@korins.ky>
#
# Permission to use, copy, modify, and distribute this software for any
# purpose with or without fee is hereby granted, provided that the above
# copyright notice and this permission notice appear in all copies.
#
# THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES
# WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF
# MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR
# ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
# WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN
# ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF
# OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.

disk_size=${DISK_SIZE:-100G}
memory=32G
cpus=8

i386_memory=4G      # OpenBSD/i386 supports up to 4Gb ram
i386_cpus=2         # More CPU is supported, but RAM suggest keep it small
armv7_memory=3G     # more than 3G makes U-boot broken
armv7_cpu=1         # OpenBSD/armv7 does not support SMP
sparc64_memory=4G   # more leads to Unhandled Exception 0x0000000000000030
sparc64_cpu=1       # more qemu doesn't support SMP in sparc

ssh_port=${SSH_PORT:-22022}

host_addr=10.0.2.1
http_addr=10.0.2.1

default_installurl=https://cdn.openbsd.org/pub/OpenBSD

usage() {
	echo "usage: $0 [-n] <arch> [qemu args ...]" >&2
	echo "       $0 [-n] (-m|-i|-u) (-s|-R version) <arch> [installurl] [qemu args ...]" >&2
	echo "       $0 [-n] -z <arch> [qemu-img convert args ...]" >&2
	echo "supported arch: amd64 arm64 armv7 i386 powerpc64 riscv64 sparc64" >&2
	exit 2
}

cleanup() {
	[ "$dry_run" = yes ] && return
	[ -n "$tmpdir" ] && rm -rf -- "$tmpdir"
	[ -n "$tmpdisk" ] && rm -f -- "$tmpdisk"
}

run_command() {
	if [ "$dry_run" = yes ]; then
		echo "$*"
	else
		"$@"
	fi
}

set_arch() {
	case "$arch" in
	amd64)
		qemu=qemu-system-x86_64
		qemu_args="-nographic"
		qemu_memory=$memory
		qemu_cpus=$cpus
		net_device=virtio-net-pci
		netboot=pxe
		;;
	arm64)
		qemu=qemu-system-aarch64
		qemu_args="-machine virt -cpu cortex-a57 -nographic -bios /usr/local/share/u-boot/qemu_arm64/u-boot.bin"
		qemu_memory=$memory
		qemu_cpus=$cpus
		net_device=virtio-net-device
		block_device=virtio-blk-pci
		netboot=efi
		efi_boot=BOOTAA64.EFI
		;;
	armv7)
		qemu=qemu-system-arm
		qemu_args="-machine virt,virtualization=on -cpu cortex-a15 -nographic -bios /usr/local/share/u-boot/qemu_arm/u-boot.bin"
		qemu_memory=$armv7_memory
		qemu_cpus=$armv7_cpu
		net_device=virtio-net-device
		block_device=virtio-blk-device
		netboot=efi
		efi_boot=BOOTARM.EFI
		;;
	i386)
		qemu=qemu-system-i386
		qemu_args="-nographic"
		qemu_memory=$i386_memory
		qemu_cpus=$i386_cpus
		net_device=virtio-net-pci
		netboot=pxe
		;;
	powerpc64)
		qemu=qemu-system-ppc64
		qemu_args="-machine powernv9 -cpu power9 -nographic -bios /usr/local/share/qemu/skiboot.lid -kernel /usr/local/share/talos-ii-pnor/pnor.BOOTKERNEL -device ich9-ahci,id=ahci0,bus=pcie.0"
		qemu_memory=$memory
		qemu_cpus=$cpus
		net_device=e1000e,bus=pcie.1
		block_device=ide-hd,bus=ahci0.0
		installer=miniroot
		qemu_disk_args=if=none,id=hd0
		qemu_miniroot_disk_args=if=none,id=miniroot0
		qemu_disk_device_args="-device ide-hd,bus=ahci0.1,drive=hd0"
		qemu_miniroot_device_args="-device ide-hd,bus=ahci0.0,drive=miniroot0"
		tmp_parent=$workdir
		;;
	riscv64)
		qemu=qemu-system-riscv64
		qemu_args="-machine virt -nographic -bios /usr/local/share/opensbi/generic/fw_jump.bin -kernel /usr/local/share/u-boot/qemu-riscv64_smode/u-boot.bin"
		qemu_memory=$memory
		qemu_cpus=$cpus
		net_device=virtio-net-device
		netboot=efi
		efi_boot=BOOTRISCV64.EFI
		;;
	sparc64)
		qemu=qemu-system-sparc64
		qemu_args="-machine sun4u -nographic -prom-env boot-device=disk -bios $workdir/openbios-sparc64-nret-fix.elf"
		qemu_memory=$sparc64_memory
		qemu_cpus=$sparc64_cpu
		net_legacy_model=sunhme
		installer=miniroot
		qemu_disk_args=if=ide,index=0
		qemu_miniroot_disk_args=if=ide,index=1
		miniroot_boot_device=/pci@1fe,0/pci@1,1/ide@3/ide@0/disk@1
		miniroot_boot_file=bsd
		;;
	*)	usage
		;;
	esac

	disk=$arch.qcow2
}

set_mode() {
	[ "$mode" = run ] || usage
	mode=$1
}

ensure_disk() {
	[ "$dry_run" = yes ] && return
	[ -f "$disk" ] && return
	qemu-img create -f qcow2 "$disk" "$disk_size" || exit 1
}

require_disk() {
	[ "$dry_run" = yes ] && return
	[ -f "$disk" ] && return
	echo "$disk does not exist" >&2
	exit 1
}

shrink_disk() {
	tmpdisk=$disk.shrink.$$
	trap cleanup EXIT HUP INT TERM
	run_command qemu-img convert -p "$@" -O qcow2 "$disk" "$tmpdisk" ||
	    exit 1

	if [ "$dry_run" = yes ]; then
		echo "mv $tmpdisk $disk"
	else
		mv "$tmpdisk" "$disk" || exit 1
	fi
	tmpdisk=
}

set_installurl() {
	if [ -z "$installurl" ] && [ -f /etc/installurl ]; then
		installurl=$(sed 's/#.*//;/^[	 ]*$/d;s/^[	 ]*//;s/[	 ]*$//;q' /etc/installurl)
	fi

	[ -n "$installurl" ] || installurl=$default_installurl

	if [ "$snapshot" = yes ]; then
		setdir=snapshots/$arch
	else
		[ -n "$release" ] || release=$(uname -r)
		setdir=$release/$arch
	fi

	srcdir=${installurl%/}/$setdir
}

fetch_file() {
	case "$srcdir" in
	ftp://*|http://*|https://*)
		ftp -o "$2" "$srcdir/$1" || exit 1
		;;
	*)
		cp "$srcdir/$1" "$2" || exit 1
		;;
	esac
}

require_tftp() {
	[ -n "$netboot" ] && return

	echo "TFTP netboot is not implemented for $arch" >&2
	exit 1
}

fetch_miniroot() {
	miniroot_version=${release:-$(uname -r)}
	case "$miniroot_version" in
	*.*)	miniroot_version=${miniroot_version%.*}${miniroot_version#*.};;
	esac
	miniroot_name=miniroot${miniroot_version}.img

	if [ "$dry_run" = yes ]; then
		case "$srcdir" in
		ftp://*|http://*|https://*)
			miniroot=/tmp/openbsd-vm.XXXXXXXXXX/$miniroot_name
			;;
		*)
			miniroot=$srcdir/$miniroot_name
			;;
		esac
		return
	fi

	case "$srcdir" in
	ftp://*|http://*|https://*)
		tmpdir=$(mktemp -d /tmp/openbsd-vm.XXXXXXXXXX) || exit 1
		trap cleanup EXIT HUP INT TERM
		miniroot=$tmpdir/$miniroot_name
		fetch_file "$miniroot_name" "$miniroot"
		;;
	*)
		miniroot=$srcdir/$miniroot_name
		[ -f "$miniroot" ] || {
			echo "$miniroot does not exist" >&2
			exit 1
		}
		;;
	esac
}

setup_miniroot() {
	set_installurl

	fetch_miniroot
}

setup_tftp() {
	require_tftp

	set_installurl

	if [ "$dry_run" = yes ]; then
		tftproot=$tmp_parent/openbsd-vm.XXXXXXXXXX/tftp
		case "$netboot" in
		pxe)	bootprog=pxeboot;;
		efi)	bootprog=$efi_boot;;
		*)	echo "TFTP netboot is not implemented for $arch" >&2
			exit 1
			;;
		esac
		bootfile=$bootprog
		case "$mode" in
		autoinstall)	bootfile=auto_install;;
		autoupgrade)	bootfile=auto_upgrade;;
		esac
		return
	fi

	tmpdir=$(mktemp -d "$tmp_parent/openbsd-vm.XXXXXXXXXX") || exit 1
	trap cleanup EXIT HUP INT TERM

	tftproot=$tmpdir/tftp
	mkdir -p "$tftproot/etc" || exit 1

	fetch_file bsd.rd "$tftproot/bsd.rd"

	case "$netboot" in
	pxe)
		fetch_file pxeboot "$tftproot/pxeboot"
		bootprog=pxeboot
		cat >"$tftproot/etc/boot.conf" <<__EOF
stty com0 115200
set tty com0
boot tftp:bsd.rd
__EOF
		;;
	efi)
		fetch_file "$efi_boot" "$tftproot/$efi_boot"
		bootprog=$efi_boot
		cat >"$tftproot/etc/boot.conf" <<__EOF
boot tftp0a:bsd.rd
__EOF
		;;
	*)	echo "TFTP netboot is not implemented for $arch" >&2
		exit 1
		;;
	esac

	bootfile=$bootprog
	case "$mode" in
	autoinstall)	bootfile=auto_install;;
	autoupgrade)	bootfile=auto_upgrade;;
	esac

	if [ "$bootfile" != "$bootprog" ]; then
		cp "$tftproot/$bootprog" "$tftproot/$bootfile" || exit 1
	fi
}

set_netdev() {
	net_user="user,host=$host_addr,hostname=$vm_hostname,domainname=$vm_domain,hostfwd=::${ssh_port}-:22"

	if [ -n "$tftproot" ]; then
		net_user="$net_user,tftp=$tftproot,bootfile=$bootfile"
	fi

	case "$mode" in
	autoinstall|autoupgrade)
		net_user="$net_user,guestfwd=tcp:$http_addr:80-cmd:$workdir/dummy-httpd.sh"
		;;
	esac
	if [ -n "$miniroot" ]; then
		net_user="$net_user,guestfwd=tcp:$http_addr:80-cmd:$workdir/dummy-httpd.sh"
	fi

	if [ -n "$net_legacy_model" ]; then
		net_args="-net nic,model=$net_legacy_model -net $net_user"
	else
		netdev="user,id=net0,${net_user#user,}"
		net_args="-netdev $netdev"
		net_args="$net_args -device $net_device,netdev=net0"
	fi
}

set_qemu_defaults() {
	qemu_default_args=
	has_memory=no
	has_cpus=no

	for arg do
		case "$arg" in
		-m|-m=*)		has_memory=yes;;
		-smp|-smp=*)	has_cpus=yes;;
		esac
	done

	[ "$has_memory" = yes ] ||
	    qemu_default_args="$qemu_default_args -m $qemu_memory"
	[ "$has_cpus" = yes ] ||
	    qemu_default_args="$qemu_default_args -smp $qemu_cpus"
}

mode=run
dry_run=no
snapshot=no
release=

while getopts nzmiuR:s opt; do
	case "$opt" in
	n)	dry_run=yes;;
	z)	set_mode shrink;;
	m)	set_mode manual;;
	i)	set_mode autoinstall;;
	u)	set_mode autoupgrade;;
	R)	release=$OPTARG;;
	s)	snapshot=yes;;
	*)	usage;;
	esac
done
shift $((OPTIND - 1))

[ "$snapshot" = no ] || [ -z "$release" ] || usage
case "$mode" in
run|shrink)
	[ "$snapshot" = no ] && [ -z "$release" ] || usage
	;;
*)
	[ "$snapshot" = yes ] || [ -n "$release" ] || usage
	;;
esac
[ $# -ge 1 ] || usage

arch=$1
shift
block_device=
net_legacy_model=
netboot=
efi_boot=
installer=tftp
qemu_disk_args=if=none,id=hd0
qemu_miniroot_disk_args=if=ide,index=1
qemu_disk_device_args=
qemu_miniroot_device_args=
tmpdir=
tmpdisk=
tftproot=
bootfile=
miniroot=
miniroot_boot_device=
miniroot_boot_file=
installurl=
workdir=$(pwd)
tmp_parent=${TMPDIR:-/tmp}
vm_domain=$(hostname)
vm_hostname=obsd-$arch.$vm_domain

case "$mode" in
manual|autoinstall|autoupgrade)
	if [ $# -gt 0 ] && [ "${1#-}" = "$1" ]; then
		installurl=$1
		shift
	fi
	;;
esac

set_arch
set_qemu_defaults "$@"

case "$mode" in
run)
	require_disk
	;;
shrink)
	require_disk
	shrink_disk "$@"
	exit
	;;
manual)
	ensure_disk
	if [ "$installer" = miniroot ]; then
		setup_miniroot
	else
		setup_tftp
	fi
	;;
autoinstall)
	require_tftp
	ensure_disk
	setup_tftp
	;;
autoupgrade)
	require_tftp
	require_disk
	setup_tftp
	;;
esac

set_netdev

qemu_boot_args=
if [ "$mode" != run ]; then
	qemu_boot_args="-no-reboot"
fi
if [ -n "$miniroot" ]; then
	[ -n "$miniroot_boot_device" ] &&
	    qemu_boot_args="-prom-env boot-device=$miniroot_boot_device $qemu_boot_args"
	[ -n "$miniroot_boot_file" ] &&
	    qemu_boot_args="-prom-env boot-file=$miniroot_boot_file $qemu_boot_args"
elif [ -n "$tftproot" ]; then
	[ "$netboot" = pxe ] &&
	    qemu_boot_args="-boot once=n,reboot-timeout=1 $qemu_boot_args"
fi
qemu_shutdown_args="-action shutdown=poweroff"

if [ -n "$miniroot" ]; then
	run_command "$qemu" $qemu_args $qemu_default_args \
	    $qemu_boot_args $qemu_shutdown_args \
	    -drive "file=$miniroot,format=raw,$qemu_miniroot_disk_args" \
	    $qemu_miniroot_device_args \
	    -drive "file=$disk,format=qcow2,$qemu_disk_args" \
	    $qemu_disk_device_args \
	    $net_args \
	    "$@"
elif [ -n "$block_device" ]; then
	run_command "$qemu" $qemu_args $qemu_default_args \
	    $qemu_boot_args $qemu_shutdown_args \
	    -drive "file=$disk,format=qcow2,$qemu_disk_args" \
	    -device "$block_device,drive=hd0,bootindex=1" \
	    $net_args \
	    "$@"
else
	run_command "$qemu" $qemu_args $qemu_default_args \
	    $qemu_boot_args $qemu_shutdown_args \
	    -hda "$disk" \
	    $net_args \
	    "$@"
fi
