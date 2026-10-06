#!/system/bin/sh
# Restore properties captured before the first active apply, then reload the
# stock audio service. The module is removed after this script returns.
MODDIR="${0%/*}"
CORE="$MODDIR/aurora_core.sh"

if [ -f "$MODDIR/aurora.log" ]; then
    echo "[$(date '+%H:%M:%S')] uninstall requested" >> "$MODDIR/aurora.log"
fi

if [ -f "$CORE" ]; then
    # shellcheck disable=SC1090,SC1091
    . "$CORE"
    if command -v aurora_restore_props >/dev/null 2>&1; then
        aurora_restore_props
    fi
fi

setprop ctl.restart audioserver 2>/dev/null
rm -rf "$MODDIR/data" "$MODDIR/.apply.lock" "$MODDIR/module_status" 2>/dev/null
exit 0
