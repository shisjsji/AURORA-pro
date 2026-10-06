#!/system/bin/sh
MODDIR="${0%/*}"
# shellcheck disable=SC1090,SC1091
. "$MODDIR/aurora_core.sh"
aurora_log "post-fs-data: preparing live Dolby XML"
LOCK="$MODDIR/.apply.lock"
if mkdir "$LOCK" 2>/dev/null; then
    echo "$$" > "$LOCK/pid"
    trap 'rm -rf "$LOCK" 2>/dev/null' EXIT
    aurora_bind_early "$MODDIR/aurora.conf"
else
    aurora_log "post-fs-data: apply lock is busy; service will retry"
fi
exit 0
