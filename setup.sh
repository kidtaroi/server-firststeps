#!/usr/bin/env bash
#
# setup.sh - turn a fresh Ubuntu Server install into a headless home server.
#
# Installs Docker CE, Cockpit, and the tools needed to run and reach the box
# unattended: DHCP that actually works, key-only SSH, a firewall, panic
# recovery, capped container logs, and optional Tailscale, cloudflared and
# opencode.
#
# Idempotent. Every step checks before it acts, so a second run is cheap.
#
# Usage:
#   sudo ./setup.sh                     # interactive, Docker + Cockpit
#   sudo ./setup.sh --yes               # no prompts, defaults
#   sudo ./setup.sh --yes --with-tailscale --with-cloudflared --with-opencode
#   sudo ./setup.sh --help
#
# Flags:
#   --yes                 non-interactive, accept defaults
#   --user NAME           account to add to the docker group and install opencode for
#   --with-tailscale      install Tailscale (login is still manual)
#   --with-cloudflared    install cloudflared (tunnel token is still manual)
#   --with-opencode       install opencode for --user
#   --no-cockpit          skip Cockpit entirely
#   --no-upgrade          skip the full apt upgrade, install only
#   --skip-network        leave netplan alone
#   --skip-ssh            leave sshd alone
#   --docker-root PATH    parent directory for stacks and appdata (default /docker)
#
# What it cannot do, because these need accounts or firmware:
#   - tailscale up                  (auth key or interactive login)
#   - cloudflared service install   (tunnel token)
#   - BIOS power-on after AC loss   (firmware setting)

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'
BOLD='\033[1m'

ASSUME_YES=0
DO_UPGRADE=1
DO_NETWORK=1
DO_SSH=1
DO_COCKPIT=1
DO_TAILSCALE=0
DO_CLOUDFLARED=0
DO_OPENCODE=0
TARGET_USER="${SUDO_USER:-}"
DOCKER_ROOT="/docker"

log_info()  { printf '%b[INFO]%b %s\n' "$GREEN" "$NC" "$1"; }
log_warn()  { printf '%b[WARN]%b %s\n' "$YELLOW" "$NC" "$1"; }
log_error() { printf '%b[ERROR]%b %s\n' "$RED" "$NC" "$1"; }
log_step()  { printf '\n%b==>%b %s\n' "$BOLD" "$NC" "$1"; }

usage() { sed -n '3,40p' "$0" | sed 's/^# \{0,1\}//'; exit 0; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --yes|-y) ASSUME_YES=1; shift ;;
    --user) TARGET_USER="$2"; shift 2 ;;
    --with-tailscale) DO_TAILSCALE=1; shift ;;
    --with-cloudflared) DO_CLOUDFLARED=1; shift ;;
    --with-opencode) DO_OPENCODE=1; shift ;;
    --no-cockpit) DO_COCKPIT=0; shift ;;
    --no-upgrade) DO_UPGRADE=0; shift ;;
    --skip-network) DO_NETWORK=0; shift ;;
    --skip-ssh) DO_SSH=0; shift ;;
    --docker-root) DOCKER_ROOT="$2"; shift 2 ;;
    -h|--help) usage ;;
    *) log_error "unknown option: $1"; exit 1 ;;
  esac
done

# ---------------------------------------------------------------------- checks

check_root() {
  if [[ $EUID -ne 0 ]]; then
    log_error "This script must be run as root"
    exit 1
  fi
}

check_ubuntu() {
  if [[ ! -f /etc/os-release ]]; then
    log_error "This script is designed for Ubuntu Server"
    exit 1
  fi
  # shellcheck disable=SC1091
  source /etc/os-release
  if [[ "${ID:-}" != "ubuntu" ]]; then
    log_error "This script is designed for Ubuntu Server, detected: ${ID:-unknown}"
    exit 1
  fi
  log_info "Detected Ubuntu $VERSION_ID (${VERSION_CODENAME:-unknown})"
}

ask() {
  local prompt="$1" default="$2" reply
  if [[ $ASSUME_YES -eq 1 ]]; then
    REPLY="$default"
    return
  fi
  read -p "$prompt" -n 1 -r || true
  echo
  if [[ -z "${REPLY:-}" ]]; then
    REPLY="$default"
  fi
}

confirm_installation() {
  echo
  log_step "This script will configure:"
  echo "  - Base tooling (git, jq, tmux, htop, rsync, ncdu, ethtool)"
  echo "  - netplan DHCP, so the wired interface gets an address without a cable during install"
  echo "  - sshd key-only authentication, root login disabled"
  echo "  - ufw: deny incoming, allow SSH, Cockpit from the LAN, and all of tailscale0"
  echo "  - kernel panic auto-reboot after 10 seconds"
  echo "  - unattended security updates without automatic reboots"
  echo "  - Docker CE with log rotation and live-restore"
  echo "  - $DOCKER_ROOT/stacks and $DOCKER_ROOT/appdata"
  if [[ $DO_COCKPIT -eq 1 ]]; then
    echo "  - Cockpit on port 9090 with Navigator and optional modules"
  fi
  if [[ $DO_TAILSCALE -eq 1 ]]; then
    echo "  - Tailscale (installed, not logged in)"
  fi
  if [[ $DO_CLOUDFLARED -eq 1 ]]; then
    echo "  - cloudflared (installed, no tunnel)"
  fi
  if [[ $DO_OPENCODE -eq 1 ]]; then
    echo "  - opencode for ${TARGET_USER:-<no user selected>}"
  fi
  echo
  if [[ $ASSUME_YES -eq 0 ]]; then
    read -p "Do you want to continue? [y/N]: " -n 1 -r || true
    echo
    if [[ ! ${REPLY:-} =~ ^[Yy]$ ]]; then
      log_info "Installation cancelled"
      exit 0
    fi
  fi
}

# ------------------------------------------------------------------- packages

update_system() {
  log_step "Updating package lists"
  apt-get update -qq
  if [[ $DO_UPGRADE -eq 1 ]]; then
    log_step "Upgrading installed packages"
    DEBIAN_FRONTEND=noninteractive apt-get upgrade -y -qq
  fi
}

install_base_tools() {
  log_step "Installing base tooling"
  DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
    curl ca-certificates gnupg lsb-release jq \
    git unzip rsync tmux htop ncdu tree vim-tiny \
    ethtool chrony unattended-upgrades ufw
  log_info "Base tooling installed"
}

apt_install_if_available() {
  local pkg="$1"
  if ! apt-cache show "$pkg" >/dev/null 2>&1; then
    log_warn "$pkg is not available on this release, skipping"
    return 0
  fi
  DEBIAN_FRONTEND=noninteractive apt-get install -y -qq "$pkg"
  log_info "$pkg installed"
}

# -------------------------------------------------------------------- network

detect_iface() {
  local iface
  iface=$(ip -o -4 route show to default 2>/dev/null | awk '{print $5; exit}')
  [[ -n "$iface" ]] || iface=$(ls /sys/class/net | grep -E '^(en|eth)' | head -1 || true)
  printf '%s' "$iface"
}

configure_network() {
  log_step "Network (netplan DHCP)"
  local iface mac
  iface=$(detect_iface)
  if [[ -z "$iface" ]]; then
    log_warn "no wired interface found, skipping"
    return 0
  fi
  if grep -qs 'dhcp4: *true' /etc/netplan/*.yaml 2>/dev/null; then
    log_info "$iface already configured for dhcp4"
    return 0
  fi

  # The Ubuntu installer writes only a MAC match and a set-name rule when it
  # ran without a cable. Without dhcp4 the interface comes up with a link and
  # never asks for a lease, which looks exactly like a dead network.
  mac=$(cat "/sys/class/net/$iface/address")
  cp -n /etc/netplan/00-installer-config.yaml /root/netplan.orig.yaml 2>/dev/null || true
  cat > /etc/netplan/00-installer-config.yaml <<YAML
network:
  version: 2
  ethernets:
    $iface:
      match:
        macaddress: $mac
      set-name: $iface
      dhcp4: true
      dhcp4-overrides:
        use-dns: true
        use-domains: true
YAML
  chmod 600 /etc/netplan/00-installer-config.yaml
  netplan apply
  log_info "$iface configured for DHCP (was missing dhcp4)"
}

# ------------------------------------------------------------------------ ssh

harden_ssh() {
  log_step "SSH (key-only)"
  mkdir -p /etc/ssh/sshd_config.d
  cat > /etc/ssh/sshd_config.d/00-hardening.conf <<'CONF'
PasswordAuthentication no
KbdInteractiveAuthentication no
PermitRootLogin no
PubkeyAuthentication yes
MaxAuthTries 3
LoginGraceTime 20
ClientAliveInterval 300
ClientAliveCountMax 2
CONF
  # cloud-init writes 50-cloud-init.conf, which sorts after 00- and would win if
  # it re-enabled passwords. Neutralise it at the source too.
  if [[ -f /etc/ssh/sshd_config.d/50-cloud-init.conf ]]; then
    sed -i 's/^PasswordAuthentication yes/PasswordAuthentication no/' \
      /etc/ssh/sshd_config.d/50-cloud-init.conf
  fi
  sshd -t
  systemctl restart ssh
  log_info "sshd now rejects passwords and root logins"
  if ! awk '/^ssh-(rsa|ed25519|dss|ecdsa)/ {found=1} END {exit !found}' \
      /root/.ssh/authorized_keys /home/*/.ssh/authorized_keys 2>/dev/null; then
    log_warn "no authorized_keys found for root or any user; keep a console session open"
  fi
}

# ------------------------------------------------------------------- firewall

lan_cidr() {
  local iface cidr
  iface=$(detect_iface)
  # Ask the routing table for the connected subnet. An address with host bits
  # set (192.168.8.118/24) is not a network and ufw rejects it.
  cidr=$(ip -o -4 route show dev "$iface" scope link 2>/dev/null | awk '{print $1; exit}')
  printf '%s' "$cidr"
}

configure_firewall() {
  log_step "Firewall"
  local cidr
  ufw default deny incoming >/dev/null
  ufw default allow outgoing >/dev/null
  ufw allow 22/tcp comment 'ssh' >/dev/null

  if [[ $DO_COCKPIT -eq 1 ]]; then
    cidr=$(lan_cidr)
    if [[ -n "$cidr" ]]; then
      ufw allow from "$cidr" to any port 9090 proto tcp comment 'cockpit lan' >/dev/null \
        || log_warn "could not add a Cockpit rule for $cidr"
      log_info "Cockpit allowed from $cidr only"
    else
      log_warn "could not detect LAN subnet; Cockpit left closed except on tailscale0"
    fi
  fi

  ufw allow in on tailscale0 comment 'tailscale' >/dev/null || true
  ufw --force enable >/dev/null
  ufw status | sed -n '1,8p'
}

# --------------------------------------------------------------- reliability

configure_sysctl() {
  log_step "Panic recovery"
  cat > /etc/sysctl.d/99-appliance.conf <<'CONF'
kernel.panic = 10
kernel.panic_on_oops = 1
CONF
  sysctl -q -p /etc/sysctl.d/99-appliance.conf
  log_info "kernel will reboot 10 seconds after a panic"
}

configure_updates() {
  log_step "Update policy"
  cat > /etc/apt/apt.conf.d/99-appliance <<'CONF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
Unattended-Upgrade::Automatic-Reboot "false";
Unattended-Upgrade::Remove-Unused-Kernel-Packages "true";
CONF
  systemctl enable --now apt-daily-upgrade.timer >/dev/null 2>&1 || true
  log_info "security updates applied daily, reboots left to you"
}

# --------------------------------------------------------------------- docker

install_docker() {
  log_step "Docker"
  if command -v docker >/dev/null; then
    log_info "Docker is already installed: $(docker --version)"
  else
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
    chmod a+r /etc/apt/keyrings/docker.asc

    local codename
    codename=$(. /etc/os-release && echo "$VERSION_CODENAME")
    # Docker sometimes has no repo for a brand new release. The previous LTS
    # repo installs and runs fine, so fall back rather than fail.
    if ! curl -fsSL -o /dev/null \
        "https://download.docker.com/linux/ubuntu/dists/${codename}/Release"; then
      log_warn "no Docker repo for ${codename}, falling back to noble"
      codename=noble
    fi

    cat > /etc/apt/sources.list.d/docker.list <<EOF
deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu ${codename} stable
EOF
    apt-get update -qq
    DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
      docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    log_info "Docker installed"
  fi

  # Cap container logs so a chatty container cannot fill the disk, and keep
  # containers running across a daemon restart.
  mkdir -p /etc/docker
  cat > /etc/docker/daemon.json <<'CONF'
{
  "log-driver": "json-file",
  "log-opts": { "max-size": "10m", "max-file": "3" },
  "live-restore": true
}
CONF
  systemctl enable --now docker >/dev/null
  systemctl restart docker

  if [[ -n "$TARGET_USER" ]] && id "$TARGET_USER" >/dev/null 2>&1; then
    usermod -aG docker "$TARGET_USER"
    log_info "added $TARGET_USER to the docker group (effective on next login)"
  fi
}

setup_layout() {
  log_step "Container layout"
  install -d -m 0755 "$DOCKER_ROOT/stacks" "$DOCKER_ROOT/appdata"
  if [[ -n "$TARGET_USER" ]] && id "$TARGET_USER" >/dev/null 2>&1; then
    chown -R "$TARGET_USER":"$TARGET_USER" "$DOCKER_ROOT"
  fi
  log_info "$DOCKER_ROOT ready for compose stacks"
}

# -------------------------------------------------------------------- cockpit

install_cockpit() {
  [[ $DO_COCKPIT -eq 1 ]] || return 0
  log_step "Cockpit"

  if systemctl is-active --quiet cockpit.socket; then
    log_info "Cockpit is already running"
  else
    DEBIAN_FRONTEND=noninteractive apt-get install -y -qq cockpit
    systemctl enable --now cockpit.socket
    log_info "Cockpit installed on port 9090"
  fi

  if [[ -d /usr/share/cockpit/navigator ]]; then
    log_info "Cockpit Navigator already installed"
  else
    apt_install_if_available cockpit-navigator
  fi

  apt_install_if_available cockpit-podman
  apt_install_if_available cockpit-machines

  if apt-cache show cockpit-docker >/dev/null 2>&1; then
    ask "Install cockpit-docker (container UI for the Docker daemon)? [Y/n]: " "y"
    if [[ ${REPLY:-y} =~ ^[Yy]$ ]]; then
      apt_install_if_available cockpit-docker
    fi
  fi

  ask "Install cockpit-389-ds (directory server)? [y/N]: " "n"
  if [[ ${REPLY:-n} =~ ^[Yy]$ ]]; then
    apt_install_if_available cockpit-389-ds
  fi
}

# ------------------------------------------------------------------ optional

install_tailscale() {
  [[ $DO_TAILSCALE -eq 1 ]] || return 0
  log_step "Tailscale"
  if command -v tailscale >/dev/null; then
    log_info "Tailscale already installed: $(tailscale version | sed -n '1p')"
  else
    curl -fsSL https://tailscale.com/install.sh | sh
  fi
  systemctl enable --now tailscaled >/dev/null 2>&1 || true
  log_warn "finish with: tailscale up --ssh --hostname=<name>"
}

install_cloudflared() {
  [[ $DO_CLOUDFLARED -eq 1 ]] || return 0
  log_step "cloudflared"
  if command -v cloudflared >/dev/null; then
    log_info "cloudflared already installed: $(cloudflared --version)"
    return 0
  fi
  local arch
  arch=$(dpkg --print-architecture)
  curl -fsSL -o /tmp/cloudflared.deb \
    "https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-${arch}.deb"
  dpkg -i /tmp/cloudflared.deb
  rm -f /tmp/cloudflared.deb
  log_info "cloudflared installed"
  log_warn "activate with: cloudflared service install <tunnel-token>"
}

install_opencode() {
  [[ $DO_OPENCODE -eq 1 ]] || return 0
  if [[ -z "$TARGET_USER" ]] || ! id "$TARGET_USER" >/dev/null 2>&1; then
    log_warn "no valid --user given, skipping opencode"
    return 0
  fi
  log_step "opencode for $TARGET_USER"
  if [[ -x "/home/$TARGET_USER/.opencode/bin/opencode" ]]; then
    log_info "already installed: $(sudo -u "$TARGET_USER" /home/$TARGET_USER/.opencode/bin/opencode --version 2>/dev/null || echo present)"
  else
    sudo -u "$TARGET_USER" bash -lc 'curl -fsSL https://opencode.ai/install | bash'
  fi
  # The installer only edits .bashrc, which non-interactive shells never read.
  if [[ -x "/home/$TARGET_USER/.opencode/bin/opencode" ]]; then
    ln -sf "/home/$TARGET_USER/.opencode/bin/opencode" /usr/local/bin/opencode
    log_info "linked /usr/local/bin/opencode"
  fi
}

# -------------------------------------------------------------------- summary

show_summary() {
  log_step "Installation complete"
  echo
  printf '  %-20s %s\n' "Docker:" "$(docker --version 2>/dev/null || echo 'not installed')"
  printf '  %-20s %s\n' "Compose:" "$(docker compose version 2>/dev/null || echo 'not installed')"
  if [[ $DO_COCKPIT -eq 1 ]]; then
    printf '  %-20s %s\n' "Cockpit:" "https://$(hostname -I | awk '{print $1}'):9090"
  fi
  printf '  %-20s %s\n' "SSH:" "$(sshd -T 2>/dev/null | awk '/^passwordauthentication/ {print $2}' | sed 's/^no$/key-only/')"
  printf '  %-20s %s\n' "Stacks:" "$DOCKER_ROOT/stacks"
  if command -v tailscale >/dev/null; then
    printf '  %-20s %s\n' "Tailscale:" "$(tailscale ip -4 2>/dev/null || echo 'not logged in')"
  fi
  echo
  log_info "Still manual, and only you can do them:"
  echo "  1. Add your SSH public key before closing the console session"
  echo "  2. tailscale up --ssh --hostname=<name>"
  echo "  3. cloudflared service install <token>"
  echo "  4. BIOS: power on after AC loss"
  echo "  5. Reboot with nothing attached and confirm it comes back"
}

main() {
  printf '%b=== Ubuntu Server home server setup ===%b\n' "$BOLD" "$NC"
  check_root
  check_ubuntu
  confirm_installation
  update_system
  install_base_tools
  if [[ $DO_NETWORK -eq 1 ]]; then configure_network; fi
  if [[ $DO_SSH -eq 1 ]]; then harden_ssh; fi
  configure_sysctl  configure_updates
  install_docker
  setup_layout
  install_cockpit
  install_tailscale
  install_cloudflared
  install_opencode
  configure_firewall
  show_summary
}

main "$@"
