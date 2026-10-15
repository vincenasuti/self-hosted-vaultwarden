# Vaultwarden Installation and Deployment Guide

## Overview

This document explains how to deploy a self-hosted Vaultwarden password manager using Docker Compose and Cloudflare Tunnel.

The deployment is based on a Raspberry Pi 5 running Linux.

Vaultwarden is configured with persistent storage, disabled public registration, and secure remote access through an existing Cloudflare Tunnel.

The configuration examples are sanitized versions of the production deployment.

---

## 1. Prerequisites

The following components are required:

| Component | Purpose |
|-----------|---------|
| Linux Server | Hosts Vaultwarden |
| Docker Engine | Runs the Vaultwarden container |
| Docker Compose | Manages container configuration |
| Cloudflare Account | Manages the domain and tunnel |
| Cloudflare Tunnel | Provides remote access |
| Domain Name | Provides an HTTPS address |
| SSH | Enables remote server administration |

The production environment uses a Raspberry Pi 5 with Docker installed.

This guide assumes Docker and Docker Compose are already configured.

---

## 2. Create the Project Directory

Create a directory to store the Vaultwarden configuration and persistent application data.

```bash
mkdir -p ~/docker/vaultwarden
cd ~/docker/vaultwarden
```

The directory will eventually contain:

```text
vaultwarden/
├── compose.yml
└── data/
```

The `data/` directory stores Vaultwarden application data outside the container.

---

## 3. Configure Docker Networking

Vaultwarden communicates with Cloudflare Tunnel through a shared Docker network.

Create the network:

```bash
docker network create portfolio-network
```

If the network already exists, this step can be skipped.

Verify the network:

```bash
docker network ls
```

The network should appear in the output.

### Why Use a Shared Docker Network?

Docker provides internal networking between containers connected to the same network.

This allows Cloudflare Tunnel to communicate with Vaultwarden without publishing a Vaultwarden port on the Raspberry Pi.

The production deployment uses an external Docker network named:

```text
portfolio-network
```

---

## 4. Create the Docker Compose Configuration

Create the configuration file:

```bash
nano compose.yml
```

Add the following:

```yaml
services:
  vaultwarden:
    image: vaultwarden/server:latest
    container_name: vaultwarden
    restart: unless-stopped

    environment:
      DOMAIN: "https://vault.example.com"
      SIGNUPS_ALLOWED: "false"

    volumes:
      - ./data:/data

    networks:
      - portfolio-network

networks:
  portfolio-network:
    external: true
```

Replace `vault.example.com` with your own HTTPS domain.

### Configuration Explanation

| Setting | Description |
|---------|-------------|
| `image` | Vaultwarden container image |
| `container_name` | Assigns the container name |
| `restart` | Restarts the container automatically |
| `DOMAIN` | Defines the application's external URL |
| `SIGNUPS_ALLOWED` | Disables public registration |
| `volumes` | Persists application data |
| `networks` | Connects to the existing Docker network |

### Security Consideration

Public account registration is disabled:

```yaml
SIGNUPS_ALLOWED: "false"
```

For a new installation, establish your initial account through a controlled setup process before disabling registration.

Do not leave public registration enabled unnecessarily.

---

## 5. Deploy Vaultwarden

Start the container:

```bash
docker compose up -d
```

Verify that it is running:

```bash
docker ps
```

Review application logs:

```bash
docker logs vaultwarden
```

The container should start without critical errors.

### Persistent Storage

The Compose configuration includes:

```yaml
volumes:
  - ./data:/data
```

This maps the local `data/` directory to Vaultwarden's application data directory.

The bind mount allows application data to persist independently of the container lifecycle.

---

## 6. Configure Cloudflare Tunnel

Cloudflare Tunnel provides remote access to Vaultwarden without requiring direct inbound router port forwarding.

The production environment uses an existing `cloudflared` container connected to the shared Docker network.

### Create or Select a Tunnel

Using the Cloudflare dashboard:

1. Navigate to the Cloudflare Zero Trust dashboard.
2. Open the tunnel management section.
3. Create a new tunnel or select an existing tunnel.
4. Configure a public hostname for Vaultwarden.
5. Configure the hostname to forward requests to the Vaultwarden container.

### Public Hostname Configuration

Example:

| Setting | Value |
|---------|-------|
| Subdomain | `vault` |
| Domain | `example.com` |
| Service Type | HTTP |
| Service URL | `vaultwarden:80` |

The service URL uses the Docker container name.

Docker's internal DNS allows containers on the same user-defined network to resolve one another by name.

### Important Networking Requirement

The Cloudflare Tunnel container must be connected to the same Docker network as Vaultwarden.

For an existing container, this can be accomplished with:

```bash
docker network connect portfolio-network cloudflared
```

Replace `cloudflared` if your tunnel container uses a different name.

For a permanent configuration, define the shared network in the Cloudflare Tunnel container's Compose configuration.

A manual `docker network connect` operation may need to be repeated if the container is recreated.

### Security Consideration

Cloudflare Tunnel does not automatically require users to authenticate through Cloudflare Access.

Vaultwarden's own authentication and two-factor authentication remain important.

Additional access restrictions can be evaluated separately, with compatibility testing for Bitwarden clients.

---

## 7. Verify Remote Access

After configuring Cloudflare Tunnel, open the configured HTTPS domain in a browser.

Example:

```text
https://vault.example.com
```

Confirm that:

1. The Vaultwarden login page loads.
2. The browser establishes an HTTPS connection.
3. Authentication works correctly.
4. Two-factor authentication functions as expected.
5. Vaultwarden can be accessed from an authorized remote device.

Do not use a production password vault for testing with untrusted accounts or devices.

---

## 8. Configure Account Security

### Disable Public Registration

Confirm that the Compose configuration contains:

```yaml
SIGNUPS_ALLOWED: "false"
```

This prevents new users from registering through the normal public signup process.

### Enable Two-Factor Authentication

After creating the Vaultwarden account:

1. Sign in to the web vault.
2. Open account security settings.
3. Navigate to two-step login settings.
4. Configure a supported authentication method.
5. Store recovery information securely.

Two-factor authentication adds protection beyond the account password.

### Use a Strong Master Password

Use a unique, strong master password that is not reused across other services.

Store recovery information separately from the Vaultwarden instance.

---

## 9. Verify Container Networking

Inspect the Docker network:

```bash
docker network inspect portfolio-network
```

Confirm that the Vaultwarden and Cloudflare Tunnel containers are connected.

Review the Vaultwarden container:

```bash
docker inspect vaultwarden
```

Verify that the container is attached to the expected network.

### Troubleshooting Connectivity

If the Vaultwarden website is inaccessible:

1. Confirm the Vaultwarden container is running.
2. Check the Vaultwarden logs.
3. Confirm the Cloudflare Tunnel container is running.
4. Verify both containers share the Docker network.
5. Check the Cloudflare public hostname configuration.
6. Confirm the service URL references the correct container and port.

---

## 10. Configure Automated Backups

The production deployment uses a separate Bash script to back up Vaultwarden application data.

The backup process uses:

- SQLite for database snapshots.
- Rsync for application files.
- Restic for encryption and snapshot management.
- Rclone for Google Drive integration.
- systemd for scheduling.
- Healthchecks for monitoring.

The example backup script is located at:

```text
scripts/backup.example.sh
```

The systemd configuration examples are located in:

```text
systemd/
├── vaultwarden-backup.service
└── vaultwarden-backup.timer
```

See `backup-recovery.md` for detailed backup configuration and recovery procedures once that document is added.

---

## 11. Updating Vaultwarden

The production configuration currently uses:

```yaml
image: vaultwarden/server:latest
```

To update the container, first ensure a recent backup exists and review the release notes.

Then execute:

```bash
docker compose pull
docker compose up -d
```

Verify that the application starts successfully:

```bash
docker ps
docker logs vaultwarden
```

Test login and essential functionality after the update.

### Recommended Improvement

Pinning the Docker image to a tested version can improve deployment consistency and reduce unexpected changes.

---

## 12. Useful Administrative Commands

### View Running Containers

```bash
docker ps
```

### View Vaultwarden Logs

```bash
docker logs vaultwarden
```

### Restart Vaultwarden

```bash
docker compose restart
```

### Stop Vaultwarden

```bash
docker compose down
```

### Start Vaultwarden

```bash
docker compose up -d
```

### Inspect Docker Networks

```bash
docker network ls
```

### Inspect the Shared Network

```bash
docker network inspect portfolio-network
```

### Check Disk Usage

```bash
df -h
```

---

## 13. Security Considerations

The deployment incorporates several security controls:

| Control | Implementation |
|---------|----------------|
| Remote access | Cloudflare Tunnel |
| Transport security | HTTPS |
| Account authentication | Master password and two-factor authentication |
| Registration control | Disabled public registration |
| Persistent storage | Docker bind mount |
| Administrative access | SSH key authentication |
| Host firewall | UFW |
| Backup encryption | Restic |
| Off-site storage | Google Drive through Rclone |

### Additional Recommendations

- Keep Docker and the host operating system updated.
- Use unique credentials and protect recovery codes.
- Review Vaultwarden security advisories.
- Restrict access to application data and configuration files.
- Avoid committing secrets to version control.
- Maintain encrypted backups and periodically test restoration.
- Monitor the availability of the application and backup system.

---

## Conclusion

This deployment demonstrates how a password management application can be self-hosted using Docker and securely accessed through Cloudflare Tunnel.

The implementation combines container networking, persistent storage, authentication controls, and automated backup infrastructure to support a reliable self-hosted service.