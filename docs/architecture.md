# System Architecture

## Overview

This project implements a self-hosted Vaultwarden password manager on a Raspberry Pi 5 using Docker.

The architecture was designed to provide secure remote access, persistent application storage, automated encrypted backups, and disaster recovery capabilities.

The infrastructure consists of two primary components:

1. **Application Infrastructure:** Hosts Vaultwarden and provides secure remote access through Cloudflare Tunnel.
2. **Backup Infrastructure:** Automates encrypted off-site backups using SQLite, Rsync, Restic, Rclone, Google Drive, and systemd.

---

## 1. Application Architecture

```text
                  Remote Client
                       |
                       | HTTPS
                       v
                 Cloudflare Edge
                       |
                       | Cloudflare Tunnel
                       v
                 Raspberry Pi 5
                       |
                       v
               cloudflared Container
                       |
                       | Docker Network
                       v
                Vaultwarden Container
                       |
                       | Persistent Volume
                       v
                 Vaultwarden Data
                       |
                       v
                  SQLite Database
```

### Request Flow

1. A client accesses the Vaultwarden application through its configured HTTPS domain.
2. Cloudflare receives the incoming request.
3. The request is forwarded through an established Cloudflare Tunnel.
4. The `cloudflared` container receives the request on the Raspberry Pi.
5. Traffic is forwarded to the Vaultwarden container through the shared Docker network.
6. Vaultwarden processes the request and accesses its persistent application data as needed.
7. The response is returned to the client through the same infrastructure.

This architecture allows Vaultwarden to be accessed remotely without requiring direct inbound port forwarding to the application.

---

## 2. Hosting Infrastructure

### Hardware

| Component | Configuration |
|-----------|---------------|
| Device | Raspberry Pi 5 |
| Memory | 16 GB RAM |
| Operating System | Linux |
| Container Platform | Docker |
| Container Management | Docker Compose |

The Raspberry Pi also hosts additional services, including a personal portfolio website and Pi-hole DNS filtering.

WireGuard VPN is configured on the host to provide secure remote network access.

### Container Configuration

Vaultwarden uses the following Docker image:

```yaml
image: vaultwarden/server:latest
```

The container is configured to restart automatically unless explicitly stopped.

```yaml
restart: unless-stopped
```

Application data is persisted using a bind mount:

```yaml
volumes:
  - ./data:/data
```

This ensures that application data remains available when the container is recreated or updated.

---

## 3. Docker Networking

Vaultwarden connects to an existing Docker network named:

```text
portfolio-network
```

The Docker Compose configuration specifies:

```yaml
networks:
  portfolio-network:
    external: true
```

This allows Vaultwarden to communicate with the existing Cloudflare Tunnel container.

### Network Design

```text
               Raspberry Pi 5
                     |
              Docker Engine
                     |
              portfolio-network
                     |
          +----------+----------+
          |                     |
          v                     v
    cloudflared             Vaultwarden
     Container               Container
          |                     |
          +---------------------+
```

The Vaultwarden Compose configuration does not publish a host port.

Instead, the application is accessible to the Cloudflare Tunnel container through Docker's internal networking.

### Security Benefits

This design:

- Avoids direct inbound router port forwarding for Vaultwarden.
- Reduces unnecessary exposure of the application.
- Allows communication between containers through an existing Docker network.
- Separates application networking from direct host-port publishing.

Docker networking provides useful service separation, although containers sharing a network can communicate where their configurations permit it.

---

## 4. Authentication and Access Control

Vaultwarden provides password management functionality compatible with Bitwarden clients.

### Account Authentication

The deployed application uses:

- Account password authentication.
- Two-factor authentication.
- Disabled public account registration.

Public registration is disabled through the following environment variable:

```yaml
SIGNUPS_ALLOWED: "false"
```

This prevents unrestricted account creation through the normal registration process.

### Administrative Access

The Raspberry Pi is administered using SSH with public-key authentication.

Host firewall rules are managed using UFW.

These controls help restrict administrative access to the underlying infrastructure.

---

## 5. Persistent Storage

Vaultwarden stores application data in a persistent directory on the Raspberry Pi.

### Directory Structure

```text
~/docker/vaultwarden/
|
|-- compose.yml
|-- backup.sh
|
|-- data/
|   |-- db.sqlite3
|   |-- ...
|
|-- backups/
```

The `data/` directory contains application data, including the SQLite database.

The `backups/` directory is used to temporarily stage data during the backup process.

### Data Persistence

Docker mounts the host's `data/` directory into the container at `/data`.

This separates application data from the container filesystem.

Recreating the container does not automatically delete the persisted application data.

---

## 6. Backup Architecture

Automated encrypted backups are implemented using a Bash script executed by systemd.

### Backup Workflow

```text
                systemd Timer
                 Daily 3 AM
                      |
                      v
               Backup Service
                      |
                      v
                  backup.sh
                      |
          +-----------+-----------+
          |                       |
          v                       v
     SQLite Backup           Rsync Files
          |                       |
          +-----------+-----------+
                      |
                      v
             Temporary Directory
                      |
                      v
                 Restic Backup
                      |
                      v
                Encryption
                      |
                      v
                 Rclone
                      |
                      v
                Google Drive
                      |
                      v
              Retention Policy
                      |
                      v
                Healthchecks
```

### Backup Components

| Component | Responsibility |
|-----------|----------------|
| Bash | Coordinates backup operations |
| SQLite | Creates a consistent database snapshot |
| Rsync | Copies remaining application files |
| Restic | Encrypts data and manages backup snapshots |
| Rclone | Provides access to Google Drive |
| Google Drive | Stores encrypted off-site backups |
| systemd | Schedules and executes backups |
| Healthchecks | Monitors successful script completion |

---

## 7. Database Backup Consistency

Vaultwarden uses SQLite to store application information.

The backup script uses SQLite's built-in backup command:

```bash
sqlite3 "$DATA_DIR/db.sqlite3" \
  ".backup '$STAGING_DIR/db.sqlite3'"
```

This creates a consistent snapshot of the database while avoiding a direct file copy of an active SQLite database.

The remaining application files are copied separately using Rsync.

The resulting backup includes a consistent database snapshot, although files copied separately are not guaranteed to represent the exact same point in time.

---

## 8. Backup Encryption and Cloud Storage

Restic is responsible for encrypting backup data.

The backup repository is accessed through Rclone:

```bash
RESTIC_REPOSITORY="rclone:gdrive:Vaultwarden-Backups"
```

The Restic encryption password is stored in a protected local file rather than embedded directly in the script.

### Data Flow

```text
Vaultwarden Data
      |
      v
Temporary Staging
      |
      v
Restic Encryption
      |
      v
Rclone
      |
      v
Google Drive
```

Backup data is encrypted by Restic before being stored remotely.

The Google Drive repository contains encrypted backup data rather than directly readable Vaultwarden files.

---

## 9. Backup Scheduling

Backups are scheduled using a systemd timer.

```ini
OnCalendar=*-*-* 03:00:00
Persistent=true
```

This schedules the backup service to run daily at 3:00 AM according to the server's local timezone.

The persistent timer setting allows systemd to initiate a missed scheduled execution when the timer becomes active again.

### Failure Handling

The backup service includes:

```ini
Restart=on-failure
RestartSec=5min
TimeoutStartSec=1800
```

These settings configure retry behavior and limit individual execution time.

Additional start-rate limits restrict repeated execution attempts.

---

## 10. Backup Retention

Restic applies the following retention policy:

| Snapshot Type | Retention |
|---------------|-----------|
| Daily | 7 |
| Weekly | 4 |
| Monthly | 6 |

Snapshots are tagged with:

```text
vaultwarden
```

The retention policy provides multiple recovery points while helping manage storage consumption.

---

## 11. Backup Monitoring

Healthchecks is used to monitor backup completion.

After the backup and retention operations complete successfully, the script sends an HTTP request to a configured Healthchecks endpoint.

The monitoring URL is stored in a protected local file.

### Monitoring Flow

```text
Backup Completed
       |
       v
Retention Applied
       |
       v
Healthchecks Ping
       |
       v
Monitoring Service
```

If the expected ping is not received within the configured monitoring window, Healthchecks can detect the missed execution.

A successful ping indicates that the script reached its notification stage. It does not independently verify backup restorability.

---

## 12. Disaster Recovery

The backup architecture supports restoration of Vaultwarden application data from encrypted off-site snapshots.

A restoration test was performed to validate that data could be recovered.

The general recovery process consists of:

1. Accessing the Restic repository.
2. Identifying a suitable backup snapshot.
3. Restoring the required application files.
4. Validating the restored SQLite database.
5. Confirming access to recovered data.

Periodic restoration testing is an important future maintenance activity.

---

## 13. Security Considerations

The architecture incorporates several security controls:

| Control | Implementation |
|---------|----------------|
| Secure remote access | Cloudflare Tunnel |
| Transport encryption | HTTPS and encrypted tunnel connections |
| Account protection | Two-factor authentication |
| Registration control | Disabled public signups |
| Administrative authentication | SSH public-key authentication |
| Host firewall | UFW |
| Backup encryption | Restic |
| Credential separation | Passwords stored outside scripts |
| Backup permissions | Restrictive file creation permissions |
| Off-site recovery | Encrypted Google Drive backups |
| Service separation | Docker containers and networking |

These controls help reduce unnecessary exposure, protect application data, and support recovery following system failures.

---

## 14. Future Improvements

Potential enhancements include:

- Pinning Vaultwarden to a tested Docker image version.
- Implementing periodic automated backup integrity checks.
- Scheduling recurring restoration tests.
- Expanding infrastructure monitoring.
- Reviewing container permissions and security settings.
- Improving backup failure alerting.
- Documenting recovery time and recovery point objectives.

---

## Conclusion

This architecture combines containerized password management, secure remote access, encrypted off-site backups, automated scheduling, and monitoring.

The project provided hands-on experience designing and maintaining a self-hosted application with an emphasis on security, reliability, and disaster recovery.