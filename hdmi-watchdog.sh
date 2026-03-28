#!/bin/bash
# HDMI Watchdog v3 - detects Samsung TV via I2C, triggers udev + kscreen-doctor fallback
# Bridges the gap until the kernel DRM patch is upstream
# (kernel currently doesn't send uevents for force-enabled connectors on HPD)

HDMI_I2C_BUS=1
HDMI_EDID_ADDR=0x50
OUTPUT_ID="1"
CHECK_INTERVAL=10
COOLDOWN=30
LAST_TOGGLE=0
TV_WAS_GONE=false

recover_hdmi() {
    local now=$(date +%s)
    local elapsed=$((now - LAST_TOGGLE))
    if [[ $elapsed -lt $COOLDOWN ]]; then
        return
    fi

    logger -t hdmi-watchdog "Samsung TV back on I2C, triggering link re-training"

    # Method 1: Send udev change event (triggers patched KWin modeset)
    udevadm trigger --action=change /sys/class/drm/card1-HDMI-A-1 2>/dev/null

    # Method 2: kscreen-doctor fallback (works even without KWin patch)
    sleep 3
    # Check if KWin's modeset already fixed it by trying I2C again
    if ! i2cget -y $HDMI_I2C_BUS $HDMI_EDID_ADDR 0x00 > /dev/null 2>&1; then
        logger -t hdmi-watchdog "KWin modeset insufficient, using kscreen-doctor fallback"
        kscreen-doctor output.$OUTPUT_ID.disable 2>/dev/null
        sleep 2
        kscreen-doctor output.$OUTPUT_ID.enable \
            output.$OUTPUT_ID.mode.1 \
            output.$OUTPUT_ID.position.1920,0 \
            output.$OUTPUT_ID.scale.1.7 \
            output.$OUTPUT_ID.priority.1 2>/dev/null
    fi

    LAST_TOGGLE=$(date +%s)
    logger -t hdmi-watchdog "HDMI recovery complete"
}

while true; do
    if i2cget -y $HDMI_I2C_BUS $HDMI_EDID_ADDR 0x00 > /dev/null 2>&1; then
        # TV is responding
        if [[ "$TV_WAS_GONE" == "true" ]]; then
            # TV just came back! Trigger recovery
            recover_hdmi
            TV_WAS_GONE=false
        fi
    else
        # TV not responding
        if [[ "$TV_WAS_GONE" == "false" ]]; then
            logger -t hdmi-watchdog "Samsung TV stopped responding on I2C (switched input?)"
            TV_WAS_GONE=true
        fi
    fi
    sleep $CHECK_INTERVAL
done
