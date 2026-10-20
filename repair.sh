KERNEL="7.2.11+deb14-amd64"

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

