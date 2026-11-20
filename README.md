# Server First Steps

An idempotent setup script that turns a fresh Ubuntu Server install into a
headless home server you can run and reach unattended. It installs Docker CE
and Cockpit, then fixes the things that make a server fail months later in
someone else's house: missing DHCP in netplan, password SSH, an open firewall,
no panic recovery, and unbounded container logs.

## Features

- **Docker CE** with Compose, log rotation, and `live-restore`
- **Cockpit** on port 9090, with Navigator and optional modules
- **netplan DHCP repair** for installs that ran without a network cable
- **Key-only SSH** with root login disabled
- **Firewall defaults** that deny inbound, allow SSH, and scope Cockpit to the LAN
- **Panic recovery** so a kernel panic reboots the box by itself
- **Unattended security updates** without surprise reboots
- **Optional Tailscale**, for administration from anywhere
- **Optional cloudflared**, for publishing services through a Cloudflare Tunnel
- **Optional opencode** for the account you nominate
- **Idempotent** — a second run skips everything already done

## Prerequisites

- Fresh Ubuntu Server install, 22.04 LTS or newer
- Root access or sudo
- An internet connection
- Your SSH public key already in `~/.ssh/authorized_keys` on the server. The
  script turns password logins off, so add the key first or keep a console
  session open.

## Installation

```bash
git clone https://github.com/kidtaroi/server-firststeps.git
cd server-firststeps
sudo ./setup.sh
```

Non-interactive with the common options:

```bash
sudo ./setup.sh --yes --user "$USER" --with-tailscale --with-cloudflared
```

## Flags

| Flag | Effect |
| --- | --- |
| `--yes` | Accept defaults, no prompts |
| `--user NAME` | Add to the `docker` group and target for opencode |
| `--with-tailscale` | Install Tailscale, login still manual |
| `--with-cloudflared` | Install cloudflared, token still manual |
| `--with-opencode` | Install opencode for `--user` |
| `--no-cockpit` | Skip Cockpit and its modules |
| `--no-upgrade` | Skip `apt upgrade`, install only |
| `--skip-network` | Leave netplan untouched |
| `--skip-ssh` | Leave sshd untouched |
| `--docker-root PATH` | Parent for stacks and appdata, default `/docker` |

## What gets installed

### Core
- **Docker CE** — container runtime
- **Docker Compose** — plugin, invoked as `docker compose`
- **Cockpit** — web management on port 9090
- **Cockpit Navigator** — file browser
- Base tooling: `git`, `jq`, `tmux`, `htop`, `rsync`, `ncdu`, `tree`, `ethtool`, `curl`, `gnupg`

### Optional Cockpit modules
- `cockpit-docker` — container UI
- `cockpit-podman` — Podman UI
- `cockpit-machines` — VM management
- `cockpit-389-ds` — directory server

Modules that a given Ubuntu release does not ship are skipped with a warning
rather than failing the run.

### Optional agents
- **Tailscale** — private network for administration; every port and protocol works
- **cloudflared** — outbound tunnel for publishing HTTP services
- **opencode** — linked into `/usr/local/bin` so it works from any shell

## The DHCP problem this script fixes

An Ubuntu Server install that runs without a network cable writes a netplan file
with no addressing method:

```yaml
network:
  ethernets:
    eno1:
      match:
        macaddress: ac:e2:d3:09:08:72
      set-name: eno1
  version: 2
```

The link comes up at full speed and the interface never asks for a lease, so
`ip a` shows `state UP` with only a link-local address. The router and the cable
are fine. The script detects the missing `dhcp4: true`, identifies the wired
interface by its current MAC rather than assuming a name, and rewrites the file.

## Security defaults

- SSH accepts keys only; passwords and root logins are rejected
- `ufw` denies inbound by default
- SSH stays open on all interfaces for recovery
- Cockpit is reachable only from the detected LAN subnet and from `tailscale0`
- Container logs are capped at 10 MB × 3 files
- `kernel.panic = 10` reboots the machine after a panic

Check any of these after a run:

```bash
sudo sshd -T | grep -E 'passwordauthentication|permitrootlogin'
sudo ufw status verbose
docker info --format '{{.LoggingDriver}}'
```

## After the script

1. Confirm your SSH key works in a second session before closing the console.
2. `sudo tailscale up --ssh --hostname=<name>` and disable key expiry for the node.
3. `sudo cloudflared service install <tunnel-token>` if you want public hostnames.
4. Set **power on after AC loss** in the BIOS. Without it, a power cut leaves the
   box off until someone presses the button.
5. Reboot with nothing attached and confirm the machine returns unattended.

Steps 4 and 5 are the difference between a server and a box that works until the
first outage.

## Layout

```
/docker/stacks    compose files, one directory per service
/docker/appdata   persistent container state
```

Run a service:

```bash
cd /docker/stacks/<service>
docker compose up -d
```

## Tested on

- Ubuntu Server 26.04 LTS
- Ubuntu Server 24.04 LTS

## Notes

- Cockpit serves HTTPS on port 9090 with a self-signed certificate
- `docker` group membership needs a fresh login to take effect
- The script does not install Cockpit modules that are absent from your release
- Run it again after a release upgrade; it repairs anything that changed

## Contributing

Issues and pull requests welcome.

## License

MIT
