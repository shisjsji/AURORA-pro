#!/system/bin/sh
# AURORA v5.7.0 shared runtime.
# The device ODM Dolby XML remains the source of truth. AURORA creates a
# private copy, changes only the speaker path, binds it over the live file,
# and restores OEM properties when the feature is disabled or uninstalled.

AURORA_VERSION="5.7.0"
MODDIR="${MODDIR:-${0%/*}}"
[ -d "$MODDIR" ] || MODDIR="/data/adb/modules/AURORA-pro"
CONF="${AURORA_CONF:-$MODDIR/aurora.conf}"
AURORA_LOG="${AURORA_LOG:-$MODDIR/aurora.log}"
AURORA_STATUS="${AURORA_STATUS:-$MODDIR/module_status}"
RUNTIME_DIR="$MODDIR/data/runtime"
PROP_SNAPSHOT="$RUNTIME_DIR/original_props"
FINGERPRINT_FILE="$RUNTIME_DIR/last-fingerprint"

AURORA_PROP_OK=0
AURORA_PROP_FAIL=0
AURORA_PROP_SKIP=0
AURORA_CONFIG_LOADED=false
AURORA_DOLBY_XML_OK=false
AURORA_DOLBY_XML_ACTIVE=false
AURORA_DOLBY_XML_MOUNT=none
AURORA_DOLBY_XML_BASE=none
AURORA_DOLBY_XML_MODE=unavailable
AURORA_SPATIAL_XML_OK=false
AURORA_SPATIAL_XML_ACTIVE=false
AURORA_SPATIAL_XML_MOUNT=none
AURORA_PROPS_ACTIVE=false
AURORA_APPLY_PHASE=none
AURORA_EFFECTIVE_ROUTE=speaker
AURORA_ROUTE_CONFIDENCE=low
AURORA_PROFILE_ID=0
AURORA_PROFILE_NAME=Dynamic
AURORA_AUDIO_RESTART=skipped
AURORA_AUDIO_REASON=none
AURORA_AUDIO_CHANGED=false
AURORA_TUNING=unavailable
AURORA_PROP_READBACK=unknown
AURORA_MAP_MODE=preserved
AURORA_CURVE=0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
AURORA_RP=""

aurora_log() {
    [ -n "$AURORA_LOG" ] || return 0
    _dir="${AURORA_LOG%/*}"
    [ "$_dir" = "$AURORA_LOG" ] && _dir=.
    mkdir -p "$_dir" 2>/dev/null
    echo "[$(date '+%H:%M:%S')] $1" >> "$AURORA_LOG"
}

aurora_trim() {
    echo "$1" | tr -d '\r' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//'
}

aurora_bool() {
    case "$1" in
        1|true|TRUE|True|yes|on) echo true ;;
        *) echo false ;;
    esac
}

aurora_clamp_int() {
    _value="$1"
    _low="$2"
    _high="$3"
    case "$_value" in
        ''|*[!0-9-]*) _value=0 ;;
    esac
    [ "$_value" -lt "$_low" ] 2>/dev/null && _value="$_low"
    [ "$_value" -gt "$_high" ] 2>/dev/null && _value="$_high"
    echo "$_value"
}

aurora_find_resetprop() {
    AURORA_RP=""
    for _rp in \
        /data/adb/magisk/resetprop \
        /data/adb/ksu/bin/resetprop \
        /data/adb/ksu/bin/resetprop_magisk \
        /data/adb/ap/bin/resetprop; do
        if [ -x "$_rp" ]; then
            AURORA_RP="$_rp"
            break
        fi
    done
    if [ -z "$AURORA_RP" ] && command -v resetprop >/dev/null 2>&1; then
        AURORA_RP="$(command -v resetprop)"
    fi
    [ -n "$AURORA_RP" ] || aurora_log "resetprop unavailable; setprop fallback"
}

aurora_resetprop_set() {
    _key="$1"
    _value="$2"
    if [ -n "$AURORA_RP" ]; then
        "$AURORA_RP" "$_key" "$_value" 2>/dev/null
    else
        setprop "$_key" "$_value" 2>/dev/null
    fi
}

aurora_resetprop_delete() {
    _key="$1"
    if [ -n "$AURORA_RP" ]; then
        "$AURORA_RP" --delete "$_key" 2>/dev/null
    else
        setprop "$_key" "" 2>/dev/null
    fi
}

aurora_set_prop() {
    _key="$1"
    _value="$2"
    if [ "$(getprop "$_key" 2>/dev/null)" = "$_value" ]; then
        AURORA_PROP_OK=$((AURORA_PROP_OK + 1))
        AURORA_PROP_SKIP=$((AURORA_PROP_SKIP + 1))
        return 0
    fi
    aurora_resetprop_set "$_key" "$_value"
    if [ "$(getprop "$_key" 2>/dev/null)" != "$_value" ]; then
        setprop "$_key" "$_value" 2>/dev/null
    fi
    if [ "$(getprop "$_key" 2>/dev/null)" = "$_value" ]; then
        AURORA_PROP_OK=$((AURORA_PROP_OK + 1))
        return 0
    fi
    AURORA_PROP_FAIL=$((AURORA_PROP_FAIL + 1))
    aurora_log "property write failed: $_key=$_value"
    return 1
}

aurora_snapshot_props() {
    mkdir -p "$RUNTIME_DIR" 2>/dev/null || return 1
    [ -f "$PROP_SNAPSHOT" ] && return 0
    _tmp="$PROP_SNAPSHOT.tmp.$$"
    : > "$_tmp" || return 1
    for _key in \
        persist.vendor.audio.effectimplenter \
        persist.vendor.audio.misound.disable \
        persist.audio.effect.device_map \
        persist.audio.dolby.profile; do
        _value="$(getprop "$_key" 2>/dev/null)"
        if [ -n "$_value" ]; then
            printf '%s|1|%s\n' "$_key" "$_value" >> "$_tmp"
        else
            printf '%s|0|\n' "$_key" >> "$_tmp"
        fi
    done
    chmod 0600 "$_tmp" 2>/dev/null
    mv -f "$_tmp" "$PROP_SNAPSHOT"
}

aurora_restore_props() {
    [ -f "$PROP_SNAPSHOT" ] || return 0
    aurora_find_resetprop
    AURORA_PROP_OK=0
    AURORA_PROP_FAIL=0
    while IFS='|' read -r _key _present _value || [ -n "$_key" ]; do
        [ -n "$_key" ] || continue
        if [ "$_present" = "1" ]; then
            aurora_set_prop "$_key" "$_value"
        else
            aurora_resetprop_delete "$_key"
            if [ -z "$(getprop "$_key" 2>/dev/null)" ]; then
                AURORA_PROP_OK=$((AURORA_PROP_OK + 1))
            else
                AURORA_PROP_FAIL=$((AURORA_PROP_FAIL + 1))
            fi
        fi
    done < "$PROP_SNAPSHOT"
    AURORA_PROP_READBACK=restored
    [ "$AURORA_PROP_FAIL" -eq 0 ]
}

aurora_load_config() {
    _file="${1:-$CONF}"
    CONF="$_file"
    PRESET_MODE=music
    DOLBY_ENABLE=true
    SPATIAL_ENABLE=true
    USER_GEQ=0,0,0,0,0,0,0,0,0,0
    ENGINE_STRENGTH=strong
    POWER_SAVE_MODE=true
    AURORA_OUTPUT_ROUTE=auto
    AUDIO_REFRESH_MODE=smart
    SUPER_BASS_MODE=false
    AURORA_SAFE_MODE=false

    if [ ! -f "$_file" ]; then
        AURORA_CONFIG_LOADED=false
        aurora_log "config missing: $_file"
        return 1
    fi

    while IFS='=' read -r _key _value || [ -n "$_key" ]; do
        _key="$(aurora_trim "$_key" | sed 's/[[:space:]]//g')"
        _value="$(aurora_trim "$_value")"
        case "$_key" in
            ''|\#*) ;;
            PRESET_MODE) PRESET_MODE="$_value" ;;
            DOLBY_ENABLE) DOLBY_ENABLE="$(aurora_bool "$_value")" ;;
            SPATIAL_ENABLE) SPATIAL_ENABLE="$(aurora_bool "$_value")" ;;
            USER_GEQ) USER_GEQ="$_value" ;;
            ENGINE_STRENGTH) ENGINE_STRENGTH="$_value" ;;
            POWER_SAVE_MODE) POWER_SAVE_MODE="$(aurora_bool "$_value")" ;;
            AURORA_OUTPUT_ROUTE) AURORA_OUTPUT_ROUTE="$_value" ;;
            AUDIO_REFRESH_MODE) AUDIO_REFRESH_MODE="$_value" ;;
            SUPER_BASS_MODE) SUPER_BASS_MODE="$(aurora_bool "$_value")" ;;
            AURORA_SAFE_MODE) AURORA_SAFE_MODE="$(aurora_bool "$_value")" ;;
        esac
    done < "$_file"

    case "$PRESET_MODE" in
        dynamic|movie|music|voice|custom|harman_kardon|xiaomi17_air|cinema_body|vocal_clear|night_soft|harman_warm|burmester_natural|bo_warm|bo_bright|jbl_punch) ;;
        *) PRESET_MODE=music ;;
    esac
    case "$ENGINE_STRENGTH" in
        balanced|strong|max) ;;
        *) ENGINE_STRENGTH=strong ;;
    esac
    case "$AURORA_OUTPUT_ROUTE" in
        auto|speaker|wired|wireless) ;;
        *) AURORA_OUTPUT_ROUTE=auto ;;
    esac
    case "$AUDIO_REFRESH_MODE" in
        smart|off|force) ;;
        *) AUDIO_REFRESH_MODE=smart ;;
    esac
    AURORA_CONFIG_LOADED=true
    return 0
}

aurora_detect_route() {
    AURORA_ROUTE_CONFIDENCE=low
    case "$AURORA_OUTPUT_ROUTE" in
        speaker|wired|wireless)
            AURORA_EFFECTIVE_ROUTE="$AURORA_OUTPUT_ROUTE"
            AURORA_ROUTE_CONFIDENCE=explicit
            return 0
            ;;
    esac

    AURORA_EFFECTIVE_ROUTE=speaker
    if command -v dumpsys >/dev/null 2>&1; then
        _audio_dump="$(dumpsys audio 2>/dev/null | tr '[:upper:]' '[:lower:]')"
        _current_line="$(echo "$_audio_dump" | grep -i 'current device:' | head -n 1)"
        [ -n "$_current_line" ] || _current_line="$(echo "$_audio_dump" | grep -iE '(^|[[:space:]])devices?:.*(speaker|a2dp|bluetooth|headphone|usb|wired|earpiece)' | head -n 1)"
        case "$_current_line" in
            *bluetooth*|*a2dp*|*ble\ headset*) AURORA_EFFECTIVE_ROUTE=wireless; AURORA_ROUTE_CONFIDENCE=explicit ;;
            *usb*|*headphone*|*wired\ headset*) AURORA_EFFECTIVE_ROUTE=wired; AURORA_ROUTE_CONFIDENCE=explicit ;;
            *speaker*|*earpiece*|*built_in*|*builtin*) AURORA_EFFECTIVE_ROUTE=speaker; AURORA_ROUTE_CONFIDENCE=explicit ;;
        esac
    fi
    aurora_log "route=$AURORA_EFFECTIVE_ROUTE confidence=$AURORA_ROUTE_CONFIDENCE"
}

aurora_find_stock_xml() {
    AURORA_DOLBY_XML_BASE=""
    for _xml in /odm/etc/dolby/dax-default.xml /vendor/etc/dolby/dax-default.xml; do
        if [ -f "$_xml" ]; then
            AURORA_DOLBY_XML_BASE="$_xml"
            break
        fi
    done
    [ -n "$AURORA_DOLBY_XML_BASE" ]
}

aurora_find_stock_spatializer() {
    AURORA_DOLBY_SPATIAL_BASE=""
    for _xml in /odm/etc/dolby/dax-default-spatializer.xml /vendor/etc/dolby/dax-default-spatializer.xml; do
        if [ -f "$_xml" ]; then
            AURORA_DOLBY_SPATIAL_BASE="$_xml"
            break
        fi
    done
    [ -n "$AURORA_DOLBY_SPATIAL_BASE" ]
}

aurora_snapshot_stock() {
    _base="$1"
    _snapshot="$2"
    [ -f "$_base" ] || return 1
    if [ -f "$_snapshot" ]; then
        [ -s "$_snapshot" ]
        return $?
    fi
    if grep -q "AURORA_RUNTIME_PATCH=" "$_base" 2>/dev/null; then
        aurora_log "refusing to snapshot AURORA-marked XML: $_base"
        return 1
    fi
    mkdir -p "${_snapshot%/*}" 2>/dev/null
    cp -fp "$_base" "$_snapshot" 2>/dev/null || return 1
    [ -s "$_snapshot" ]
}

aurora_select_profile() {
    _wanted=Dynamic
    _fallback=0
    case "$PRESET_MODE" in
        movie|cinema_body) _wanted=Movie; _fallback=1 ;;
        music|harman_kardon|xiaomi17_air|harman_warm|burmester_natural|bo_warm|bo_bright|jbl_punch) _wanted=Music; _fallback=2 ;;
        voice) _wanted=Voice; _fallback=4 ;;
        custom) _wanted=Custom; _fallback=3 ;;
        vocal_clear) _wanted=VocalClear; _fallback=8 ;;
        night_soft) _wanted=NightSoft; _fallback=9 ;;
    esac
    _line="$(grep -i '^[[:space:]]*<profile[[:space:]]' "$RUNTIME_DIR/stock-dax-default.xml" 2>/dev/null | grep -i "name=\"$_wanted\"" | head -n 1)"
    _id="$(echo "$_line" | sed -n 's/.*id="\([0-9][0-9]*\)".*/\1/p')"
    if [ -z "$_id" ]; then
        _id="$_fallback"
    fi
    AURORA_PROFILE_ID="$_id"
    AURORA_PROFILE_NAME="$_wanted"
    aurora_log "profile=$AURORA_PROFILE_ID name=$AURORA_PROFILE_NAME preset=$PRESET_MODE"
}

aurora_curve_for_preset() {
    case "$PRESET_MODE" in
        cinema_body)
            AURORA_CURVE=80,70,40,20,0,-10,10,35,60,80,90,80,70,90,110,120,90,55,30,0 ;;
        movie)
            AURORA_CURVE=100,90,68,42,16,4,0,14,34,52,66,58,42,50,70,84,68,40,18,0 ;;
        music)
            AURORA_CURVE=70,55,30,10,-5,0,15,30,60,80,100,90,70,85,100,110,90,55,30,0 ;;
        voice)
            AURORA_CURVE=20,15,0,-10,20,45,80,100,75,45,30,45,60,55,35,20,10,0,0,-10 ;;
        vocal_clear)
            AURORA_CURVE=28,24,12,4,0,2,12,30,54,72,78,76,70,88,108,122,102,70,42,18 ;;
        night_soft)
            AURORA_CURVE=28,24,14,6,0,-8,-2,8,18,24,25,20,15,14,10,6,0,0,0,-5 ;;
        harman_kardon|harman_warm)
            AURORA_CURVE=86,76,52,28,12,0,-6,8,28,46,58,50,32,22,12,2,-8,-12,-8,-8 ;;
        xiaomi17_air|burmester_natural)
            AURORA_CURVE=36,30,18,8,0,-4,2,14,30,42,48,44,38,50,66,78,64,42,22,4 ;;
        bo_warm)
            AURORA_CURVE=66,58,38,22,10,0,-4,4,18,32,42,36,24,18,10,2,-4,-8,-5,-5 ;;
        bo_bright)
            AURORA_CURVE=28,24,12,4,0,2,12,30,54,72,78,76,70,88,108,122,102,70,42,18 ;;
        jbl_punch)
            AURORA_CURVE=100,90,68,42,16,4,0,14,34,52,66,58,42,50,70,84,68,40,18,0 ;;
        custom)
            AURORA_CURVE=45,38,24,10,0,-6,0,18,36,52,58,50,40,52,68,78,56,32,14,0 ;;
        *)
            AURORA_CURVE=55,45,25,10,0,-10,0,25,50,65,70,60,50,65,80,90,65,40,20,0 ;;
    esac
    case "$ENGINE_STRENGTH" in
        balanced) AURORA_CURVE="$(echo "$AURORA_CURVE" | awk -F, 'BEGIN{OFS=","}{for(i=1;i<=NF;i++)$i=int($i*0.65)}1')" ;;
        max) AURORA_CURVE="$(echo "$AURORA_CURVE" | awk -F, 'BEGIN{OFS=","}{for(i=1;i<=NF;i++)$i=int($i*1.15)}1')" ;;
    esac
    if [ "$POWER_SAVE_MODE" = true ] && [ "$ENGINE_STRENGTH" != max ]; then
        AURORA_CURVE="$(echo "$AURORA_CURVE" | awk -F, 'BEGIN{OFS=","}{for(i=1;i<=NF;i++)$i=int($i*0.78)}1')"
        AURORA_POWER_SAVE_APPLIED=true
    else
        AURORA_POWER_SAVE_APPLIED=false
    fi
    if [ "$SUPER_BASS_MODE" = true ]; then
        AURORA_CURVE="$(echo "$AURORA_CURVE" | awk -F, 'BEGIN{OFS=","}{$1+=40;$2+=32;$3+=22;$4+=10}1')"
    fi
}

aurora_validate_xml() {
    _file="$1"
    _mode="$2"
    [ -s "$_file" ] || return 1
    grep -q '<' "$_file" 2>/dev/null || return 1
    if [ "$_mode" = patched ]; then
        grep -q "AURORA_RUNTIME_PATCH=" "$_file" 2>/dev/null || return 1
        _src_count="$(grep -c '<band_optimizer[[:space:]]' "$3" 2>/dev/null)"
        _out_count="$(grep -c '<band_optimizer[[:space:]]' "$_file" 2>/dev/null)"
        [ "$_src_count" = "$_out_count" ] || return 1
    fi
    return 0
}

aurora_prepare_xml() {
    mkdir -p "$RUNTIME_DIR" 2>/dev/null || return 1
    AURORA_DOLBY_XML_OK=false
    AURORA_SPATIAL_XML_OK=false
    AURORA_TUNING=unavailable
    if ! aurora_find_stock_xml; then
        aurora_log "no stock Dolby XML found"
        return 1
    fi
    aurora_snapshot_stock "$AURORA_DOLBY_XML_BASE" "$RUNTIME_DIR/stock-dax-default.xml" || return 1
    aurora_select_profile
    aurora_curve_for_preset
    _source="$RUNTIME_DIR/stock-dax-default.xml"
    _out="$RUNTIME_DIR/dax-default.xml"
    if [ "$AURORA_SAFE_MODE" = true ] || [ "$DOLBY_ENABLE" != true ]; then
        cp -fp "$_source" "$_out" 2>/dev/null || return 1
        AURORA_DOLBY_XML_MODE=stock
        AURORA_TUNING=stock
    else
        sh "$MODDIR/aurora_xml_patch.sh" "$_source" "$_out" \
            "$PRESET_MODE" "$ENGINE_STRENGTH" "$AURORA_EFFECTIVE_ROUTE" "$USER_GEQ" \
            "$SPATIAL_ENABLE" "$AURORA_CURVE" "$AURORA_PROFILE_ID" || return 1
        aurora_validate_xml "$_out" patched "$_source" || return 1
        AURORA_DOLBY_XML_MODE=patched
        AURORA_TUNING=patched
    fi
    AURORA_DOLBY_XML_OK=true

    if aurora_find_stock_spatializer; then
        aurora_snapshot_stock "$AURORA_DOLBY_SPATIAL_BASE" "$RUNTIME_DIR/stock-dax-default-spatializer.xml" || return 1
        _spatial_source="$RUNTIME_DIR/stock-dax-default-spatializer.xml"
        _spatial_out="$RUNTIME_DIR/dax-default-spatializer.xml"
        if [ "$AURORA_DOLBY_XML_MODE" = stock ]; then
            cp -fp "$_spatial_source" "$_spatial_out" 2>/dev/null || return 1
        else
            sh "$MODDIR/aurora_xml_patch.sh" "$_spatial_source" "$_spatial_out" \
                "$PRESET_MODE" "$ENGINE_STRENGTH" "$AURORA_EFFECTIVE_ROUTE" "$USER_GEQ" \
                "$SPATIAL_ENABLE" "$AURORA_CURVE" "$AURORA_PROFILE_ID" || return 1
            aurora_validate_xml "$_spatial_out" patched "$_spatial_source" || return 1
        fi
        AURORA_SPATIAL_XML_OK=true
    else
        AURORA_SPATIAL_XML_OK=true
        AURORA_SPATIAL_XML_MOUNT=none
    fi
    return 0
}

aurora_bind_one() {
    _src="$1"
    _dst="$2"
    [ -f "$_src" ] || return 1
    [ -f "$_dst" ] || return 1
    if grep -q " $_dst " /proc/mounts 2>/dev/null; then
        umount "$_dst" 2>/dev/null
    fi
    mount -o bind "$_src" "$_dst" 2>/dev/null || {
        aurora_log "bind failed: $_src -> $_dst"
        return 1
    }
    grep -q " $_dst " /proc/mounts 2>/dev/null
}

aurora_unbind_one() {
    _dst="$1"
    [ -n "$_dst" ] || return 0
    if grep -q " $_dst " /proc/mounts 2>/dev/null; then
        umount "$_dst" 2>/dev/null
    fi
}

aurora_unbind_runtime() {
    aurora_find_stock_spatializer
    [ -n "$AURORA_DOLBY_SPATIAL_BASE" ] && aurora_unbind_one "$AURORA_DOLBY_SPATIAL_BASE"
    aurora_find_stock_xml
    [ -n "$AURORA_DOLBY_XML_BASE" ] && aurora_unbind_one "$AURORA_DOLBY_XML_BASE"
    AURORA_DOLBY_XML_ACTIVE=false
    AURORA_SPATIAL_XML_ACTIVE=false
    AURORA_DOLBY_XML_MOUNT=none
    AURORA_SPATIAL_XML_MOUNT=none
}

aurora_bind_dolby_xml() {
    [ "$AURORA_DOLBY_XML_OK" = true ] || return 1
    aurora_find_stock_xml || return 1
    if ! aurora_bind_one "$RUNTIME_DIR/dax-default.xml" "$AURORA_DOLBY_XML_BASE"; then
        AURORA_DOLBY_XML_ACTIVE=false
        return 1
    fi
    AURORA_DOLBY_XML_ACTIVE=true
    AURORA_DOLBY_XML_MOUNT=bound
    if [ "$AURORA_SPATIAL_XML_OK" = true ] && [ -f "$RUNTIME_DIR/dax-default-spatializer.xml" ]; then
        aurora_find_stock_spatializer
        if [ -n "$AURORA_DOLBY_SPATIAL_BASE" ]; then
            if ! aurora_bind_one "$RUNTIME_DIR/dax-default-spatializer.xml" "$AURORA_DOLBY_SPATIAL_BASE"; then
                aurora_unbind_runtime
                return 1
            fi
            AURORA_SPATIAL_XML_ACTIVE=true
            AURORA_SPATIAL_XML_MOUNT=bound
        fi
    fi
    return 0
}

aurora_apply_props() {
    aurora_snapshot_props || return 1
    if [ "$AURORA_SAFE_MODE" = true ] || [ "$DOLBY_ENABLE" != true ]; then
        if aurora_restore_props; then
            AURORA_PROPS_ACTIVE=true
            return 0
        fi
        AURORA_PROPS_ACTIVE=false
        return 1
    fi
    aurora_find_resetprop
    AURORA_PROP_OK=0
    AURORA_PROP_FAIL=0
    aurora_set_prop persist.vendor.audio.effectimplenter dolby
    aurora_set_prop persist.vendor.audio.misound.disable true
    _map="$(getprop persist.audio.effect.device_map 2>/dev/null)"
    if [ -z "$_map" ]; then
        aurora_set_prop persist.audio.effect.device_map "speaker:dolby,earpiece:dolby"
        AURORA_MAP_MODE=speaker_only
    else
        AURORA_MAP_MODE=preserved
        AURORA_PROP_SKIP=$((AURORA_PROP_SKIP + 1))
    fi
    aurora_set_prop persist.audio.dolby.profile "$AURORA_PROFILE_ID"
    AURORA_PROP_READBACK="$(getprop persist.audio.dolby.profile 2>/dev/null)"
    [ "$AURORA_PROP_READBACK" = "$AURORA_PROFILE_ID" ] || AURORA_PROP_READBACK=unverified
    if [ "$AURORA_PROP_FAIL" -eq 0 ] && [ "$AURORA_PROP_READBACK" != unverified ]; then
        AURORA_PROPS_ACTIVE=true
        return 0
    fi
    AURORA_PROPS_ACTIVE=false
    return 1
}

aurora_checksum() {
    _file="$1"
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$_file" 2>/dev/null | cut -d' ' -f1
    else
        cksum "$_file" 2>/dev/null | cut -d' ' -f1
    fi
}

aurora_fingerprint() {
    _source_sum="$(aurora_checksum "$RUNTIME_DIR/stock-dax-default.xml")"
    echo "$_source_sum|$PRESET_MODE|$DOLBY_ENABLE|$AURORA_SAFE_MODE|$SPATIAL_ENABLE|$ENGINE_STRENGTH|$POWER_SAVE_MODE|$SUPER_BASS_MODE|$AURORA_EFFECTIVE_ROUTE|$AURORA_PROFILE_ID|$USER_GEQ|$AURORA_CURVE"
}

aurora_refresh_audio() {
    AURORA_AUDIO_RESTART=skipped
    AURORA_AUDIO_REASON=none
    _changed="$1"
    case "$AUDIO_REFRESH_MODE" in
        off)
            AURORA_AUDIO_REASON=disabled
            return 0
            ;;
        smart)
            if [ "$_changed" != true ]; then
                AURORA_AUDIO_REASON=unchanged
                return 0
            fi
            ;;
        force) ;;
    esac
    command -v setprop >/dev/null 2>&1 || {
        AURORA_AUDIO_REASON=setprop_unavailable
        return 1
    }
    _old_pid="$(pidof audioserver 2>/dev/null)"
    setprop ctl.restart audioserver 2>/dev/null
    AURORA_AUDIO_RESTART=requested
    AURORA_AUDIO_REASON=restart
    _n=0
    while [ "$_n" -lt 5 ]; do
        sleep 1
        _state="$(getprop init.svc.audioserver 2>/dev/null)"
        _new_pid="$(pidof audioserver 2>/dev/null)"
        if [ "$_state" = running ] && [ -n "$_new_pid" ] && [ "$_new_pid" != "$_old_pid" ]; then
            AURORA_AUDIO_RESTART=ok
            return 0
        fi
        _n=$((_n + 1))
    done
    if [ "$(getprop init.svc.audioserver 2>/dev/null)" = running ]; then
        AURORA_AUDIO_RESTART=running
        AURORA_AUDIO_REASON=running_unverified
    else
        AURORA_AUDIO_RESTART=failed
        AURORA_AUDIO_REASON=not_running
    fi
    return 1
}

aurora_write_status() {
    _file="${1:-$AURORA_STATUS}"
    _dir="${_file%/*}"
    [ "$_dir" = "$_file" ] && _dir=.
    mkdir -p "$_dir" 2>/dev/null
    _volume="$(getprop ro.config.media_vol_steps 2>/dev/null)"
    [ -n "$_volume" ] || _volume=unknown
    _state=DEGRADED
    if [ "$AURORA_APPLY_PHASE" = early ] && [ "$AURORA_DOLBY_XML_ACTIVE" = true ]; then
        _state=XML_BOUND
    elif [ "$AURORA_SAFE_MODE" = true ] || [ "$DOLBY_ENABLE" != true ]; then
        [ "$AURORA_DOLBY_XML_ACTIVE" = true ] && [ "$AURORA_PROPS_ACTIVE" = true ] && _state=STOCK
    elif [ "$AURORA_DOLBY_XML_ACTIVE" = true ] && [ "$AURORA_PROPS_ACTIVE" = true ] && { [ "$AURORA_SPATIAL_XML_ACTIVE" = true ] || [ "$AURORA_SPATIAL_XML_OK" = true ]; }; then
        _state=ACTIVE
    fi
    [ "$AURORA_CONFIG_LOADED" = true ] || _state=CONFIG_ERROR
    {
        echo "STATUS=$_state"
        echo "MODULE_VERSION=$AURORA_VERSION"
        echo "CONFIG_LOADED=$AURORA_CONFIG_LOADED"
        echo "PRESET_MODE=$PRESET_MODE"
        echo "PROFILE_ID=$AURORA_PROFILE_ID"
        echo "PROFILE_NAME=$AURORA_PROFILE_NAME"
        echo "DOLBY_ENABLE=$DOLBY_ENABLE"
        echo "SPATIAL_ENABLE=$SPATIAL_ENABLE"
        echo "SAFE_MODE=$AURORA_SAFE_MODE"
        echo "ENGINE_STRENGTH=$ENGINE_STRENGTH"
        echo "POWER_SAVE_MODE=$POWER_SAVE_MODE"
        echo "POWER_SAVE_APPLIED=$AURORA_POWER_SAVE_APPLIED"
        echo "SUPER_BASS_MODE=$SUPER_BASS_MODE"
        echo "OUTPUT_ROUTE=$AURORA_OUTPUT_ROUTE"
        echo "EFFECTIVE_ROUTE=$AURORA_EFFECTIVE_ROUTE"
        echo "ROUTE_CONFIDENCE=$AURORA_ROUTE_CONFIDENCE"
        echo "AUDIO_REFRESH_MODE=$AUDIO_REFRESH_MODE"
        echo "AUDIO_RESTART=$AURORA_AUDIO_RESTART"
        echo "AUDIO_REASON=$AURORA_AUDIO_REASON"
        echo "VOLUME_STEPS=$_volume"
        echo "XML_BASE=$AURORA_DOLBY_XML_BASE"
        echo "XML_MODE=$AURORA_DOLBY_XML_MODE"
        echo "XML_ACTIVE=$AURORA_DOLBY_XML_ACTIVE"
        echo "XML_MOUNT=$AURORA_DOLBY_XML_MOUNT"
        echo "SPATIAL_XML_OK=$AURORA_SPATIAL_XML_OK"
        echo "SPATIAL_XML_ACTIVE=$AURORA_SPATIAL_XML_ACTIVE"
        echo "SPATIAL_XML_MOUNT=$AURORA_SPATIAL_XML_MOUNT"
        echo "PROPS_ACTIVE=$AURORA_PROPS_ACTIVE"
        echo "PROP_MAP_MODE=$AURORA_MAP_MODE"
        echo "TUNING=$AURORA_TUNING"
        echo "PROP_READBACK=$AURORA_PROP_READBACK"
        echo "PROP_OK=$AURORA_PROP_OK"
        echo "PROP_FAIL=$AURORA_PROP_FAIL"
        echo "PROP_SKIP=$AURORA_PROP_SKIP"
        echo "USER_GEQ=$USER_GEQ"
        echo "CURVE=$AURORA_CURVE"
    } > "$_file"
}

aurora_apply_all() {
    _file="${1:-$CONF}"
    _reason="${2:-manual}"
    AURORA_APPLY_PHASE=full
    AURORA_PROP_OK=0
    AURORA_PROP_FAIL=0
    AURORA_PROP_SKIP=0
    AURORA_AUDIO_REASON=none
    if ! aurora_load_config "$_file"; then
        aurora_write_status "$AURORA_STATUS"
        return 1
    fi
    aurora_detect_route
    if ! aurora_prepare_xml; then
        aurora_log "prepare failed; no runtime properties written"
        aurora_write_status "$AURORA_STATUS"
        return 2
    fi
    _new_fp="$(aurora_fingerprint)"
    _old_fp=""
    [ -f "$FINGERPRINT_FILE" ] && IFS= read -r _old_fp < "$FINGERPRINT_FILE"
    [ "$_new_fp" = "$_old_fp" ] && AURORA_AUDIO_CHANGED=false || AURORA_AUDIO_CHANGED=true
    if ! aurora_bind_dolby_xml; then
        aurora_log "bind failed; restoring OEM properties"
        aurora_restore_props
        aurora_write_status "$AURORA_STATUS"
        return 2
    fi
    if ! aurora_apply_props; then
        aurora_log "property apply failed; unbinding runtime XML"
        aurora_unbind_runtime
        aurora_restore_props
        aurora_write_status "$AURORA_STATUS"
        return 2
    fi
    if [ "$_reason" = webui ] || [ "$_reason" = service ]; then
        aurora_refresh_audio "$AURORA_AUDIO_CHANGED"
    fi
    if [ "$AURORA_DOLBY_XML_ACTIVE" = true ] && [ "$AURORA_PROPS_ACTIVE" = true ]; then
        printf '%s\n' "$_new_fp" > "$FINGERPRINT_FILE"
    fi
    aurora_write_status "$AURORA_STATUS"
    aurora_log "apply reason=$_reason state=$(sed -n 's/^STATUS=//p' "$AURORA_STATUS" | head -n 1) xml=$AURORA_DOLBY_XML_MODE props=$AURORA_PROP_OK/$AURORA_PROP_FAIL"
    grep -q '^STATUS=ACTIVE$' "$AURORA_STATUS" 2>/dev/null || grep -q '^STATUS=STOCK$' "$AURORA_STATUS" 2>/dev/null
}

aurora_bind_early() {
    AURORA_APPLY_PHASE=early
    if ! aurora_load_config "${1:-$CONF}"; then
        aurora_write_status "$AURORA_STATUS"
        return 1
    fi
    aurora_detect_route
    if aurora_prepare_xml && aurora_bind_dolby_xml; then
        aurora_write_status "$AURORA_STATUS"
        return 0
    fi
    aurora_write_status "$AURORA_STATUS"
    return 1
}
