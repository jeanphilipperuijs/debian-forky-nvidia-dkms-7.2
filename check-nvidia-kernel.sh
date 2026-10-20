#!/bin/bash
set -u

KERNEL="$(uname -r)"
NVIDIA_VERSION="550.163.01"
DKMS_NAME="nvidia-current"

echo "=== Kernel ==="
echo "Running kernel: $KERNEL"
echo

echo "=== DKMS ==="
dkms status
echo

echo "=== NVIDIA modules ==="
if modinfo nvidia >/dev/null 2>&1; then
    modinfo nvidia | grep -E '^(filename|version|vermagic):'
else
    echo "nvidia module not currently available to modinfo"
fi
echo

echo "=== Loaded NVIDIA modules ==="
lsmod | grep nvidia || echo "No NVIDIA modules currently loaded"
echo

echo "=== Kernel module directory ==="
if [ -d "/lib/modules/$KERNEL/updates/dkms" ]; then
    find "/lib/modules/$KERNEL/updates/dkms" \
        -maxdepth 1 \
        -type f \
        -name 'nvidia*' \
        -printf '%f\n' | sort
else
    echo "No DKMS module directory for $KERNEL"
fi
echo

echo "=== Headers ==="
if [ -e "/lib/modules/$KERNEL/build" ]; then
    readlink -f "/lib/modules/$KERNEL/build"
else
    echo "WARNING: kernel headers/build directory missing"
fi
echo

echo "=== NVIDIA status ==="
if command -v nvidia-smi >/dev/null 2>&1; then
    nvidia-smi
else
    echo "nvidia-smi not available"
fi

