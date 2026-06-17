# Orange Pi Zero 2W normal boot. Generated to boot.scr by gen-boot-scr.sh.
# Boots the kernel + DTB from the squashfs rootfs partition (mmc 0:1).
setenv bootargs console=ttyS0,115200 console=tty1 consoleblank=0 \
	root=/dev/mmcblk0p1 rootfstype=squashfs ro rootwait cma=256M loglevel=7

setenv fdtfile allwinner/sun50i-h618-orangepi-zero2w.dtb

echo "Loading kernel and DTB from squashfs rootfs (mmc 0:1)..."
load mmc 0:1 ${kernel_addr_r} /boot/Image
load mmc 0:1 ${fdt_addr_r} /boot/dtb/${fdtfile}
fdt addr ${fdt_addr_r}
booti ${kernel_addr_r} - ${fdt_addr_r}
