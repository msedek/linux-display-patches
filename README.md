# Linux Display Patches: HDMI Link Re-training for Force-enabled Connectors

## Problem

When using a TV as an HDMI monitor with `video=HDMI-A-1:e` (force-enabled connector), switching the TV to built-in apps (Netflix, etc.) causes the HDMI link to die. The TV stops listening on its HDMI receiver, but the GPU thinks the output is still active. When the TV returns to the HDMI input, the link doesn't re-negotiate because no component detects the change.

### Root cause (multi-layer)

1. **Kernel DRM**: `check_connector_changed()` in `drm_probe_helper.c` doesn't send uevents for force-enabled connectors because the driver's `detect()` returns "connected" (forced), so the epoch counter never increments.

2. **KWin**: Even if a "change" udev event arrives, `DrmGpu::updateOutputs()` sees the connector is still connected and does nothing. It only forces modeset when `linkStatus == Bad`, which NVIDIA doesn't set.

3. **NVIDIA driver**: Correctly handles `connector->force` in `detect()` (returns `forceConnected`), but this means HPD events are silently swallowed.

## Patches

### Patch 1: Kernel DRM (`drm_probe_helper.c`)

**Target**: `drivers/gpu/drm/drm_probe_helper.c` (upstream kernel)

When `check_connector_changed()` processes a force-enabled connector, increment the epoch counter and return `true` to ensure the hotplug uevent reaches userspace. This allows compositors to trigger link re-training.

### Patch 2: KWin DRM backend

**Target**: `src/backends/drm/` (KDE KWin)

- Adds `DrmConnector::isHdmi()` accessor
- In `DrmGpu::updateOutputs()`, when a hotplug event arrives for an HDMI connector that's still connected, sets `m_forceModeset = true` to trigger link re-training via the existing modeset pipeline

### Watchdog (bridge until upstream)

`hdmi-watchdog.sh` — Userspace daemon that polls I2C to detect TV state changes. When the TV comes back, sends `udevadm trigger --action=change` + `kscreen-doctor` fallback.

## Testing

Tested on:
- **GPU**: NVIDIA RTX 5070 Ti (nvidia-drm, open kernel module)
- **TV**: Samsung 75" 4K via HDMI-A-1 (force-enabled)
- **Monitor**: DisplayPort DP-2
- **OS**: CachyOS (Arch-based), kernel 6.19.10, KWin 6.6.3, Wayland
- **Driver**: NVIDIA 595.58.03

## Files

```
0001-drm-probe-helper-signal-hotplug-for-force-enabled-connectors.patch  # kernel
0002-kwin-drm-force-modeset-on-hdmi-hotplug-for-link-retraining.patch    # kwin
hdmi-watchdog.sh          # userspace bridge
hdmi-watchdog.service     # systemd unit
90-kwin-hold.hook         # pacman hook to prevent updates
```

## Status

- [ ] Local testing complete
- [ ] Kernel patch submitted to dri-devel
- [ ] KWin patch submitted to KDE GitLab
