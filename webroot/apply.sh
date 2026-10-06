#!/system/bin/sh
# Apply the configuration written by WebUI. When --stdin is supplied, this
# script owns the lock before committing the new configuration, so a busy
# service cannot leave a half-written file behind.

MODDIR="${0%/*}"
MODDIR="${MODDIR%/webroot}"
CONF="$MODDIR/aurora.conf"
CORE="$MODDIR/aurora_core.sh"
STATUS="$MODDIR/module_status"

[ -f "$CORE" ] || { echo "ERROR=missing_core"; exit 1; }

LOCK="$MODDIR/.apply.lock"
if ! mkdir "$LOCK" 2>/dev/null; then
    _owner=""
    [ -f "$LOCK/pid" ] && _owner="$(cat "$LOCK/pid" 2>/dev/null)"
    if [ -z "$_owner" ] || ! kill -0 "$_owner" 2>/dev/null; then
        rm -rf "$LOCK" 2>/dev/null
        mkdir "$LOCK" 2>/dev/null || {
            echo "STATUS=BUSY"
            echo "MESSAGE=音频正在应用上一项改动"
            [ -f "$STATUS" ] && cat "$STATUS"
            exit 3
        }
    else
        echo "STATUS=BUSY"
        echo "MESSAGE=音频正在应用上一项改动"
        [ -f "$STATUS" ] && cat "$STATUS"
        exit 3
    fi
fi
echo "$$" > "$LOCK/pid"
trap 'rm -rf "$LOCK" 2>/dev/null' EXIT
trap 'rm -rf "$LOCK" 2>/dev/null; exit 130' HUP INT TERM

if [ "$1" = "--stdin" ]; then
    _tmp="$CONF.tmp.$$"
    if ! cat > "$_tmp"; then
        rm -f "$_tmp" 2>/dev/null
        echo "STATUS=CONFIG_ERROR"
        echo "MESSAGE=无法读取新配置"
        exit 1
    fi
    chmod 0644 "$_tmp" 2>/dev/null
    if ! mv -f "$_tmp" "$CONF"; then
        rm -f "$_tmp" 2>/dev/null
        echo "STATUS=CONFIG_ERROR"
        echo "MESSAGE=无法提交新配置"
        exit 1
    fi
fi

if [ ! -f "$CONF" ]; then
    echo "STATUS=CONFIG_ERROR"
    echo "MESSAGE=missing_config"
    exit 1
fi

# shellcheck disable=SC1090,SC1091
. "$CORE"
aurora_log "webui apply start"
aurora_apply_all "$CONF" webui
_code=$?
aurora_write_status "$STATUS"
cat "$STATUS"
aurora_log "webui apply done code=$_code props=$AURORA_PROP_OK/$AURORA_PROP_FAIL"
exit "$_code"
