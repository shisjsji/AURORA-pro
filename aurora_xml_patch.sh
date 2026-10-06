#!/system/bin/sh
# Patch a live device Dolby XML without replacing its profiles, tunings, or
# safety nodes. Arguments:
#   source output preset strength route user_geq spatial curve profile_id

SRC="$1"
OUT="$2"
PRESET="$3"
STRENGTH="$4"
ROUTE="$5"
USER_GEQ="$6"
SPATIAL="$7"
CURVE="$8"
PROFILE_ID="$9"

[ -f "$SRC" ] || exit 1
[ -n "$OUT" ] || exit 1
OUT_DIR="${OUT%/*}"
[ "$OUT_DIR" = "$OUT" ] && OUT_DIR=.
mkdir -p "$OUT_DIR" 2>/dev/null || exit 1
TMP="${OUT}.tmp.$$"

DIALOG_ADD=0
SPACE_ADD=0
BASS_ADD=0
case "$STRENGTH" in
    balanced) DIALOG_ADD=1; SPACE_ADD=3; BASS_ADD=2 ;;
    max) DIALOG_ADD=3; SPACE_ADD=10; BASS_ADD=5 ;;
    *) DIALOG_ADD=2; SPACE_ADD=6; BASS_ADD=3 ;;
esac
case "$PRESET" in
    voice|vocal_clear) DIALOG_ADD=$((DIALOG_ADD + 3)) ;;
    movie|cinema_body) SPACE_ADD=$((SPACE_ADD + 3)) ;;
esac
case "$PRESET" in
    movie|music|harman_kardon|harman_warm|jbl_punch) BASS_ADD=$((BASS_ADD + 2)) ;;
esac

awk -v preset="$PRESET" \
    -v route="$ROUTE" \
    -v spatial="$SPATIAL" \
    -v user="$USER_GEQ" \
    -v curve="$CURVE" \
    -v target_profile="$PROFILE_ID" \
    -v dialog_add="$DIALOG_ADD" \
    -v space_add="$SPACE_ADD" \
    -v bass_add="$BASS_ADD" '
BEGIN {
    split(curve, c, ",")
    split(user, u, ",")
    for (i = 1; i <= 10; i++) {
        if (u[i] == "") u[i] = 0
        u[i] += 0
        if (u[i] > 12) u[i] = 12
        if (u[i] < -12) u[i] = -12
    }
    if (target_profile == "") target_profile = -1
    target_profile += 0
    print_marker = 1
    in_profile = 0
    in_endpoint = 0
    in_tuning = 0
    profile_id = -1
    endpoint_id = ""
    tuning_endpoint = ""
}
function attr(line, name,    pat, token) {
    pat = name "=\"[-+]?[0-9]+\""
    if (match(line, pat)) {
        token = substr(line, RSTART, RLENGTH)
        sub(name "=\"", "", token)
        sub("\"", "", token)
        return token + 0
    }
    return 0
}
function text_attr(line, name,    pat, token) {
    pat = name "=\"[^\"]*\""
    if (match(line, pat)) {
        token = substr(line, RSTART, RLENGTH)
        sub("^" name "=\"", "", token)
        sub("\"$", "", token)
        return token
    }
    return ""
}
function replace_attr(line, name, old, new,    token) {
    token = name "=\"" old "\""
    sub(token, name "=\"" new "\"", line)
    return line
}
function replace_text_attr(line, name, value,    pat, token) {
    pat = name "=\"[^\"]*\""
    token = name "=\"" value "\""
    sub(pat, token, line)
    return line
}
function replace_bool_attr(line, value) {
    return replace_text_attr(line, "value", value)
}
function clamp(v, low, high) {
    if (v < low) return low
    if (v > high) return high
    return v
}
function target_profile_scope() {
    return (in_profile && profile_id == target_profile)
}
function speaker_scope() {
    if (in_tuning) return (tuning_endpoint == "speaker")
    return (in_endpoint && endpoint_id == "speaker" && target_profile_scope())
}
{
    line = $0

    if (print_marker) {
        print line
        print "<!-- AURORA_RUNTIME_PATCH=5.7.0; source=live-device-xml; preset=" preset " -->"
        print_marker = 0
        next
    }

    if (line ~ /<profile[[:space:]>]/) {
        in_profile = 1
        profile_id = attr(line, "id")
        endpoint_id = ""
        in_endpoint = 0
    }
    if (line ~ /<endpoint_type[[:space:]>]/) {
        in_endpoint = 1
        endpoint_id = text_attr(line, "id")
    }
    if (line ~ /<tuning[[:space:]>]/) {
        in_tuning = 1
        tuning_endpoint = text_attr(line, "endpoint_type")
    }
    if (line ~ /<audio-optimizer-bands[[:space:]>]/) {
        band_count = 0
    }

    # Only the active profile speaker endpoint and standalone speaker
    # tunings are audible on the phone dual speakers. External endpoints
    # remain stock so Bluetooth, USB and headphones are not double-processed.
    if (line ~ /<band_optimizer[[:space:]]/ && speaker_scope()) {
        band_count++
        delta = c[band_count] + 0
        ui = int((band_count + 1) / 2)
        if (ui >= 1 && ui <= 10) delta += (u[ui] * 32)
        if (route == "wireless" && delta > 0) delta = int(delta * 0.82)
        if (route == "wired" && delta > 0) delta = int(delta * 0.90)
        delta = clamp(delta, -384, 384)
        left = attr(line, "gain_left")
        right = attr(line, "gain_right")
        line = replace_attr(line, "gain_left", left, left + delta)
        line = replace_attr(line, "gain_right", right, right + delta)
    }

    # Peak protection is scoped to the same speaker path. Keep every other
    # OEM protection and high-pass node unchanged.
    if (line ~ /<peak-value[[:space:]]/ && speaker_scope()) {
        peak = attr(line, "value")
        if (peak > 256) line = replace_attr(line, "value", peak, 256)
    }

    if (line ~ /<surround-boost[[:space:]]/ && speaker_scope()) {
        old_value = attr(line, "value")
        line = replace_attr(line, "value", old_value, clamp(old_value + space_add, 0, 256))
    }
    if (line ~ /<dialog-enhancer-amount[[:space:]]/ && speaker_scope()) {
        old_value = attr(line, "value")
        line = replace_attr(line, "value", old_value, clamp(old_value + dialog_add, 0, 32))
    }
    if (line ~ /<bass-enhancer-boost[[:space:]]/ && speaker_scope()) {
        old_value = attr(line, "value")
        # Newer OEM files can use 192 or higher; 64 was an accidental legacy
        # ceiling that erased the stock bass calibration.
        line = replace_attr(line, "value", old_value, clamp(old_value + bass_add, 0, 256))
    }

    # The XML uses textual booleans, so numeric-only replacement silently
    # failed before. Explicitly set both states on the active speaker path.
    if (line ~ /<(surround-decoder-enable|virtualizer-enable)[[:space:]]/ && speaker_scope()) {
        line = replace_bool_attr(line, spatial == "true" ? "true" : "false")
    }

    print line

    if (line ~ /<\/endpoint_type[[:space:]>]/) {
        in_endpoint = 0
        endpoint_id = ""
    }
    if (line ~ /<\/profile[[:space:]>]/) {
        in_profile = 0
        in_endpoint = 0
        profile_id = -1
        endpoint_id = ""
    }
    if (line ~ /<\/tuning[[:space:]>]/) {
        in_tuning = 0
        tuning_endpoint = ""
    }
}
' "$SRC" > "$TMP" || {
    rm -f "$TMP"
    exit 1
}

if [ ! -s "$TMP" ] || ! grep -q "AURORA_RUNTIME_PATCH=" "$TMP"; then
    rm -f "$TMP"
    exit 1
fi

# A line-oriented patch must never drop or duplicate optimizer bands.
SRC_BANDS="$(grep -c '<band_optimizer[[:space:]]' "$SRC" 2>/dev/null)"
OUT_BANDS="$(grep -c '<band_optimizer[[:space:]]' "$TMP" 2>/dev/null)"
if [ "$SRC_BANDS" != "$OUT_BANDS" ]; then
    rm -f "$TMP"
    exit 1
fi

mv -f "$TMP" "$OUT" || {
    rm -f "$TMP"
    exit 1
}
chmod 0644 "$OUT" 2>/dev/null
exit 0
