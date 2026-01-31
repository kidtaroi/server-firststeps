#!/usr/bin/env bash

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'
BOLD='\033[1m'

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_step() {
    echo -e "${BOLD}==>${NC} $1"
}

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
    
    source /etc/os-release
    if [[ "$ID" != "ubuntu" ]]; then
        log_error "This script is designed for Ubuntu Server, detected: $ID"
        exit 1
    fi
    
    log_info "Detected Ubuntu $VERSION_ID"
}

confirm_installation() {
    echo
    log_step "This script will install:"
    echo "  - Docker CE (latest)"
    echo "  - Docker Compose"
    echo "  - Cockpit (web-based server management)"
    echo "  - Cockpit Navigator (file manager)"
    echo "  - Cockpit Docker module"
    echo "  - Cockpit Podman module (optional)"
    echo "  - Cockpit 389-ds module (optional)"
    echo "  - Cockpit Machines module (optional)"
    echo
    read -p "Do you want to continue? [y/N]: " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "Installation cancelled"
        exit 0
    fi
}

update_system() {
    log_step "Updating system packages..."
    apt-get update
    apt-get upgrade -y
    log_info "System updated successfully"
}

install_docker() {
    log_step "Installing Docker..."
    
    if command -v docker &> /dev/null; then
        log_info "Docker is already installed"
        return
    fi
    
    apt-get install -y \
        ca-certificates \
        curl \
        gnupg \
        lsb-release
    
    mkdir -p /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    
    echo \
      "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
      $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
    
    apt-get update
    apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    
    log_info "Docker installed successfully"
}

install_cockpit() {
    log_step "Installing Cockpit..."
    
    if systemctl is-active --quiet cockpit.socket; then
        log_info "Cockpit is already installed and running"
    else
        apt-get install -y cockpit
        systemctl enable --now cockpit.socket
        log_info "Cockpit installed and enabled"
    fi
}

install_cockpit_navigator() {
    log_step "Installing Cockpit Navigator..."
    
    if [[ -d /usr/share/cockpit/cockpit-navigator ]]; then
        log_info "Cockpit Navigator is already installed"
    else
        apt-get install -y cockpit-navigator
        log_info "Cockpit Navigator installed"
    fi
}

install_cockpit_modules() {
    log_step "Installing Cockpit modules..."
    
    echo
    read -p "Install Cockpit Docker module? [Y/n]: " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Nn]$ ]]; then
        apt-get install -y cockpit-docker
        log_info "Cockpit Docker module installed"
    fi
    
    echo
    read -p "Install Cockpit Podman module? [y/N]: " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        apt-get install -y cockpit-podman
        log_info "Cockpit Podman module installed"
    fi
    
    echo
    read -p "Install Cockpit 389-ds module? [y/N]: " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        apt-get install -y cockpit-389-ds
        log_info "Cockpit 389-ds module installed"
    fi
    
    echo
    read -p "Install Cockpit Machines module? [y/N]: " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        apt-get install -y cockpit-machines
        log_info "Cockpit Machines module installed"
    fi
}

configure_firewall() {
    log_step "Configuring firewall..."
    
    if command -v ufw &> /dev/null && ufw status | grep -q "active"; then
        ufw allow 9090/tcp
        log_info "Firewall rule added for Cockpit (port 9090)"
    fi
}

show_summary() {
    log_step "Installation Complete!"
    echo
    log_info "Summary:"
    echo "  - Docker: $(docker --version 2>/dev/null || echo 'Not installed')"
    echo "  - Docker Compose: $(docker compose version 2>/dev/null || echo 'Not installed')"
    echo "  - Cockpit: $(systemctl is-active cockpit.socket 2>/dev/null && echo 'Running on port 9090' || echo 'Not running')"
    echo
    log_info "Access Cockpit at: https://$(hostname -I | awk '{print $1}'):9090"
    log_info "Or use: https://$(hostname -f 2>/dev/null || hostname):9090"
    echo
    log_info "Next steps:"
    echo "  1. Access Cockpit web interface"
    echo "  2. Manage Docker containers via Cockpit Docker module"
    echo "  3. Explore server files with Cockpit Navigator"
}

main() {
    echo -e "${BOLD}=== Ubuntu Server Docker & Cockpit Setup ===${NC}"
    echo
    
    check_root
    check_ubuntu
    confirm_installation
    update_system
    install_docker
    install_cockpit
    install_cockpit_navigator
    install_cockpit_modules
    configure_firewall
    show_summary
}

main "$@"