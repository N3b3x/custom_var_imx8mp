# 15 · Source tour: read the code that boots your board

[Docs](README.md) › **15 · Source tour**

> **In this guide:** the handful of source files that matter, in the order they
> run, with **real excerpts** from the exact commits this repo builds. After
> this you can open any of them and explain what it does. All paths are
> relative to `build/src/` (run `./build.sh all` once to get the sources).

![The code that runs, in order](images/source-map.svg)

**Stops:** [SPL start](#1-spl-board_init_f-the-first-c-code) ·
[DDR](#2-spl-identifying-the-module-and-training-ddr) · [TZASC](#3-spl-turning-trustzone-memory-control-on) ·
[BL31 setup](#4-bl31-security-rules-and-the-hand-off-to-u-boot) ·
[PSCI, both sides](#5-psci-cpu_on-both-sides-of-the-smc) ·
[U-Boot board detection](#6-u-boot-board_late_init-who-am-i) ·
[findfdt](#7-u-boot-environment-choosing-the-device-tree) ·
[A driver](#8-linux-a-driver-binds-to-a-device-tree-node) ·
[init](#9-linux-starting-pid-1) · [This repo's scripts](#10-this-repos-scripts)

> **How to read C you don't know:** find the function name, read its comments,
> then follow only the calls whose names match the job you care about.
> `grep -rn "function_name(" build/src/<repo>` finds definitions and callers.

---

## 1. SPL: `board_init_f()`, the first C code

**File:** `uboot-imx/board/variscite/imx8mp_var_dart/spl.c` · runs in OCRAM, EL3 (the CPU's
highest privilege level, [what that means](13-secure-world.md#2-who-runs-where-exception-levels-and-worlds)), with no DDR yet.

```c
void board_init_f(ulong dummy)
{
	/* Clear the BSS. */
	memset(__bss_start, 0, __bss_end - __bss_start);

	arch_cpu_init();
	timer_init();
	ret = spl_early_init();
	board_early_init_f();

	/* Can run only after UART clock is enabled */
	preloader_console_init();          // ← "U-Boot SPL 2026.04 …" appears now
	…
	enable_tzc380();                   // → §3
	board_id = var_detect_board_id();  // DART, SOM or SMARC?
	…
	/* PMIC initialization */
	power_init_board();                // set DDR / core voltages
	/* DDR initialization */
	spl_dram_init();                   // → §2
	board_init_r(NULL, 0);             // load the FIT, jump to BL31
}
```

What to notice:

- The **`_f`** means "before relocation": there's no DDR, so the stack and data
  live in OCRAM. `board_init_r` ("after") runs once DDR works.
- **Order matters:** clocks → UART (so you can see errors) → **PMIC** (DDR needs
  its voltage) → **DDR** → only then load big images.
- `preloader_console_init()` is why the very first line on the console is
  `U-Boot SPL …`.

## 2. SPL: identifying the module and training DDR

**Same file**, `spl_dram_init()`:

```c
static void spl_dram_init(void)
{
	board_id = var_detect_board_id();
	if (board_id == BOARD_ID_DART)
		carrier_eeprom_bus = CARRIER_EEPROM_BUS_DART;
	else if (board_id == BOARD_ID_SOM)
		carrier_eeprom_bus = CARRIER_EEPROM_BUS_SOM;
	…
	/* EEPROM initialization */
	var_eeprom_read_header(&eeprom);
	var_carrier_eeprom_read(carrier_eeprom_bus, CARRIER_EEPROM_ADDR, &carrier_eeprom);
	var_eeprom_adjust_dram(&eeprom, &dram_timing);   // RAM size/timings per SoM
	ddr_init(&dram_timing);                           // drivers/ddr/imx/imx8m/ddr_init.c
}
```

What to notice:

- **One `imx-boot.bin` serves every module** because the SPL reads the SoM's
  EEPROM and *adjusts the DDR timings* before training. Your 4 GiB VAR-SOM and
  a 2 GiB DART use the same binary.
- `ddr_init()` is where the four `lpddr4_pmu_train_*` blobs from NXP are fed to
  the DDR PHY ([14 · Acronyms](14-acronyms.md#2-memory): "Training").

## 3. SPL: turning TrustZone memory control on

**File:** `uboot-imx/arch/arm/mach-imx/imx8m/soc.c`

```c
void enable_tzc380(void)
{
	/* Enable TZASC and lock setting */
	setbits_le32(&gpr->gpr[10], GPR_TZASC_EN);
	setbits_le32(&gpr->gpr[10], GPR_TZASC_EN_LOCK);
	…
	/*
	 * set Region 0 attribute to allow secure and non-secure
	 * read/write permission. Found some masters like usb dwc3
	 * controllers can't work with secure memory.
	 */
	writel(0xf0000000, TZASC_BASE_ADDR + 0x108);
}
```

What to notice:

- The TZASC is **switched on and locked** (it can't be turned off until reset),
  but region 0 is set to *everything allowed*. That's the "open" state shown
  in the [TrustZone diagram](images/trustzone.svg). OP-TEE would add a
  secure-only region on top.

## 4. BL31: security rules and the hand-off to U-Boot

**File:** `imx-atf/plat/imx/imx8m/imx8mp/imx8mp_bl31_setup.c` · EL3.

```c
void bl31_early_platform_setup2(…)
{
	/* Enable CSU NS access permission */
	for (i = 0; i < 64; i++) {
		mmio_write_32(IMX_CSU_BASE + i * 4, 0x00ff00ff);   // every peripheral: both worlds
	}
	…
	bl33_image_ep_info.pc = PLAT_NS_IMAGE_OFFSET;          // 0x4020_0000 = U-Boot proper
	bl33_image_ep_info.spsr = get_spsr_for_bl33_entry();   // → EL2 if the CPU has it
	SET_SECURITY_STATE(bl33_image_ep_info.h.attr, NON_SECURE);
#if defined(SPD_opteed) || defined(SPD_trusty)
	/* Populate entry point information for BL32 */
	bl32_image_ep_info.pc = BL32_BASE;                     // 0x5600_0000, OP-TEE
	…
#endif
}
```

What to notice:

- **This is where U-Boot's address, privilege level and world are decided.**
  `NON_SECURE` + EL2 is why U-Boot and Linux start in the normal world at EL2.
- The `#if defined(SPD_opteed)` block is compiled out in this build: no BL32.
  It's the switch the [OP-TEE roadmap](13-secure-world.md#7-adding-op-tee-roadmap) turns on.
- `bl31_tzc380_setup()` in the same file re-programs the same open TZASC region.

## 5. PSCI CPU_ON: both sides of the `smc`

At boot Linux starts CPUs 1–3. This is the same operation seen from both ends,
the normal-world caller and the secure-world handler:

**Caller:** `linux-imx/drivers/firmware/psci/psci.c` (EL1)

```c
static int psci_0_2_cpu_on(unsigned long cpuid, unsigned long entry_point)
{
	return __psci_cpu_on(PSCI_FN_NATIVE(0_2, CPU_ON), cpuid, entry_point);
}
…
__invoke_psci_fn_smc(unsigned long function_id, unsigned long arg0, …)
{
	struct arm_smccc_res res;
	arm_smccc_smc(function_id, arg0, arg1, arg2, 0, 0, 0, 0, &res);  // ← the smc #0
	return res.a0;
}
```

**Handler:** `imx-atf/plat/imx/imx8m/imx8m_psci_common.c` (EL3)

```c
int imx_pwr_domain_on(u_register_t mpidr)
{
	core_id = MPIDR_AFFLVL0_VAL(mpidr);              // which core: 1, 2 or 3
	imx_set_cpu_secure_entry(core_id, base_addr);    // where it starts (BL31)
	imx_set_cpu_pwr_on(core_id);                     // GPC: power the core up
	return PSCI_E_SUCCESS;                           // → x0 = 0 after eret
}
```

What to notice:

- `PSCI_FN_NATIVE(0_2, CPU_ON)` = `0xC400_0003`: the function ID in `x0`
  ([SMC table](13-secure-world.md#4-what-an-smc-does)).
- TF-A's generic PSCI code (`lib/psci/psci_on.c`) validates the request, then
  calls this platform hook through `.pwr_domain_on = imx_pwr_domain_on`
  (`imx8mp_psci.c`). Generic code plus a small platform hook is the pattern
  throughout TF-A.
- The new core starts *in BL31* (secure), which then ERETs it to Linux's
  `entry_point` in the normal world. Your log line `CPU1: Booted secondary
  processor` is the end of this round trip. See the [SMC flow](images/smc-flow.svg).

## 6. U-Boot `board_late_init()`: "who am I?"

**File:** `uboot-imx/board/variscite/imx8mp_var_dart/imx8mp_var_dart.c` · EL2, DDR.

```c
int board_late_init(void)
{
	…
	snprintf(sdram_size_str, SDRAM_SIZE_STR_LEN, "%d", (int)(gd->ram_size / 1024 / 1024));
	env_set("sdram_size", sdram_size_str);            // → ramsize_check → cma=704M

	board_id = var_detect_board_id();
	if (board_id == BOARD_ID_SOM) {
		env_set("board_name", "VAR-SOM-MX8M-PLUS");
		env_set("console", "ttymxc1,115200");         // ← why your console is ttymxc1
		var_carrier_eeprom_read(CARRIER_EEPROM_BUS_SOM, …);
	} else if (board_id == BOARD_ID_DART) {
		env_set("board_name", "DART-MX8M-PLUS");      // console stays ttymxc0
	…
```

What to notice:

- C code **writes environment variables**, and the boot *script* (§7) reads
  them. That's how hardware detection reaches the boot logic. Print them at
  the U-Boot prompt: `printenv board_name sdram_size console`.

## 7. U-Boot environment: choosing the device tree

**File:** `uboot-imx/board/variscite/imx8mp_var_dart/imx8mp_var_dart.env` (compiled
into U-Boot; the text dump is `build/deploy/u-boot-initial-env`). `findfdt`,
reformatted for reading:

```sh
if test ${fdt_file} = undefined; then
    if test ${board_name} = VAR-SOM-MX8M-PLUS; then
        setenv module_name imx8mp-var-som;   setenv carrier_default symphony;
    elif test ${board_name} = DART-MX8M-PLUS; then
        setenv module_name imx8mp-var-dart;  setenv carrier_default sonata;
    else
        setenv module_name imx8mp-var-smarc; setenv carrier_default echo;
    fi
    if test ${carrier_name} = undefined; then setenv carrier_name ${carrier_default}; fi
    setenv fdt_suffix ""
    if test ${som_rev} -lt 2; then
        if test ${board_name} != VAR-SMARC-MX8M-PLUS; then setenv fdt_suffix -1.x; fi
    elif test ${som_has_wbe} = 1; then setenv fdt_suffix -wbe; fi
    setenv fdt_file ${module_name}${fdt_suffix}-${carrier_name}.dtb
fi
```

What to notice:

- U-Boot's script language is a small shell: `if test`, `setenv`, `run`.
- `fdt_file = undefined` is the trigger, so setting `fdt_file` yourself
  (prompt or `uEnv.txt`) **skips the whole detection**. That's the official
  way to use your own DTB. See the [U-Boot flow](images/uboot-bootcmd.svg) and
  the [environment layers](images/uboot-env.svg).

## 8. Linux: a driver binds to a device-tree node

![From one line of device tree to a working driver](images/dt-to-driver.svg)

**File:** `linux-imx/drivers/rtc/rtc-ds1307.c`

```c
static const struct of_device_id ds1307_of_match[] = {
	…
	{
		.compatible = "dallas,ds1337",        // ← same string as in the .dts
		.data = (void *)ds_1337
	},
	…
};

static struct i2c_driver ds1307_driver = {
	.driver = {
		.name	= "rtc-ds1307",
		.of_match_table = ds1307_of_match,    // match against DT compatible
	},
	.probe		= ds1307_probe,               // called on a match
	.id_table	= ds1307_id,
};
module_i2c_driver(ds1307_driver);             // register with the I2C core

/* inside ds1307_probe(): */
	ds1307->rtc = devm_rtc_allocate_device(ds1307->dev);
	…
	err = devm_rtc_register_device(ds1307->rtc);   // → /dev/rtc0
```

What to notice:

- **Every Linux driver has this shape:** a match table, a `probe()` and a
  registration macro. Learn it once and you can read any driver.
- `module_i2c_driver` means "I drive I2C devices", so the I2C core offers it
  every I2C node from the DT. The `compatible` decides.
- Because this is a module, `depmod` turns the match table into a line in
  `modules.alias`, which is how `/sbin/coldplug` or udev knows to load it.

## 9. Linux: starting PID 1

**File:** `linux-imx/init/main.c` · end of `kernel_init()`:

```c
	if (!try_to_run_init_process("/sbin/init") ||
	    !try_to_run_init_process("/etc/init") ||
	    !try_to_run_init_process("/bin/init") ||
	    !try_to_run_init_process("/bin/sh"))
		return 0;

	panic("No working init found.  Try passing init= option to kernel. "
```

What to notice:

- This is the **hand-over from kernel to userspace**, and the
  `Run /sbin/init as init process` line in your boot log.
- The fallback list explains a classic error: a broken rootfs ends in
  `No working init found`. `init=/bin/sh` in `kernelargs` gives you a rescue shell.

## 10. This repo's scripts

| File | Read it to learn |
| --- | --- |
| `scripts/lib/common.sh` → `run()` | how every command is printed with its reason, and why `--dry-run` works: the same function either prints or executes |
| `scripts/lib/common.sh` → `git_checkout()` | shallow-fetching one pinned commit, and protecting your local edits |
| `scripts/uboot.sh` → `do_mkimage()` | staging files into `iMX8M/` exactly like Variscite's Yocto recipe, then `make … flash_evk` |
| `scripts/kernel.sh` → `dtb_targets()` | reading the DTB list out of the kernel Makefile (composite overlays) |
| `scripts/image.sh` | building a root-owned ext4 image and a partitioned disk image without sudo |
| `scripts/rootfs/debian-customize.sh` | turning a bare Debian into a bootable board image, line by line |

```bash
# the fastest way to read a script: let it explain itself
./build.sh --dry-run uboot | less -R
```

---

← [14 · Acronyms](14-acronyms.md) · [Index](README.md) · [Main README](../README.md) →
