vboxuser@lab-test:~$ cat vagrant_setup.sh
#!/usr/bin/env bash
#
# setup-vagrant-libvirt.sh
#
# Automates the installation of KVM/libvirt, Vagrant, and the
# vagrant-libvirt plugin on Ubuntu 22.04+ (Desktop or Server).
# Based on: https://gist.github.com/PaulNeumann/81f299a7980f0b74cec9c5cc0508172b
#
# It also creates a VM project folder (default: ~/vm) containing a
# ".vagrant_base" file. Paste your Vagrantfile content into that file,
# then run "vagrant up" inside the folder (a Vagrantfile symlink pointing
# to .vagrant_base is created automatically).
#
# Usage:
#   chmod +x setup-vagrant-libvirt.sh
#   ./setup-vagrant-libvirt.sh [vm-folder-path]
#
# Do NOT run as root. Run it as your normal user (it will call sudo).

set -euo pipefail

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
VM_DIR="${1:-$HOME/vm}"           # VM project folder (override with 1st arg)
BASE_FILE=".vagrant_base"          # File where you'll paste your Vagrantfile
ENABLE_PASSWORDLESS_SUDO="yes"     # Set to "no" to skip the sudoers change

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
info()  { echo -e "\e[1;34m[INFO]\e[0m  $*"; }
ok()    { echo -e "\e[1;32m[ OK ]\e[0m  $*"; }
warn()  { echo -e "\e[1;33m[WARN]\e[0m  $*"; }
fail()  { echo -e "\e[1;31m[FAIL]\e[0m  $*" >&2; exit 1; }

[[ $EUID -eq 0 ]] && fail "Do not run this script as root. Run it as your normal user."

# ---------------------------------------------------------------------------
# 1. Verify CPU supports hardware virtualization
# ---------------------------------------------------------------------------
info "Checking CPU hardware virtualization support..."
if [[ "$(grep -E -c '(vmx|svm)' /proc/cpuinfo)" -ge 1 ]]; then
    ok "CPU supports hardware virtualization."
else
    fail "CPU does not support hardware virtualization (vmx/svm not found). Enable VT-x/AMD-V in BIOS or use different hardware."
fi

# ---------------------------------------------------------------------------
# 2. Update the system
# ---------------------------------------------------------------------------
info "Updating the system (apt update && upgrade)..."
sudo apt-get -y update
ok "System is up to date."

# ---------------------------------------------------------------------------
# 3. (Optional) Enable password-less sudo
#    Needed so vagrant-libvirt can configure NFS without prompting.
# ---------------------------------------------------------------------------
if [[ "$ENABLE_PASSWORDLESS_SUDO" == "yes" ]]; then
    info "Enabling password-less sudo for $(id -un)..."
    sudo su -c "echo \"$(id -un) ALL=(ALL) NOPASSWD: ALL\" > /etc/sudoers.d/$(id -un)"
    sudo su -c "chmod 0440 /etc/sudoers.d/$(id -un)"
    ok "Password-less sudo enabled."
else
    warn "Skipping password-less sudo (you'll be prompted for your password on vagrant up/halt)."
fi

# ---------------------------------------------------------------------------
# 4. Install KVM / libvirt and start the service
# ---------------------------------------------------------------------------
info "Installing KVM and libvirt packages..."
sudo apt-get -y install qemu-kvm libvirt-daemon-system libvirt-clients bridge-utils
sudo systemctl enable --now libvirtd
ok "KVM/libvirt installed and libvirtd is running."

# Optionally install virt-manager on Desktop systems (GUI VM manager)
if dpkg -l ubuntu-desktop >/dev/null 2>&1 || [[ -n "${XDG_CURRENT_DESKTOP:-}" ]]; then
    info "Desktop environment detected - installing virt-manager (GUI)..."
    sudo apt-get -y install virt-manager || warn "virt-manager install failed (non-fatal)."
fi

# ---------------------------------------------------------------------------
# 5. Add user to virtualization groups
# ---------------------------------------------------------------------------
info "Adding $(id -un) to 'libvirt' and 'kvm' groups..."
sudo adduser "$(id -un)" libvirt
sudo adduser "$(id -un)" kvm
ok "Group membership configured (requires re-login to take effect)."

# ---------------------------------------------------------------------------
# 6. Install Vagrant from the official HashiCorp repository
# ---------------------------------------------------------------------------
info "Installing Vagrant from HashiCorp's apt repository..."
wget -O- https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor --yes -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" \
    | sudo tee /etc/apt/sources.list.d/hashicorp.list
sudo apt-get -y update && sudo apt-get -y install vagrant
ok "Vagrant installed: $(vagrant --version)"

# ---------------------------------------------------------------------------
# 7. Enable deb-src repositories (needed for build-dep)
#    Handles both pre-24.04 (sources.list) and 24.04+ (ubuntu.sources)
# ---------------------------------------------------------------------------
UBUNTU_VERSION="$(lsb_release -rs | cut -d. -f1)"
info "Enabling source code (deb-src) repositories for Ubuntu $(lsb_release -rs)..."
if [[ "$UBUNTU_VERSION" -ge 24 ]]; then
    sudo sed -i 's/^Types: deb$/Types: deb deb-src/' /etc/apt/sources.list.d/ubuntu.sources
else
    sudo cp /etc/apt/sources.list "/etc/apt/sources.list.$(date +"%F")"
    sudo sed -i -e '/^# deb-src.*universe$/s/# //g' /etc/apt/sources.list
fi
sudo apt-get -y update
ok "deb-src repositories enabled."

# ---------------------------------------------------------------------------
# 8. Install prerequisites for the vagrant-libvirt plugin
# ---------------------------------------------------------------------------
info "Installing NFS server..."
sudo apt-get -y install nfs-kernel-server
sudo systemctl enable --now nfs-server

info "Installing build dependencies..."
if ! sudo apt-get -y build-dep vagrant ruby-libvirt; then
    warn "'build-dep vagrant' failed - falling back to 'build-dep ruby-libvirt' only..."
    sudo apt-get -y build-dep ruby-libvirt
fi
sudo apt-get -y install ebtables dnsmasq-base
sudo apt-get -y install libxslt-dev libxml2-dev libvirt-dev zlib1g-dev ruby-dev
ok "Plugin prerequisites installed."

# ---------------------------------------------------------------------------
# 9. Install the vagrant-libvirt plugin
# ---------------------------------------------------------------------------
info "Installing the vagrant-libvirt plugin (this can take a few minutes)..."
vagrant plugin install vagrant-libvirt
ok "Plugin installed: $(vagrant plugin list | grep vagrant-libvirt || true)"

# ---------------------------------------------------------------------------
# 10. Create the VM project folder with the .vagrant_base file
# ---------------------------------------------------------------------------
info "Creating VM project folder at: $VM_DIR"
mkdir -p "$VM_DIR"

if [[ ! -f "$VM_DIR/$BASE_FILE" ]]; then
    cat > "$VM_DIR/$BASE_FILE" <<'EOF'
Vagrant.configure("2") do |config|
  config.vm.box = "generic/ubuntu2204"
  config.vm.hostname = "kvm-dev"

  # Attach to the pre-created NAT network by name
  config.vm.network "private_network",
    ip: "192.168.50.10",
    libvirt__network_name: "vagrant-nat"


  config.vm.provider :libvirt do |libvirt|
    libvirt.uri               = "qemu:///system"
    libvirt.default_prefix    = "vagrant"
    libvirt.cpus              = 2
    libvirt.memory            = 2048
    libvirt.cpu_mode          = "host-passthrough"
    libvirt.storage_pool_name = "default"
    libvirt.graphics_type     = "none"
    libvirt.disk_bus          = "virtio"
    libvirt.disk_driver :cache => "writeback"
    libvirt.driver            = "kvm"
  end


  config.vm.provision "shell", inline: <<-SHELL
    apt-get update
    apt-get install -y curl git vim
    echo "KVM-backed VM provisioned successfully"
  SHELL
end
EOF
    ok "Created $VM_DIR/$BASE_FILE (sample Vagrantfile inside - edit it!)."
else
    warn "$VM_DIR/$BASE_FILE already exists - leaving it untouched."
fi

# Vagrant looks for a file named "Vagrantfile", so symlink it to .vagrant_base.
# Anything you paste into .vagrant_base is automatically what vagrant up uses.
if [[ ! -e "$VM_DIR/Vagrantfile" ]]; then
    ln -s "$BASE_FILE" "$VM_DIR/Vagrantfile"
    ok "Symlinked $VM_DIR/Vagrantfile -> $BASE_FILE"
fi

# Make libvirt the default provider so plain "vagrant up" works
if ! grep -q "VAGRANT_DEFAULT_PROVIDER" "$HOME/.bashrc" 2>/dev/null; then
    echo 'export VAGRANT_DEFAULT_PROVIDER=libvirt' >> "$HOME/.bashrc"
    ok "Set VAGRANT_DEFAULT_PROVIDER=libvirt in ~/.bashrc"
fi

exec $SHELL -l
# ---------------------------------------------------------------------------
# Done
# ---------------------------------------------------------------------------
echo
echo "=============================================================="
ok "Installation complete!"
echo
echo "  IMPORTANT: log out and log back in (or reboot) so the"
echo "  libvirt/kvm group membership takes effect."
echo
echo "  Then verify with:   virsh list --all"
echo
echo "  Next steps:"
echo "    1. Paste your Vagrantfile content into: $VM_DIR/$BASE_FILE"
echo "    2. cd $VM_DIR"
echo "    3. vagrant up          (libvirt is the default provider)"
echo "=============================================================="