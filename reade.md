Absolutely. Here is a self-contained runbook you can keep as the future reference for this exact Debian Forky/NVIDIA/DKMS issue.

# Debian Forky — NVIDIA 550 DKMS vs Linux 7.2 Compatibility Fix

## Situation

System:

- Debian Forky (`deb14`)
- Kernel:
  - **Working fallback:** `7.1.13+deb14-amd64`
  - **Target/new kernel:** `7.2.6+deb14-amd64`
- NVIDIA driver: `550.163.01-5.1`
- DKMS module: `nvidia-current/550.163.01`
- NVIDIA GPU driver packages must remain installed.
- The old `7.1.13` kernel must remain installed as a fallback.

The problem was:

> NVIDIA 550.163.01-5.1 DKMS builds successfully on Linux 7.1.13 but fails against Linux 7.2.6 because Linux 7.2 removed/renamed APIs used by the NVIDIA 550 source.

The eventual solution was to apply the relevant Debian fixes from the unreleased `550.163.01-5.2` NMU/debdiff manually to the DKMS source, then rebuild.

---

# 1. Verify the running kernel

```bash
uname -r
```

Expected after booting the new kernel:

```text
7.2.6+deb14-amd64
```

The old fallback should remain:

```text
7.1.13+deb14-amd64
```

Do **not** remove it.

---

# 2. Verify kernel headers

For the new kernel:

```bash
dpkg -l | grep 'linux-headers-7.2.6'
```

Expected:

```text
linux-headers-7.2.6+deb14-amd64
linux-headers-7.2.6+deb14-common
```

Verify the DKMS links:

```bash
ls -l /lib/modules/7.2.6+deb14-amd64/build
ls -l /lib/modules/7.2.6+deb14-amd64/source
```

Expected:

```text
build  -> ../../../src/linux-headers-7.2.6+deb14-amd64
source -> ../../../src/linux-headers-7.2.6+deb14-common
```

---

# 3. Original DKMS failure

The original build failed with:

```text
nvidia/os-interface.c:753:5:
error: implicit declaration of function ‘strncpy’
```

The problematic code was:

```c
strncpy(buf, current->comm, len - 1);
buf[len - 1] = '\0';
```

Linux 7.2 removed `strncpy()` from the relevant kernel API.

The appropriate replacement was:

```c
strscpy(buf, current->comm, len);
```

However, this was **not the only Linux 7.2 incompatibility**.

The NVIDIA DRM code also expected the old:

```c
struct drm_atomic_state
```

API while Linux 7.2 uses:

```c
struct drm_atomic_commit
```

There were consequently multiple DRM callback/type/helper errors.

---

# 4. NVIDIA package state

Relevant packages:

```text
nvidia-kernel-dkms 550.163.01-5.1
nvidia-driver      550.163.01-5.1
```

DKMS module:

```text
nvidia-current/550.163.01
```

The package's `nvidia-current` name is the DKMS module name; the `nvidia-current` package itself was not installed.

Check:

```bash
dpkg -l | grep nvidia
dkms status
```

---

# 5. Recovering the Debian DKMS package

APT initially had a broken package-file state:

```text
E: Internal Error: No file name for nvidia-kernel-dkms:amd64
```

After:

```bash
sudo apt update
```

the package was downloaded directly:

```bash
apt-get download nvidia-kernel-dkms=550.163.01-5.1
```

This produced:

```text
nvidia-kernel-dkms_550.163.01-5.1_amd64.deb
```

Then it was reinstalled with:

```bash
sudo dpkg -i nvidia-kernel-dkms_550.163.01-5.1_amd64.deb
```

This refreshed the package's DKMS source tree.

---

# 6. Important source directory

The DKMS source was:

```text
/usr/src/nvidia-current-550.163.01
```

Enter it with:

```bash
cd /usr/src/nvidia-current-550.163.01
```

---

# 7. Debian Linux 7.2 compatibility patches

Two relevant Debian patches from the subsequent `550.163.01-5.2` NMU were identified:

```text
0087-strncpy-to-strscpy.patch
0088-drm-atomic.patch
```

These fixes correspond to two separate Linux 7.2 API changes.

## 0087 — strncpy → strscpy

Affected NVIDIA source files:

```text
nvidia/os-interface.c
nvidia/linux_nvswitch.c
nvidia-uvm/uvm_pmm_gpu.c
nvidia-modeset/nvidia-modeset-linux.c
```

The live source was brought into the Linux 7.2-compatible state.

Verify no live `strncpy()` remains:

```bash
cd /usr/src/nvidia-current-550.163.01

grep -R -nE '\bstrncpy\b' \
    nvidia nvidia-uvm nvidia-modeset
```

At the time of the fix, only `.orig` backup files contained the old calls.

That is fine.

---

# 8. Special note about nvidia-modeset

The modeset source had already been manually changed to:

```c
char* nvkms_strncpy(char *dest, const char *src, size_t n)
{
    strscpy(dest, src, n); return dest;
}
```

Therefore the corresponding 0087 patch hunk did not need to be applied again.

Do **not** blindly force that patch with:

```bash
patch -f
```

The source was already in the desired state.

---

# 9. 0088 DRM atomic patch

A clean version of the Debian DRM compatibility patch was created as:

```text
/tmp/0088-drm-atomic-clean.patch
```

It contains five source-file changes:

```text
conftest.sh
nvidia-drm/nvidia-drm-conftest.h
nvidia-drm/nvidia-drm-crtc.c
nvidia-drm/nvidia-drm-modeset.c
nvidia-drm/nvidia-drm-sources.mk
```

Verify:

```bash
grep -c '^diff --git' /tmp/0088-drm-atomic-clean.patch
```

Expected:

```text
5
```

---

# 10. Always dry-run a kernel-driver patch

Before applying:

```bash
cd /usr/src/nvidia-current-550.163.01

sudo patch --dry-run -p1 < /tmp/0088-drm-atomic-clean.patch
```

Successful output looked like:

```text
checking file conftest.sh
checking file nvidia-drm/nvidia-drm-conftest.h
checking file nvidia-drm/nvidia-drm-crtc.c
checking file nvidia-drm/nvidia-drm-modeset.c
checking file nvidia-drm/nvidia-drm-sources.mk
```

Only after a clean dry-run:

```bash
sudo patch -p1 < /tmp/0088-drm-atomic-clean.patch
```

---

# 11. The DRM compatibility mechanism

The patch adds a conftest for:

```c
struct drm_atomic_commit
```

and defines compatibility aliases such as:

```c
#define drm_atomic_state                 drm_atomic_commit
#define drm_atomic_state_alloc           drm_atomic_commit_alloc
#define drm_atomic_state_clear           drm_atomic_commit_clear
#define drm_atomic_state_default_clear   drm_atomic_commit_default_clear
#define drm_atomic_state_default_release drm_atomic_commit_default_release
#define drm_atomic_state_free            drm_atomic_commit_put
#define drm_atomic_state_get             drm_atomic_commit_get
#define drm_atomic_state_init            drm_atomic_commit_init
#define drm_atomic_state_put             drm_atomic_commit_put
```

It also adjusts the NVIDIA DRM atomic callbacks and adds the new conftest to:

```text
nvidia-drm/nvidia-drm-sources.mk
```

This is why the previously observed errors involving:

```text
struct drm_atomic_commit *
struct drm_atomic_state *
drm_atomic_state_alloc
drm_atomic_state_clear
drm_atomic_state_free
drm_atomic_state_get
drm_atomic_get_crtc_state
```

could be resolved without changing the kernel itself.

---

# 12. Final DKMS rebuild

The critical command was:

```bash
sudo dkms install nvidia-current/550.163.01 -k 7.2.6+deb14-amd64
```

Successful output:

```text
Building module(s)............. done.
```

followed by signing of:

```text
nvidia.ko
nvidia-modeset.ko
nvidia-drm.ko
nvidia-uvm.ko
nvidia-peermem.ko
```

and installation under:

```text
/lib/modules/7.2.6+deb14-amd64/updates/dkms/
```

The successful result means the Linux 7.2 compatibility problem is now solved for this DKMS build.

---

# 13. Current known-good state

At this point:

```text
Kernel:             7.2.6+deb14-amd64
NVIDIA:             550.163.01
DKMS:               successfully built
Kernel fallback:    7.1.13+deb14-amd64
```

The newly built modules are:

```text
nvidia-current.ko.xz
nvidia-current-modeset.ko.xz
nvidia-current-drm.ko.xz
nvidia-current-uvm.ko.xz
nvidia-current-peermem.ko.xz
```

under:

```text
/lib/modules/7.2.6+deb14-amd64/updates/dkms/
```

---

# 14. Finish the kernel integration

Run:

```bash
sudo depmod -a 7.2.6+deb14-amd64
sudo update-initramfs -u -k 7.2.6+deb14-amd64
sudo update-grub
```

Then verify DKMS:

```bash
dkms status
```

You want to see NVIDIA installed for both kernels, approximately:

```text
nvidia-current/550.163.01, 7.1.13+deb14-amd64, x86_64: installed
nvidia-current/550.163.01, 7.2.6+deb14-amd64, x86_64: installed
```

Also:

```bash
modinfo nvidia | head
```

and, once the module is loaded:

```bash
lsmod | grep nvidia
```

Optionally:

```bash
nvidia-smi
```

---

# 15. Reboot

Once the above checks are clean:

```bash
sudo reboot
```

After reboot:

```bash
uname -r
```

should say:

```text
7.2.6+deb14-amd64
```

Then:

```bash
nvidia-smi
```

and:

```bash
lsmod | grep nvidia
```

---

# 16. If the new kernel ever fails

At GRUB, select:

```text
7.1.13+deb14-amd64
```

That kernel is the known-good fallback.

Once booted into it:

```bash
uname -r
```

should show:

```text
7.1.13+deb14-amd64
```

Then investigate without removing anything.

Useful diagnostics:

```bash
dkms status
```

```bash
journalctl -k -b | grep -iE 'nvidia|nouveau|drm'
```

```bash
dmesg | grep -iE 'nvidia|nouveau|drm'
```

For a DKMS compilation failure:

```bash
grep -E 'error:|warning:' \
    /var/lib/dkms/nvidia-current/550.163.01/build/make.log \
    | tail -100
```

Full tail:

```bash
tail -200 /var/lib/dkms/nvidia-current/550.163.01/build/make.log
```

---

# 17. Things NOT to do

### Do not remove the old kernel

Keep:

```text
7.1.13+deb14-amd64
```

until the new kernel has been thoroughly tested.

### Do not purge NVIDIA

Do not run things like:

```bash
sudo apt purge 'nvidia*'
```

### Do not run autoremove casually

Avoid:

```bash
sudo apt autoremove
```

while troubleshooting this.

### Do not force patches

Avoid:

```bash
patch -f
```

If a patch hunk fails, inspect the actual source first.

### Do not blindly reinstall the DKMS package

The normal:

```bash
sudo apt-get --reinstall install nvidia-kernel-dkms
```

previously encountered:

```text
Internal Error: No file name for nvidia-kernel-dkms:amd64
```

The direct `.deb` download/reinstall was the workaround.

---

# 18. Useful automated verification script

Save as:

```text
/usr/local/sbin/check-nvidia-kernel.sh
```

```bash
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
```

Make executable:

```bash
sudo chmod +x /usr/local/sbin/check-nvidia-kernel.sh
```

Run:

```bash
sudo /usr/local/sbin/check-nvidia-kernel.sh
```

---

# 19. Simple Bash repair procedure for future kernels

For a future kernel `KERNEL`, the basic workflow is:

```bash
KERNEL="7.2.6+deb14-amd64"

# Verify headers
ls -l "/lib/modules/$KERNEL/build"

# Check DKMS
dkms status

# Build/install NVIDIA for that kernel
sudo dkms install nvidia-current/550.163.01 -k "$KERNEL"

# Integrate modules
sudo depmod -a "$KERNEL"

# Update initramfs
sudo update-initramfs -u -k "$KERNEL"

# Regenerate GRUB
sudo update-grub
```

If DKMS compilation fails:

```bash
tail -200 \
  /var/lib/dkms/nvidia-current/550.163.01/build/make.log
```

Then inspect the **first actual compiler error**, rather than chasing the cascade of errors afterward.

---

# 20. Ansible-oriented checks

A future Ansible role can enforce the important invariants without touching the working fallback kernel:

```yaml
- name: Get running kernel
  ansible.builtin.command: uname -r
  register: running_kernel
  changed_when: false

- name: Check NVIDIA DKMS status
  ansible.builtin.command: dkms status
  register: dkms_status
  changed_when: false

- name: Verify NVIDIA DKMS module for running kernel
  ansible.builtin.command:
    cmd: >-
      dkms status
      -m nvidia-current
      -v 550.163.01
      -k {{ running_kernel.stdout }}
  register: nvidia_dkms
  changed_when: false
  failed_when: false

- name: Show DKMS state
  ansible.builtin.debug:
    msg: "{{ nvidia_dkms.stdout }}"
```

For a new kernel:

```yaml
- name: Install NVIDIA DKMS module for kernel
  ansible.builtin.command:
    cmd: >-
      dkms install
      nvidia-current/550.163.01
      -k {{ target_kernel }}
  register: dkms_install
  changed_when: >
    'Building module(s)' in dkms_install.stdout or
    'Installing' in dkms_install.stdout

- name: Run depmod
  ansible.builtin.command:
    cmd: depmod -a {{ target_kernel }}

- name: Update initramfs
  ansible.builtin.command:
    cmd: update-initramfs -u -k {{ target_kernel }}

- name: Update GRUB
  ansible.builtin.command:
    cmd: update-grub
```

For production automation, I'd make the patching step explicit and versioned rather than relying on ad-hoc edits under `/usr/src`.

---

# 21. Better long-term automation: keep the patches

The key lesson is that these manual changes should eventually become a reproducible DKMS patch mechanism.

Maintain something like:

```text
files/
├── 0087-strncpy-to-strscpy.patch
└── 0088-drm-atomic.patch
```

and have automation:

1. Install the exact NVIDIA DKMS source package.
2. Verify the NVIDIA source version.
3. Verify the kernel version.
4. Apply the compatibility patches.
5. Build DKMS.
6. Verify the resulting modules.
7. Run `depmod`.
8. Regenerate initramfs.
9. Regenerate GRUB.

That way, if the NVIDIA package is reinstalled and `/usr/src/nvidia-current-550.163.01` is regenerated, the fixes can be reapplied deterministically.

**Important:** the manual modifications in `/usr/src` are not persistent package changes. A future reinstall/update of `nvidia-kernel-dkms` can overwrite them.

---

# 22. Current checkpoint

The most important milestone has now been reached:

```text
Linux 7.2.6+deb14-amd64
        │
        ▼
NVIDIA 550.163.01 DKMS
        │
        ├── 0087: strncpy → strscpy
        │
        └── 0088: Linux 7.2 DRM atomic compatibility
        │
        ▼
DKMS BUILD: SUCCESS
        │
        ▼
Signed NVIDIA kernel modules installed
```

And the safety net remains:

```text
7.1.13+deb14-amd64
        │
        └── known-good NVIDIA DKMS build
```

**Do not delete that fallback yet.**

