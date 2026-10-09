# 12 · Board tour: a real board, explained

[Docs](README.md) › **12 · Board tour**

This is a guided tour of a live board running this repository's Alpine image,
with **real output** captured over the serial console and an explanation of
each result. Use it to know what "normal" looks like, and to spot what's
different on your board.

> **Board used:** VAR-SOM-MX8M-PLUS rev 1.2 (part `VSM-MX8MP-249B`, 4 GB) on
> a Symphony carrier, booted from SD. Values differ on DART or SMARC modules,
> and with other module options.

**Contents:** [Identity](#1-who-am-i) · [CPU & thermal](#2-cpu-memory-and-temperature) ·
[Processes](#3-whats-running) · [Drivers](#4-drivers-and-modules) ·
[Storage](#5-storage) · [Network](#6-network) · [I2C map](#7-the-i2c-map-what-chips-are-on-the-board) ·
[Display, input, audio](#8-display-input-audio-video) · [Time](#9-time-and-the-rtc) ·
[Logs](#10-logs) · [What's not working and why](#11-whats-not-working-on-this-board-and-why)

---

## 1. Who am I?

```console
# uname -a
Linux imx8mp-var-dart 6.18.20-custom #2 SMP PREEMPT Thu Oct  8 18:39:51 MDT 2026 aarch64 Linux
# cat /proc/device-tree/model; echo
Variscite VAR-SOM-MX8M-PLUS on Symphony-Board
# cat /proc/cmdline
console=ttymxc1,115200 root=/dev/mmcblk1p1 rootwait rw cma=704M cma_name=linux,cma
# cat /sys/devices/soc0/soc_id /sys/devices/soc0/revision
i.MX8MP
1.1
```

| Value | Meaning |
| --- | --- |
| `6.18.20-custom` | the kernel built by `./build.sh kernel` (`-custom` = `KERNEL_LOCALVERSION`) |
| `#2 SMP PREEMPT` | build number 2, multi-core, preemptible (good latency) |
| `aarch64` | 64-bit ARM |
| `Symphony-Board` model | U-Boot detected a VAR-SOM and loaded `imx8mp-var-som-1.x-symphony.dtb` |
| `console=ttymxc1` | U-Boot picked UART2 for this module. The login follows it automatically |
| `root=/dev/mmcblk1p1` | running from the SD card's first partition |
| `cma=704M` | memory reserved for the GPU/VPU/camera (contiguous buffers), sized by U-Boot from the 4 GB of RAM |
| `i.MX8MP` `1.1` | SoC and silicon revision |

The hostname says `imx8mp-var-dart` because that's the default `TARGET_HOSTNAME`.
It's only a name; change it in `config/local.conf`.

## 2. CPU, memory and temperature

```console
# nproc
4
# cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_available_frequencies
1200000 1600000 1800000
# cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor
ondemand
# free -m
              total        used        free      shared  buff/cache   available
Mem:           3649          51        3584           0          14        3521
# grep -E "CmaTotal|CmaFree" /proc/meminfo
CmaTotal:         720896 kB
CmaFree:          715412 kB
# for z in /sys/class/thermal/thermal_zone*; do echo "$(cat $z/type) $(cat $z/temp) passive=$(cat $z/trip_point_0_temp) critical=$(cat $z/trip_point_1_temp)"; done
soc-thermal 57000 passive=85000 critical=95000
cpu-thermal 57000 passive=85000 critical=95000
```

- **4 Cortex-A53 cores** that step between 1.2, 1.6 and 1.8 GHz. `ondemand`
  raises the frequency under load.
- **3.6 of 4 GB visible:** about 450 MB never reach the allocator: 256 MB
  reserved for the GPU and 15 MB for the DSP (see `OF: reserved mem` at the
  top of `dmesg`), plus the kernel itself and DMA bounce buffers. The 704 MB
  CMA area *is* counted as free until a driver uses it.
- **Only 51 MB used:** an idle Alpine system is tiny.
- **57 °C idle**, no heatsink. At **85 °C** the kernel starts throttling the
  CPU (passive trip); at **95 °C** it shuts down (critical). A heatsink is
  recommended for sustained load.

## 3. What's running?

```console
# ps -o pid,ppid,user,stat,vsz,rss,args | grep -v "\["
PID   PPID  USER     STAT VSZ  RSS  COMMAND
    1     0 root     S    1692  908 /sbin/init
  128     1 root     S    1692  840 /bin/login -- root
  129     1 root     S    1692  780 /sbin/getty 38400 tty1
  132   128 root     S    1784 1164 -sh
# ps | wc -l
112
# pstree
init-+-getty
     `-login---sh---pstree
```

- **About 6 userspace processes; the other ~106 are kernel threads** (shown in
  `[brackets]` by `ps`), which is normal.
- `init` (PID 1) started everything from `/etc/inittab`.
- On the serial console, `getty` turned into `login` and then into your
  shell, `-sh` (the leading `-` marks a login shell). `getty` on `tty1` waits
  for a login on the screen.
- With the current image you'll also see `syslogd -C512`, `klogd` and
  `mdev -d` (logging and hotplug).
- RSS ~1 MB each: everything is BusyBox, one shared ~900 KB binary.

`top` shows the same live (`Q` quits):

```text
Mem: 92840K used, 3643812K free, 512K shrd, 2176K buff, 5444K cached
CPU:   0% usr   2% sys   0% nic  95% idle   0% io   0% irq   2% sirq
Load average: 0.02 0.07 0.08 1/128 1352
```

The load average of 0.02 means the board is idle (4.0 would be all four cores busy).

## 4. Drivers and modules

```console
# lsmod | wc -l
28
# lsmod | awk 'NR>1{print $1}' | tr '\n' ' '
ads7846 dw_hdmi_cec extcon_ptn5150 snd_soc_imx_hdmi snd_soc_fsl_sai imx_pcm_dma snd_soc_fsl_utils
rtc_ds1307 ov5640 imx_sdma caam_jr caam ... flexcan can_dev imx8_media_dev snd_soc_wm8904 ...
```

Most drivers are built into the kernel. These ~27 are **modules**, loaded
at boot by `/sbin/coldplug`: it reads each device's `modalias` from `/sys` and
runs `modprobe` (what `udev` does on bigger distros).

| Module | Hardware it drives |
| --- | --- |
| `imx_sdma` | the SoC's DMA engines; loads `/lib/firmware/imx/sdma/sdma-imx7d.bin`. SPI and audio need it |
| `rtc_ds1307` | the DS1337 real-time clock on the carrier (`/dev/rtc0`) |
| `snd_soc_fsl_sai`, `snd_soc_wm8904` | audio interface + the WM8904 codec (headphone/line) |
| `snd_soc_imx_hdmi` | audio over HDMI |
| `ads7846` | resistive touchscreen controller (on SPI) |
| `extcon_ptn5150` | USB-C connector role detection |
| `caam*` | hardware crypto engine (AES, SHA, RNG) |
| `flexcan`, `can_dev` | CAN bus → `can0` |
| `ov5640`, `imx8_media_dev` | MIPI camera (only works with a camera attached) |

> If `lsmod` is empty on your board, you're running an image built before the
> coldplug fix. Run `/sbin/coldplug` if it exists, or rebuild the rootfs.

## 5. Storage

```console
# cat /proc/partitions
 179        0   30535680 mmcblk2
 179       32       4096 mmcblk2boot0
 179       64       4096 mmcblk2boot1
 179       96   31395840 mmcblk1
 179       97   31387648 mmcblk1p1
# df -h /
Filesystem                Size      Used Available Use% Mounted on
/dev/root                29.5G     63.4M     27.9G   0% /
# blkid
/dev/mmcblk1p1: LABEL="root" UUID="1c0bf4fd-..." TYPE="ext4"
# fdisk -l /dev/mmcblk2
Disk /dev/mmcblk2: 29 GB, 31268536320 bytes, 61071360 sectors
Disk /dev/mmcblk2 doesn't contain a valid partition table
```

| Device | What it is |
| --- | --- |
| `mmcblk1` (32 GB) | the SD card. One partition, grown to the full card by `flash --expand` |
| `mmcblk1p1` = `/dev/root` | the running root filesystem: **63 MB used** |
| `mmcblk2` (29 GB) | the module's **eMMC**. **Empty on this board** (no partition table) |
| `mmcblk2boot0/1` | the eMMC's two 4 MB hardware boot partitions |

Because the eMMC is empty, setting the boot switch to eMMC would boot nothing.
To install the system there, see [07 · Installing to the on-module eMMC](07-flashing-and-boot.md#installing-to-the-on-module-emmc).

## 6. Network

```console
# ip link
2: eth0: <BROADCAST,MULTICAST> mtu 1500 qdisc noop state DOWN qlen 1000
    link/ether f8:dc:7a:cf:06:ad brd ff:ff:ff:ff:ff:ff
3: eth1: <BROADCAST,MULTICAST> mtu 1500 qdisc noop state DOWN qlen 1000
    link/ether f8:dc:7a:cf:06:ac brd ff:ff:ff:ff:ff:ff
4: can0: <NOARP40000> mtu 16 qdisc noop state DOWN qlen 10
# for i in eth0 eth1; do echo "$i $(basename $(readlink /sys/class/net/$i/device/driver)) $(basename $(readlink /sys/class/net/$i/device))"; done
eth0 imx-dwmac 30bf0000.ethernet
eth1 fec 30be0000.ethernet
# ip link set eth0 up; ip link set eth1 up
imx-dwmac 30bf0000.ethernet eth0: cannot attach to PHY (error: -ENODEV)
ADIN1300 stmmac-1:05: attached PHY driver (mii_bus:phy_addr=stmmac-1:05, irq=POLL)
```

| Interface | Controller | PHY | On this board |
| --- | --- | --- | --- |
| `eth0` | EQoS (`imx-dwmac`, also does TSN) | on the module, MDIO address 4 | ❌ **no PHY found**: this module variant has no second PHY populated |
| `eth1` | FEC (`fec`) | ADIN1300 on the carrier, MDIO address 5 | ✅ **use this port** |
| `can0` | FlexCAN | carrier transceiver | ✅ present |

All interfaces are **down** until you bring one up. Alpine doesn't start
networking by itself:

```sh
ip link set eth1 up
cat /sys/class/net/eth1/carrier      # 1 = cable plugged in and link up, 0 = no link
udhcpc -i eth1                       # get an address
```

## 7. The I2C map: what chips are on the board

Without installing anything, `/sys` lists every I2C chip the device tree
declares, and whether a driver claimed it:

```sh
for d in /sys/bus/i2c/devices/[0-9]*; do
  printf "%-8s %-14s driver=%s\n" $(basename $d) $(cat $d/name) $(basename "$(readlink $d/driver)" 2>/dev/null)
done
```

```text
0-001a   wm8904         driver=wm8904        audio codec
0-0025   pca9450c       driver=nxp-pca9450   PMIC (power supplies of the module)
2-0020   pca9534        driver=pca953x       GPIO expander (carrier: LEDs, buttons, resets)
2-003c   ov5640         driver=              camera: no camera attached → fails to power on
2-003d   ptn5150        driver=ptn5150       USB-C controller
3-0021   pcal6408       driver=              GPIO expander: does NOT answer on this carrier (see §11)
3-002e   st33ktpm2xi2c  driver=              TPM: waits for 3-0021
3-0038   edt-ft5206     driver=edt_ft5x06    capacitive touchscreen
3-0068   ds1337         driver=rtc-ds1307    real-time clock
```

`X-00YY` means bus X, address 0xYY. `driver=` empty means no driver is
attached, either because the chip didn't respond or because a dependency is
missing. The bus numbers: `i2c-0` = I2C1, `i2c-2` = I2C3, `i2c-3` = I2C4
(`cat /sys/bus/i2c/devices/i2c-*/name` shows the controller addresses).

With `i2c-tools` installed, `i2cdetect -y 3` actually probes the bus and
shows what answers (`UU` = in use by a driver, `--` = nothing there).

## 8. Display, input, audio, video

```console
# for c in /sys/class/drm/card*-*; do echo "$(basename $c): $(cat $c/status) $(head -1 $c/modes)"; done
card1-HDMI-A-1: disconnected
card1-LVDS-1: connected 800x480
# for i in /sys/class/input/input*; do echo "$(basename $i): $(cat $i/name)"; done
input0: 30370000.snvs:snvs-powerkey
input1: generic ft5x06 (7b)
input2: gpio-keys
input3: audio-hdmi HDMI Jack
input4: ADS7846 Touchscreen
# cat /proc/asound/cards
 0 [audiohdmi      ]: audio-hdmi - audio-hdmi
 1 [wm8904audio    ]: simple-card - wm8904-audio
# ls /dev | grep -E "galcore|hantro|video|watchdog"
galcore mxc_hantro mxc_hantro_vc8000e video0 video1 video2 watchdog watchdog0
```

| Item | Meaning |
| --- | --- |
| `LVDS-1 connected 800x480` | the LVDS panel is where the penguins appear |
| `HDMI-A-1 disconnected` | no monitor on HDMI (it's detected when plugged in) |
| `snvs-powerkey`, `gpio-keys` | the ON/OFF key and the carrier's buttons |
| `ft5x06`, `ADS7846` | capacitive and resistive touch controllers. Use the one your panel has |
| sound cards 0, 1 | HDMI audio and the WM8904 codec (`aplay -l` after `apk add alsa-utils`) |
| `galcore` | GPU / NPU driver (Vivante) |
| `mxc_hantro`, `mxc_hantro_vc8000e` | video decoder / encoder (VPU) |
| `video0..2` | V4L2 devices: VPU and the ISI (camera/colour-conversion engine) |
| `watchdog0` | hardware watchdog: resets the board if not fed (BusyBox `watchdog`) |

Try them:

```sh
cat /dev/urandom > /dev/fb0                     # fills the LVDS screen with noise (Ctrl+C), proves the display path
evtest                                          # (apk add evtest) pick input1/input4 and touch the screen
```

## 9. Time and the RTC

```console
# date
Thu Jan  1 00:39:04 UTC 1970          ← before: nothing ever set the clock
# dmesg | grep rtc
rtc-ds1307 3-0068: SET TIME!          ← the RTC was never set either
rtc-ds1307 3-0068: registered as rtc0
# date -u -s "2026-10-09 02:08:08"; hwclock -u -w
# hwclock -u
Fri Oct  9 02:08:08 2026  0.000000 seconds
```

The image reads the RTC at boot (`hwclock -u -s`) and writes it back at
shutdown. Set the time once, as above (or with `ntpd -q -n -p pool.ntp.org`
when online), and it survives reboots. On power-off it keeps running from the
carrier's RTC backup supply (coin cell or supercap, if fitted).

## 10. Logs

```console
# logger "hello from the docs check"
# logread | tail -3
Jan  1 00:39:20 imx8mp-var-dart kern.info kernel: [   13.332700] imx8mp-blk-ctrl 32f10000.blk-ctrl: sync_state() pending due to 33800000.pcie
Jan  1 00:39:20 imx8mp-var-dart kern.notice kernel: [   92.421383] random: crng init done
Jan  1 00:39:21 imx8mp-var-dart user.notice root: hello from the docs check
```

- `logread` = system log (kernel messages via `klogd`, plus programs and
  `logger`). `logread -f` follows it live.
- Each line shows the date, host, facility.level (`kern.info`,
  `user.notice`), source and message.
- The log is kept **in RAM** (512 KiB ring buffer) and lost at reboot. No SD
  card wear.
- `dmesg` = kernel messages only, since boot.

## 11. What's not working on this board, and why

```console
# mount -t debugfs none /sys/kernel/debug
# cat /sys/kernel/debug/devices_deferred
3-002e          i2c: supplier 3-0021 not ready
33800000.pcie   platform: supplier 3-0021 not ready
32c00000.bus:camera
```

| Symptom | Cause | What to do |
| --- | --- | --- |
| `pca953x 3-0021: failed writing register: -6` at boot, TPM and PCIe "deferred" | the device tree for Symphony declares a **PCAL6408 GPIO expander at I2C4 0x21**, used for the TPM reset, PCIe reset and LVDS RGB select. It doesn't answer on this carrier, probably an older Symphony revision without it | if you don't need TPM/PCIe, ignore it. Otherwise check your Symphony revision with Variscite, or make a custom DTS that drops `pcal6408` and its users ([08](08-customizing.md#a-device-tree-for-your-carrier-board)) |
| `eth0: cannot attach to PHY (error: -ENODEV)`, `MDIO device at address 4 is missing` | no Ethernet PHY at address 4 on this module (option not populated) | use `eth1`. If your module should have it, check the part number options |
| `ov5640 ... failed to power on`, `32c00000.bus:camera` deferred | no camera module connected | attach the camera, or ignore it |
| `optee optee: OP-TEE api uid mismatch` (U-Boot) | OP-TEE isn't part of this build | harmless |
| `mmc0: Failed to initialize a non-removable card` | Wi-Fi/BT SDIO slot: not populated on this module, or needs firmware | harmless if you don't use Wi-Fi |

**Rule of thumb:** "deferred" means "waiting for something". Read
`devices_deferred` to see *what* it's waiting for, then check whether that part
exists on your hardware.

---

← [11 · Using the board](11-using-the-board.md) · [Index](README.md) · [13 · Secure world](13-secure-world.md) →
