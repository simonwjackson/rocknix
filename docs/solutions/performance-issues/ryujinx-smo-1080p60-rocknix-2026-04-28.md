---
title: Configure Super Mario Odyssey in Ryujinx for 1080p output and 60fps target on ROCKNIX
date: 2026-04-28
category: performance-issues
module: ROCKNIX Ryujinx Switch emulation
problem_type: performance_issue
component: tooling
symptoms:
  - Super Mario Odyssey runs but default docked rendering is 900p rather than 1080p.
  - A direct 1920x1080 SMO patch exists but is marked unstable by the mod authors.
  - Ryujinx needs per-title mods plus global graphics settings to produce a stable 1080p output path.
root_cause: config_error
resolution_type: config_change
severity: low
tags: [rocknix, ryujinx, super-mario-odyssey, switch, 1080p, 60fps, vulkan, performance]
---

# Configure Super Mario Odyssey in Ryujinx for 1080p output and 60fps target on ROCKNIX

## Problem

Super Mario Odyssey was playable in Ryujinx on ROCKNIX/SM8550, but the goal was to tune it for a practical 1080p/60fps experience. The important constraint is that SMO already targets 60fps, while its normal docked resolution is 1600x900; forcing native 1920x1080 directly is available as a mod option but is documented as unstable.

## Symptoms

- Ryujinx launched SMO successfully after keys, firmware, input, and save conversion were fixed.
- Online references and the SMO upscaling patch notes identify the default game resolution as 1600x900 in docked mode.
- The `Upscaling Settings` mod includes multiple resolution options and labels the full 1920x1080 patch as unstable.
- Before installing a per-title mod, Ryujinx logs only showed the mod search paths, not an enabled SMO patch.

## What Didn't Work

- Treating Ryujinx's global resolution scale alone as the whole solution is not ideal. Scaling SMO's default 1600x900 by 2x renders above 1080p and wastes GPU headroom on a handheld.
- Enabling the mod's native `1920x1080 docked` section is risky because the patch itself labels that mode unstable and crash-prone.
- Placing a patch archive on disk is insufficient. Ryujinx needs the mod unpacked into its title-specific mod directory and enabled for the game.

## Solution

Use the stable SMO upscaling strategy: patch the game to render at 960x540 in docked mode, then set Ryujinx resolution scale to `2x`. This produces a 1920x1080 output path while keeping the internal work lower than a direct 1080p patch.

### 1. Install the SMO upscaling mod

The downloaded GameBanana `Upscaling Settings` archive contained:

```text
Upscaling Settings/exefs/1.0.0.pchtxt
Upscaling Settings/exefs/1.3.0.pchtxt
```

Install it under Ryujinx's per-title mod directory:

```text
/storage/.config/Ryujinx/mods/contents/0100000000010000/1080p60-Perf/exefs/
```

For SMO v1.0.0, enable these sections in `1.0.0.pchtxt`:

```text
// Disable Dynamic Resolution (required)
@enabled

// Disable FXAA (recommended)
@enabled

// Disable Vignette Motion Blur (recommended)
@enabled

// 960x540 docked (upscale 2x to 1920x1080)
@enabled

// 1280x720 docked (upscale 3x to 3840x2160)
@disabled

// [UNSTABLE] 1920x1080 docked (upscale 2x to 3840x2160)
@disabled
```

Enable the same sections in `1.3.0.pchtxt` so the configuration survives a future game update.

Ryujinx can also be told explicitly that the mod is enabled:

```json
{
  "mods": [
    {
      "path": "/storage/.config/Ryujinx/mods/contents/0100000000010000/1080p60-Perf",
      "enabled": true
    }
  ]
}
```

Store that at:

```text
/storage/.config/Ryujinx/games/0100000000010000/mods.json
```

### 2. Set Ryujinx global graphics settings

Back up `Config.json` first:

```text
/storage/.config/Ryujinx/Config.json.bak-before-1080p60-20260428221539
```

Then apply these settings:

```json
{
  "graphics_backend": "Vulkan",
  "backend_threading": "Auto",
  "docked_mode": true,
  "res_scale": 2,
  "res_scale_custom": 1.0,
  "aspect_ratio": "Fixed16x9",
  "max_anisotropy": -1,
  "anti_aliasing": "None",
  "scaling_filter": "Bilinear",
  "scaling_filter_level": 80,
  "enable_shader_cache": true,
  "enable_macro_hle": true,
  "enable_ptc": true,
  "enable_low_power_ptc": false,
  "memory_manager_mode": "HostMappedUnsafe",
  "use_hypervisor": true,
  "ignore_missing_services": true,
  "enable_fs_integrity_checks": false,
  "enable_vsync": true,
  "enable_custom_vsync_interval": false,
  "tick_scalar": 0,
  "start_fullscreen": true,
  "hide_cursor": 1,
  "window_startup": {
    "window_size_width": 1920,
    "window_size_height": 1080,
    "window_maximized": true
  }
}
```

The applied configuration was recorded at:

```text
/storage/smo-1080p60-config.log
```

### 3. Verify Ryujinx sees the mod and settings

On launch, logs should show the expected graphics settings:

```text
Configuration LogValueChange: ResScale set to: 2
Configuration LogValueChange: EnableDockedMode set to: True
Configuration LogValueChange: MemoryManagerMode set to: HostMappedUnsafe
Configuration LogValueChange: IgnoreMissingServices set to: True
```

For mod verification, look for Ryujinx mod loader lines such as:

```text
ModLoader QueryContentsDir: Searching mods for Application 0100000000010000
ModLoader: Found enabled mod '1080p60-Perf'
ModLoader: Matching IPSwitch patch '1.0.0.pchtxt'
```

If those patch lines do not appear, inspect:

```text
/storage/.config/Ryujinx/mods/contents/0100000000010000/1080p60-Perf/exefs/
/storage/.config/Ryujinx/games/0100000000010000/mods.json
/storage/.config/Ryujinx/Logs/*.log
```

## Why This Works

SMO's native 60fps target is already the right frame-rate goal. The performance problem is avoiding unnecessary internal resolution work while still presenting a 1080p image.

The stable path is:

```text
SMO internal patch: 960x540 docked
Ryujinx scale:      2x
Output target:      1920x1080
Frame-rate target:  native SMO 60fps
```

This avoids the unstable full-1080p SMO patch and avoids rendering the default 900p image at 2x, which would be closer to 3200x1800 internally. Vulkan, shader cache, PPTC, Macro HLE, HostMappedUnsafe, and hypervisor support are the performance-oriented Ryujinx settings already appropriate for this ARM64 handheld environment.

Disabling filesystem integrity checks and missing service strictness reduces avoidable overhead/noise for a known-good local ROM setup. VSync remains enabled because SMO is a 60fps game and uncapped frame pacing can feel worse than a stable cap on handheld displays.

## Prevention

- Prefer title-specific resolution patches over blindly increasing Ryujinx global resolution scale.
- Avoid mod sections explicitly marked unstable unless testing in a disposable configuration.
- Keep `Config.json` backups before performance tuning so a bad setting can be rolled back quickly.
- Confirm mod loader messages in Ryujinx logs after installing a patch; a correct directory tree is as important as the patch content.
- Expect first-run shader compilation stutter even with the correct settings. Re-test after revisiting areas once the shader cache warms.

## Related Issues

- `docs/solutions/integration-issues/ryujinx-switch-save-conversion-rocknix-2026-04-28.md` — related ROCKNIX/Ryujinx setup work, but distinct from performance tuning.
- GameBanana `Upscaling Settings` mod for Super Mario Odyssey — source of the 960x540/2x and unstable 1920x1080 patch guidance.
- Ryujinx Vulkan and resolution-scaling guidance — supports using Vulkan, shader cache, and measured resolution scaling rather than over-rendering.
