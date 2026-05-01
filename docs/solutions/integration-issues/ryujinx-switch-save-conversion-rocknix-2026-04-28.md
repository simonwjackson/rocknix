---
title: Convert Switch save exports into Ryujinx BIS save layout on ROCKNIX
date: 2026-04-28
category: integration-issues
module: ROCKNIX Ryujinx save migration
problem_type: integration_issue
component: tooling
symptoms:
  - Imported Switch saves copied into Ryujinx but Super Mario Odyssey still started as a new game.
  - Ryujinx generated a save container under /storage/.config/Ryujinx/bis/user/save/0000000000000001.
  - Source saves used an account/title layout under user/save/0000000000000000/<profile-id>/<title-id>/.
root_cause: incomplete_setup
resolution_type: tooling_addition
severity: medium
tags: [rocknix, ryujinx, switch-saves, save-conversion, bis-layout, super-mario-odyssey]
---

# Convert Switch save exports into Ryujinx BIS save layout on ROCKNIX

## Problem

Switch saves exported from another system were present on the source host, but simply copying them to the Ryujinx data directory did not make Ryujinx load them. Super Mario Odyssey launched successfully but showed a new game instead of the existing progress.

## Symptoms

- Source save tree was available at:
  ```text
  zao:/srv/lakes/towada/gaming/profiles/simonwjackson/progress/saves/nintendo-switch/
  ```
- Exported account saves used this shape:
  ```text
  user/save/0000000000000000/<profile-id>/<title-id>/<save-files>
  ```
- Ryujinx expected BIS save containers under:
  ```text
  /storage/.config/Ryujinx/bis/user/save/<save-data-id>/
  ```
- After an initial conversion, Mario still started as new because files were placed at the save-container root instead of the committed save directory.

## What Didn't Work

- Copying the whole exported `user/save` tree directly into Ryujinx did not work because Ryujinx does not load the account/title export layout directly.
- Creating Ryujinx save containers and patching `ExtraData0`/`ExtraData1` was still insufficient when game files were placed beside `ExtraData0` and `ExtraData1`.
- The key missed detail was Ryujinx's committed/working directory structure: it loads committed save data from the `0/` subdirectory when that directory exists.

## Solution

Stage the source saves onto the device, choose the source profile to import, convert account/title directories into Ryujinx save containers, patch the metadata to the local Ryujinx profile, then place game save files inside each container's `0/` directory.

### 1. Stage the exported saves

```sh
ssh zao 'tar -C /srv/lakes/towada/gaming/profiles/simonwjackson/progress/saves -cf - nintendo-switch/user/save nintendo-switch/user/saveMeta' \
  | ssh root@192.168.1.104 'set -e; rm -rf /storage/tmp/switch-saves-import; mkdir -p /storage/tmp/switch-saves-import; tar -C /storage/tmp/switch-saves-import -xf -'
```

### 2. Identify the profile to import

In this case the newer source profile was:

```text
/storage/tmp/switch-saves-import/nintendo-switch/user/save/0000000000000000/B520592F96495D53CD15BD9E48BE421D
```

The Ryujinx local user profile was read from:

```text
/storage/.config/Ryujinx/system/Profiles.json
```

For the local `RyuPlayer` profile:

```text
00000000000000010000000000000000
```

### 3. Convert title directories to Ryujinx containers

Each source title directory maps to a Ryujinx save container:

```text
<title-id> -> /storage/.config/Ryujinx/bis/user/save/<save-data-id>/
```

For Super Mario Odyssey:

```text
0100000000010000 -> /storage/.config/Ryujinx/bis/user/save/0000000000000001
```

The conversion must preserve or create:

```text
ExtraData0
ExtraData1
.lock
0/
1/
```

Patch `ExtraData0` and `ExtraData1` so bytes `8..23` contain the local Ryujinx profile id as two little-endian u64 values. Also ensure the title id is present at the known title-id offsets (`0..7` and `64..71`) where applicable.

### 4. Put game save files in the committed directory

The fix that made Mario load the imported save was moving game files into `0/`:

```text
/storage/.config/Ryujinx/bis/user/save/0000000000000001/
  ExtraData0
  ExtraData1
  .lock
  0/
    Common.bin
    File1.bin
  1/
```

A generic placement repair script moved all non-metadata files from the container root into `0/`:

```python
from pathlib import Path
import json, shutil, time, os

log = json.loads(Path('/storage/switch-save-import.log').read_text())
root = Path('/storage/.config/Ryujinx/bis/user/save')
backup = Path(f"/storage/backups/ryujinx-saves-before-placement-fix-{time.strftime('%Y%m%d-%H%M%S')}")

os.system('killall Ryujinx >/dev/null 2>&1 || true')
backup.mkdir(parents=True, exist_ok=True)

for item in log['mapping']:
    d = root / item['container']
    if d.exists():
        shutil.copytree(d, backup / item['container'], dirs_exist_ok=True)

for item in log['mapping']:
    d = root / item['container']
    if not d.exists():
        continue

    committed = d / '0'
    working = d / '1'
    committed.mkdir(exist_ok=True)
    working.mkdir(exist_ok=True)

    for child in list(d.iterdir()):
        if child.name in {'ExtraData0', 'ExtraData1', '.lock', '0', '1'}:
            continue

        dest = committed / child.name
        if dest.exists():
            if dest.is_dir():
                shutil.rmtree(dest)
            else:
                dest.unlink()

        shutil.move(str(child), str(dest))
```

### 5. Keep backups and logs

Useful artifacts from the successful import:

```text
/storage/backups/ryujinx-saves-before-import-20260428-220628
/storage/backups/ryujinx-saves-before-placement-fix-20260428-220958
/storage/switch-save-import.log
/storage/switch-save-import-repair.log
/storage/switch-save-placement-fix.log
```

## Why This Works

Ryujinx save data is not just a folder of game files. It is a BIS save container with metadata and committed/working directories.

The exported save path grouped data by source account and title id:

```text
user/save/0000000000000000/<source-account-id>/<title-id>/
```

Ryujinx loads a save by resolving a save-data id from `ExtraData0`/`ExtraData1`, matching the local user id, and then mounting the committed save directory. When `0/` exists, Ryujinx treats it as the committed data to load. Placing `Common.bin` and `File1.bin` at the container root leaves the actual committed save empty, so the game behaves as if no save exists.

The working layout therefore needs both correct metadata and correct placement:

```text
<container>/ExtraData0          # title id + local Ryujinx user metadata
<container>/ExtraData1          # alternate metadata copy
<container>/0/<actual files>    # committed save loaded by Ryujinx
<container>/1/                  # working save directory
```

## Prevention

- Treat Switch save imports as a conversion, not a copy.
- Before declaring an import successful, inspect the target container and verify game files are under `0/`, not beside `ExtraData0`.
- Preserve a backup before each conversion or repair step.
- For account save exports, patch source profile ids in `ExtraData0`/`ExtraData1` to the local Ryujinx profile id from `Profiles.json`.
- Use a known title id to validate the mapping. For Super Mario Odyssey:
  ```text
  0100000000010000 -> /storage/.config/Ryujinx/bis/user/save/0000000000000001
  ```

## Related Issues

- No existing `docs/solutions/` entries were present in this repository at the time this was documented.
