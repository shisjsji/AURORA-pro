#!/system/bin/sh
MODDIR="${0%/*}"
# shellcheck disable=SC1090,SC1091
. "$MODDIR/aurora_core.sh"

until [ "$(getprop sys.boot_completed 2>/dev/null)" = "1" ]; do
    sleep 2
done
sleep 3

LOCK="$MODDIR/.apply.lock"
if mkdir "$LOCK" 2>/dev/null; then
    echo "$$" > "$LOCK/pid"
    trap 'rm -rf "$LOCK" 2>/dev/null' EXIT
    aurora_log "service: applying runtime configuration"
    aurora_apply_all "$MODDIR/aurora.conf" service
else
    _owner=""
    [ -f "$LOCK/pid" ] && _owner="$(cat "$LOCK/pid" 2>/dev/null)"
    if [ -z "$_owner" ] || ! kill -0 "$_owner" 2>/dev/null; then
        rm -rf "$LOCK" 2>/dev/null
        if mkdir "$LOCK" 2>/dev/null; then
            echo "$$" > "$LOCK/pid"
            trap 'rm -rf "$LOCK" 2>/dev/null' EXIT
            aurora_log "service: recovered stale apply lock"
            aurora_apply_all "$MODDIR/aurora.conf" service
        else
            aurora_log "service: another apply is active"
        fi
    else
        aurora_log "service: another apply is active"
    fi
fi
exit 0
