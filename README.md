# Server First Steps

A comprehensive, interactive setup script for Ubuntu Server that installs Docker, Cockpit web interface, and essential management tools in one command.

## 🚀 Features

- **Docker CE** - Latest version with Docker Compose
- **Cockpit** - Web-based server management interface
- **Cockpit Navigator** - File manager for Cockpit
- **Optional Cockpit Modules**:
  - Docker module (container management)
  - Podman module (alternative container runtime)
  - 389-ds module (directory server management)
  - Machines module (virtual machine management)
- **Automatic firewall configuration** (if using UFW)
- **Interactive prompts** - Choose what to install
- **System verification** - Checks Ubuntu version and permissions

## 📋 Prerequisites

- Fresh Ubuntu Server installation (20.04 LTS, 22.04 LTS, or 24.04 LTS)
- Root access or sudo privileges
- Internet connection

## 🛠️ Installation

1. **Download the script**
   ```bash
   wget https://raw.githubusercontent.com/yourusername/server-firststeps/main/setup.sh
   ```

2. **Make it executable**
   ```bash
   chmod +x setup.sh
   ```

3. **Run as root**
   ```bash
   sudo ./setup.sh
   ```

   Or run directly as root:
   ```bash
   sudo bash -c "$(curl -fsSL https://raw.githubusercontent.com/yourusername/server-firststeps/main/setup.sh)"
   ```

## 🎯 What Gets Installed

### Core Components
- **Docker CE** - Container runtime
- **Docker Compose** - Multi-container orchestration
- **Cockpit** - Web-based server management (port 9090)
- **Cockpit Navigator** - File browser for Cockpit

### Optional Modules (selected during installation)
- `cockpit-docker` - Manage Docker containers via Cockpit
- `cockpit-podman` - Manage Podman containers
- `cockpit-389-ds` - 389 Directory Server management
- `cockpit-machines` - Virtual machine management

## 🔧 Usage

After installation, access your server:

1. **Cockpit Web Interface**
   ```
   https://your-server-ip:9090
   ```

2. **Docker Management**
   ```bash
   # Verify Docker installation
   docker --version
   docker compose version
   
   # Run a test container
   docker run hello-world
   ```

3. **Cockpit Features**
   - System monitoring (CPU, memory, disk usage)
   - Service management
   - Network configuration
   - User account management
   - Docker container management (if module installed)
   - File browser with Navigator

## 📝 Script Details

The script performs the following steps:

1. **System Check** - Verifies Ubuntu Server and root permissions
2. **Confirmation** - Shows what will be installed
3. **System Update** - Updates all packages
4. **Docker Installation** - Installs Docker CE from official repository
5. **Cockpit Installation** - Installs and enables Cockpit web interface
6. **Module Installation** - Interactive selection of Cockpit modules
7. **Firewall Configuration** - Opens port 9090 for Cockpit (if UFW is active)
8. **Summary** - Shows installation results and access instructions

## ⚙️ Customization

Edit the script to:
- Skip certain installations
- Add additional packages
- Change default options
- Configure specific firewall rules

## 🧪 Testing

Tested on:
- Ubuntu Server 22.04 LTS
- Ubuntu Server 24.04 LTS

## ⚠️ Notes

- Cockpit runs on port 9090 (HTTPS)
- Docker requires root privileges
- Some Cockpit modules may require additional configuration
- The script is designed for fresh Ubuntu Server installations

## 🤝 Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## 📄 License

This project is licensed under the MIT License - see the LICENSE file for details.

## 🙏 Acknowledgments

- [Docker](https://www.docker.com/) for container technology
- [Cockpit Project](https://cockpit-project.org/) for the web interface
- [Ubuntu](https://ubuntu.com/) for the server platform

---

**Happy Server Management!** 🎉