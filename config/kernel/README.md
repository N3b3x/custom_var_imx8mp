# config/kernel/

Kernel configuration fragments: every `*.cfg` here is merged on top of
`imx8_var_defconfig` when the kernel `.config` is created.

```
# example: config/kernel/debug.cfg
CONFIG_DYNAMIC_DEBUG=y
# CONFIG_DRM_IMX_LCDIF is not set
```

After changing fragments: `FORCE_CONFIG=1 ./build.sh kernel`
