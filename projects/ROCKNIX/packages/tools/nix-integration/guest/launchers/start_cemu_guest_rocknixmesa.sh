#!/run/current-system/sw/bin/bash
# Diagnostic-only launcher: run guest Cemu with the ROCKNIX host Mesa ICD
# plus a narrow host dependency shim, but keep the Nix Vulkan loader.
#
# This deliberately does NOT preload /host/lib/libvulkan.so.1: mixing the host
# Vulkan loader with Cemu's Nix Vulkan loader has crashed Cemu. Use this only to
# characterize the runtime gap; the product target remains a coherent Nix-built
# graphics stack.
set -eu

export VK_ICD_FILENAMES="${ROCKNIX_MESA_ICD:-/storage/.guest/host-freedreno-icd.json}"
export VK_DRIVER_FILES="$VK_ICD_FILENAMES"
export LD_LIBRARY_PATH="${ROCKNIX_MESA_LIBS:-/storage/.guest/host-mesa-libs}${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
export NODEVICE_SELECT=1
unset VK_LAYER_PATH VK_INSTANCE_LAYERS LD_PRELOAD || true

exec /storage/.guest/start_cemu_guest.sh "$@"
