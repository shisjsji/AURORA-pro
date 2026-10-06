#!/system/bin/sh
# shellcheck disable=SC2034
# AURORA v5.7.0 installer. The package contains no static Dolby XML: the
# runtime copies the device's own /odm XML on first boot and patches that copy.

SKIPUNZIP=0

ui_print ""
ui_print "  AURORA 双扬声器调音 v5.7.0"
ui_print "  基于设备原厂 Dolby XML，适配 Magisk / KernelSU"
ui_print ""

if [ -z "$MODPATH" ]; then
    abort "MODPATH is not set"
fi

# Keep a user's existing tuning when Magisk/KernelSU installs this build as an
# update. A fresh install has no old file, so the packaged defaults remain.
_old_conf="/data/adb/modules/AURORA-pro/aurora.conf"
if [ -f "$_old_conf" ] && [ "$_old_conf" != "$MODPATH/aurora.conf" ]; then
    cp -fp "$_old_conf" "$MODPATH/aurora.conf" 2>/dev/null
fi

for _required in \
    "$MODPATH/aurora_core.sh" \
    "$MODPATH/aurora_xml_patch.sh" \
    "$MODPATH/aurora.conf" \
    "$MODPATH/webroot/index.html" \
    "$MODPATH/webroot/apply.sh"; do
    if [ ! -f "$_required" ]; then
        abort "Missing module file: $_required"
    fi
done

if [ -f /odm/etc/dolby/dax-default.xml ]; then
    ui_print "  [OK] Device ODM Dolby XML detected"
elif [ -f /vendor/etc/dolby/dax-default.xml ]; then
    ui_print "  [OK] Vendor Dolby XML fallback detected"
else
    ui_print "  [!] Dolby XML will be checked again after boot"
fi

if [ -d "$MODPATH/webroot" ]; then
    set_perm_recursive "$MODPATH/webroot" 0 0 0755 0644
fi
set_perm "$MODPATH/aurora_core.sh" 0 0 0755
set_perm "$MODPATH/aurora_xml_patch.sh" 0 0 0755
set_perm "$MODPATH/webroot/apply.sh" 0 0 0755
set_perm "$MODPATH/service.sh" 0 0 0755
set_perm "$MODPATH/post-fs-data.sh" 0 0 0755
set_perm "$MODPATH/post-mount.sh" 0 0 0755
set_perm "$MODPATH/uninstall.sh" 0 0 0755
set_perm "$MODPATH/aurora.conf" 0 0 0644
set_perm "$MODPATH/system.prop" 0 0 0644

ui_print "  [OK] Runtime patcher and mobile WebUI installed"
ui_print "  [i] Reboot once, then open the module WebUI"
ui_print ""
