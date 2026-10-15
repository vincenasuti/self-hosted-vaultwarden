# Self-Hosted Vaultwarden | Secure Password Management & Automated Backups

A self-hosted password management solution deployed on a Raspberry Pi 5 using Docker, with secure remote access through Cloudflare Tunnel and automated encrypted backups to Google Drive.

This project demonstrates practical experience in Linux administration, containerization, network security, identity and access management, backup automation, and disaster recovery.

## TL;DR

- **Application:** Vaultwarden, a lightweight Bitwarden-compatible password manager.
- **Infrastructure:** Raspberry Pi 5 running Linux.
- **Containerization:** Docker and Docker Compose.
- **Remote Access:** Cloudflare Tunnel with HTTPS.
- **Authentication:** Password-based authentication with two-factor authentication enabled.
- **Data Protection:** Encrypted backups using Restic.
- **Cloud Storage:** Google Drive integration through Rclone.
- **Automation:** Daily backups scheduled using systemd.
- **Monitoring:** Healthchecks monitors successful backup completion.
- **Disaster Recovery:** Backup restoration tested successfully.

## Project Objectives

The primary objective was to deploy a self-hosted password management solution while maintaining control over application data and implementing appropriate security and recovery mechanisms.

Specific objectives included:

1. Deploy Vaultwarden using Docker.
2. Configure secure remote access without exposing the application through direct router port forwarding.
3. Implement multifactor authentication and disable public account registration.
4. Establish automated, encrypted off-site backups.
5. Implement a backup retention policy.
6. Monitor backup execution and identify failures.
7. Validate the ability to restore application data following a failure.

---

## Technology Stack

| Technology | Purpose |
|------------|---------|
| Raspberry Pi 5 | Physical hosting infrastructure |
| Linux | Server operating system |
| Docker | Containerized application deployment |
| Docker Compose | Container configuration and management |
| Vaultwarden | Self-hosted password management |
| Cloudflare Tunnel | Secure remote application access |
| SQLite | Vaultwarden application database |
| Bash | Backup automation scripting |
| Restic | Backup encryption and snapshot management |
| Rclone | Google Drive storage integration |
| Google Drive | Off-site backup storage |
| systemd | Backup scheduling and execution |
| Healthchecks | Backup completion monitoring |

---

## System Architecture

```text
                     INTERNET
                        |
                        v
                  Cloudflare Edge
                        |
                        v
                 Cloudflare Tunnel
                        |
                        v
                  Raspberry Pi 5
                        |
                Docker Environment
                        |
          +-------------+-------------+
          |                           |
          v                           v
    cloudflared                  Vaultwarden
     Container                    Container
          |                           |
          +-------- Docker -----------+
                    Network
                                      |
                                      v
                              Persistent Storage
                                      |
                                      v
                                SQLite Database
```

The Vaultwarden container is connected to an existing external Docker network named `portfolio-network`.

Cloudflare Tunnel provides public access to the application without requiring a directly published host port.

The application is accessible through a dedicated HTTPS subdomain.

---

## Docker Deployment

Vaultwarden is deployed using Docker Compose.

The configuration includes:

- Automatic container restart.
- Persistent application storage.
- Disabled public account registration.
- A dedicated application domain.
- Connection to an existing Docker network.

### Docker Compose Configuration

```yaml
services:
  vaultwarden:
    image: vaultwarden/server:latest
    container_name: vaultwarden
    restart: unless-stopped

    environment:
      DOMAIN: "https://vault.vincenasuti.com"
      SIGNUPS_ALLOWED: "false"

    volumes:
      - ./data:/data

    networks:
      - portfolio-network

networks:
  portfolio-network:
    external: true
```

The container does not publish a host port. Instead, Cloudflare Tunnel communicates with Vaultwarden through the shared Docker network.

The `data` directory provides persistent storage so application data is retained when the container is recreated.

---

## Security Implementation

Security considerations were incorporated into the deployment and ongoing management of Vaultwarden.

### 1. Secure Remote Access

Cloudflare Tunnel establishes an outbound connection from the Raspberry Pi to Cloudflare.

This eliminates the need to configure direct inbound port forwarding for the password manager.

### 2. Multifactor Authentication

Two-factor authentication is enabled for the Vaultwarden account.

This adds an additional authentication requirement beyond the account password.

### 3. Disabled Public Registration

The Docker Compose configuration includes:

```yaml
SIGNUPS_ALLOWED: "false"
```

This prevents unrestricted public account registration through the normal signup process.

### 4. Persistent Data Storage

Vaultwarden application data is stored in a persistent directory outside the container.

This separates application data from the container lifecycle.

### 5. Restricted Backup Permissions

The backup script uses:

```bash
umask 077
```

This restricts the permissions of newly created backup files and directories.

### 6. Encrypted Off-Site Backups

Restic encrypts backup data before storing it in Google Drive through Rclone.

The Restic repository password is stored separately from the backup script.

---

## Automated Backup Architecture

One of the primary components of this project is an automated backup system designed to protect Vaultwarden application data.

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
             +---------+---------+
             |                   |
             v                   v
       SQLite Backup        Rsync Data
             |                   |
             +---------+---------+
                       |
                       v
              Temporary Staging
                       |
                       v
                Restic Backup
                       |
                       v
                Data Encryption
                       |
                       v
                 Rclone Backend
                       |
                       v
                  Google Drive
                       |
                       v
                Retention Policy
                       |
                       v
                Healthchecks Ping
```

### Backup Process

The automated backup script performs the following operations:

1. Creates a temporary staging directory.
2. Generates a consistent SQLite database backup.
3. Copies the remaining Vaultwarden application files.
4. Encrypts the backup using Restic.
5. Stores the encrypted backup in Google Drive through Rclone.
6. Applies the configured backup retention policy.
7. Removes temporary staging files.
8. Sends a successful completion notification to Healthchecks.

The script uses Bash error handling to stop execution when critical commands fail.

---

## Backup Retention Policy

Restic manages backup snapshots using the following retention policy:

| Backup Type | Retention |
|-------------|-----------|
| Daily | 7 |
| Weekly | 4 |
| Monthly | 6 |

The retention policy balances recovery options with long-term storage management.

Snapshots are tagged `vaultwarden` to identify backups associated with this application.

---

## Backup Scheduling

Backups are automated using a systemd service and timer.

### Schedule

```ini
[Timer]
OnCalendar=*-*-* 03:00:00
Persistent=true
Unit=vaultwarden-backup.service
```

The timer initiates the backup process daily at 3:00 AM.

The `Persistent=true` setting allows systemd to trigger a missed scheduled backup after the timer becomes active again.

### Failure Handling

The backup service includes:

```ini
Restart=on-failure
RestartSec=5min
TimeoutStartSec=1800
```

These settings provide:

- Automatic retries following failures.
- A five-minute delay between retry attempts.
- A maximum execution time of 30 minutes.

Additional start-rate limits prevent excessive restart attempts.

---

## Backup Monitoring

Healthchecks is used to monitor successful backup completion.

Following a successful backup and retention operation, the script sends an HTTP request to a dedicated monitoring endpoint.

If the expected notification is not received within the configured monitoring window, Healthchecks can identify the missed execution.

This provides visibility into scheduled backup activity without requiring manual inspection after every run.

---

## Disaster Recovery

Backup restoration was tested to validate the recovery process.

The recovery workflow involves:

1. Accessing the encrypted Restic repository.
2. Identifying an available backup snapshot.
3. Restoring the required Vaultwarden application data.
4. Validating the restored files and database.
5. Confirming that the recovered data can be accessed.

Successful restoration testing provides greater confidence in the backup process than backup creation alone.

---

## Testing and Validation

The following checks are used to validate the deployment.

### Container Status

```bash
docker ps
```

Confirms that the Vaultwarden container is running.

### Container Logs

```bash
docker logs vaultwarden
```

Reviews application logs for errors.

### Backup Timer Status

```bash
systemctl status vaultwarden-backup.timer
```

Confirms that the backup timer is active.

### Backup Service Logs

```bash
journalctl -u vaultwarden-backup.service
```

Reviews backup execution history and errors.

### Backup Snapshot Verification

```bash
restic snapshots
```

Lists available snapshots when the Restic repository and credentials are configured.

### Remote Access

The application is accessed through its HTTPS subdomain to verify that Cloudflare Tunnel routing and Vaultwarden authentication function correctly.

---

## Challenges and Lessons Learned

### Container Networking

Configured communication between Vaultwarden and Cloudflare Tunnel through a shared Docker network without publishing a host port.

### Backup Consistency

Used SQLite's built-in backup functionality to create a consistent database snapshot rather than directly copying an active database file.

### Encryption and Off-Site Storage

Integrated Restic and Rclone to encrypt application backups and store them remotely.

### Automation

Implemented systemd services and timers to automate recurring backup operations.

### Monitoring

Integrated Healthchecks to provide visibility into backup execution and identify missed runs.

### Disaster Recovery

Performed restoration testing to verify that backup data could be recovered.

---

## Repository Structure

```text
self-hosted-vaultwarden/
|
|-- README.md
|
|-- docs/
|   |-- architecture.md
|   |-- installation.md
|   |-- security.md
|   |-- backup-recovery.md
|   |-- troubleshooting.md
|
|-- docker/
|   |-- compose.example.yml
|
|-- scripts/
|   |-- backup.example.sh
|
|-- systemd/
|   |-- vaultwarden-backup.service
|   |-- vaultwarden-backup.timer
|
|-- .gitignore
```

The repository contains technical documentation and sanitized configuration examples.

It does not contain production password vault data, authentication credentials, or encrypted backup archives.

---

## Future Improvements

Potential improvements include:

- Pinning Docker images to tested versions.
- Implementing automated container update notifications.
- Expanding backup integrity verification.
- Scheduling periodic disaster recovery tests.
- Improving monitoring and alerting.
- Further hardening container and application security.

---

## Security Disclaimer

This repository is intended for educational and professional portfolio purposes.

It does not contain production Vaultwarden databases, encryption passwords, authentication tokens, Cloudflare credentials, or backup archives.

Configuration files are provided as examples and should be reviewed before deployment.

---

## Author

**Vincent Nasuti**

Information Systems & Analytics Student | Cybersecurity Enthusiast

This project demonstrates practical experience in secure application deployment, Linux administration, backup automation, encryption, and disaster recovery.