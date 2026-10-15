# Vaultwarden Troubleshooting Guide

## Overview

This document provides troubleshooting procedures for the self-hosted Vaultwarden deployment running on a Raspberry Pi 5.

The deployment uses Docker, Cloudflare Tunnel, SQLite, Restic, Rclone, Google Drive, and systemd.

The goal of this guide is to provide a structured approach to identifying and resolving common application, networking, and backup issues.

> **Note:** These are diagnostic procedures and potential solutions. They do not necessarily represent issues encountered during the original deployment.

---

## 1. Troubleshooting Methodology

When investigating an issue, I follow a structured process:

1. Identify the affected service.
2. Determine whether the issue involves the application, container, network, or host.
3. Review relevant logs and service status.
4. Identify the likely cause.
5. Apply the least disruptive corrective action.
6. Verify that the service is functioning.
7. Document the issue and resolution.

This approach helps avoid unnecessary configuration changes and reduces the risk of introducing additional problems.

---

## 2. Vaultwarden Container Not Running

### Symptoms

- Vaultwarden is inaccessible.
- The container does not appear in the list of running containers.
- The application fails to start.

### Diagnosis

Check running containers:

```bash
docker ps
```

Check all containers, including stopped containers:

```bash
docker ps -a
```

Review Vaultwarden logs:

```bash
docker logs --tail 100 vaultwarden
```

Check the Docker service:

```bash
sudo systemctl status docker
```

### Potential Causes

- Docker is not running.
- Invalid Docker Compose configuration.
- Application startup failure.
- Incorrect volume permissions.
- Insufficient disk space.

### Resolution

Navigate to the Vaultwarden directory:

```bash
cd ~/docker/vaultwarden
```

Validate the Compose configuration:

```bash
docker compose config
```

Start the container:

```bash
docker compose up -d
```

Verify its status:

```bash
docker ps
```

If the issue persists, investigate the specific error messages in the container logs.

---

## 3. Vaultwarden Website Not Accessible

### Symptoms

- Browser displays a connection error.
- Cloudflare returns an error.
- Vaultwarden works internally but not remotely.

### Diagnosis

First, verify that Vaultwarden is running:

```bash
docker ps
```

Review application logs:

```bash
docker logs --tail 100 vaultwarden
```

Inspect the Docker network:

```bash
docker network inspect portfolio-network
```

Confirm that both Vaultwarden and the Cloudflare Tunnel container are connected.

### Potential Causes

- Vaultwarden container is stopped.
- Cloudflare Tunnel is disconnected.
- Containers are on different Docker networks.
- Incorrect Cloudflare public hostname configuration.
- Incorrect internal service URL.

### Resolution

Verify that the Cloudflare Tunnel public hostname points to:

```text
http://vaultwarden:80
```

This example assumes that the container is named `vaultwarden` and that the tunnel container shares its Docker network.

If the containers do not share a network, update the Docker configuration.

Avoid publishing additional ports or modifying firewall rules until the cause has been identified.

---

## 4. Cloudflare Tunnel Not Working

### Symptoms

- Vaultwarden is inaccessible through its public domain.
- Cloudflare reports a tunnel connectivity issue.
- The tunnel container repeatedly restarts.

### Diagnosis

Identify the Cloudflare Tunnel container:

```bash
docker ps -a
```

Review its logs, replacing the container name if necessary:

```bash
docker logs --tail 100 cloudflared
```

Inspect the Docker network:

```bash
docker network inspect portfolio-network
```

### Potential Causes

- Cloudflare Tunnel container is stopped.
- Invalid or expired tunnel credentials.
- Incorrect public hostname configuration.
- Network connectivity issues.
- Incorrect internal service destination.

### Resolution

Confirm that:

1. The tunnel container is running.
2. The tunnel is connected in Cloudflare.
3. The public hostname is configured correctly.
4. The tunnel container can reach Vaultwarden.
5. Both containers are attached to the required Docker network.

For a tunnel managed through Docker Compose, restart it using the appropriate Compose configuration after reviewing its logs.

---

## 5. Docker Network Issues

### Symptoms

- Cloudflare Tunnel cannot communicate with Vaultwarden.
- Containers are running but the application is inaccessible.
- Docker reports that the network does not exist.

### Diagnosis

List Docker networks:

```bash
docker network ls
```

Inspect the shared network:

```bash
docker network inspect portfolio-network
```

### Potential Cause

The required external Docker network was never created or is not attached to the appropriate containers.

### Resolution

If the network does not exist, create it:

```bash
docker network create portfolio-network
```

Ensure the Vaultwarden Compose configuration includes:

```yaml
networks:
  portfolio-network:
    external: true
```

Restart the Vaultwarden deployment if required:

```bash
docker compose up -d
```

The Cloudflare Tunnel container must also be connected to the network.

For persistent connectivity, define the shared network in the tunnel container's Compose configuration.

---

## 6. Vaultwarden Database Issues

### Symptoms

- Vaultwarden fails to start.
- Database errors appear in the logs.
- Application data appears unavailable.

### Diagnosis

Review the container logs:

```bash
docker logs --tail 100 vaultwarden
```

Check the data directory:

```bash
ls -lah ~/docker/vaultwarden/data
```

Check available disk space:

```bash
df -h
```

### Potential Causes

- Incorrect file permissions.
- Storage exhaustion.
- Database corruption.
- Missing application data.
- Incorrect Docker volume mapping.

### Resolution

Confirm that the Compose configuration contains:

```yaml
volumes:
  - ./data:/data
```

If database corruption is suspected, preserve the existing data before attempting repairs.

A database integrity check can be performed against a separate, safely created SQLite backup:

```bash
sqlite3 /path/to/database-copy.sqlite3 \
  "PRAGMA integrity_check;"
```

A healthy database should return:

```text
ok
```

Do not delete or overwrite the production database during troubleshooting.

---

## 7. Automated Backup Not Running

### Symptoms

- No recent Restic snapshots.
- Healthchecks reports a missed backup.
- The systemd timer appears inactive.

### Diagnosis

Check the timer:

```bash
systemctl status vaultwarden-backup.timer
```

List scheduled timers:

```bash
systemctl list-timers --all | grep vaultwarden
```

Check the backup service:

```bash
systemctl status vaultwarden-backup.service
```

Review service logs:

```bash
journalctl -u vaultwarden-backup.service -n 100 --no-pager
```

### Potential Causes

- Timer is disabled.
- Service configuration contains incorrect paths.
- Backup script is not executable.
- Missing dependencies.
- Restic or Rclone authentication failure.
- Backup execution timed out.

### Resolution

If the timer is disabled:

```bash
sudo systemctl enable --now vaultwarden-backup.timer
```

If the service configuration was modified:

```bash
sudo systemctl daemon-reload
```

Verify that the configured script exists:

```bash
ls -l ~/docker/vaultwarden/backup.sh
```

Investigate any errors in the systemd journal before manually rerunning the backup.

---

## 8. Restic Backup Failure

### Symptoms

- Backup script exits with an error.
- No new snapshot appears.
- Restic cannot access the repository.

### Diagnosis

Check the repository configuration:

```bash
echo "$RESTIC_REPOSITORY"
```

If the variable is not set in the current shell, configure it for your environment.

Example:

```bash
export RESTIC_REPOSITORY="rclone:gdrive:Vaultwarden-Backups"
export RESTIC_PASSWORD_FILE="$HOME/.config/restic/vaultwarden-password"
```

List snapshots:

```bash
restic snapshots
```

### Potential Causes

- Incorrect repository configuration.
- Missing encryption password file.
- Rclone authentication failure.
- Network connectivity problems.
- Google Drive storage issues.

### Resolution

Verify that:

1. The Restic password file exists.
2. The configured repository path is correct.
3. Rclone can access Google Drive.
4. The server has network connectivity.
5. The repository is accessible.

Do not initialize a new repository over an existing repository path while troubleshooting.

---

## 9. Rclone Cannot Access Google Drive

### Symptoms

- Restic cannot connect to its remote repository.
- Authentication errors appear.
- Rclone reports access failures.

### Diagnosis

List configured Rclone remotes:

```bash
rclone listremotes
```

Verify access to the expected remote:

```bash
rclone lsd gdrive:
```

### Potential Causes

- Expired or revoked authorization.
- Missing Rclone configuration.
- Incorrect remote name.
- Google Drive connectivity issues.
- Insufficient account permissions.

### Resolution

Review the Rclone configuration:

```bash
rclone config
```

If authorization has expired, follow Rclone's authentication process to reconnect the remote.

Avoid exposing Rclone configuration files or authentication tokens in public repositories.

---

## 10. Restic Repository Integrity Issues

### Symptoms

- Restic reports repository errors.
- Snapshots cannot be listed or restored.
- Integrity checks fail.

### Diagnosis

Check repository integrity:

```bash
restic check
```

For a more comprehensive check:

```bash
restic check --read-data
```

### Resolution

Preserve the existing repository before attempting repairs.

Review the exact Restic error message and consult the appropriate recovery procedure.

Avoid running destructive maintenance commands without understanding their impact.

A second independent backup destination can provide additional protection against repository corruption or loss.

---

## 11. Healthchecks Not Receiving Notifications

### Symptoms

- Backup appears successful.
- Healthchecks reports a missed execution.
- Monitoring notifications are not received.

### Diagnosis

Review backup service logs:

```bash
journalctl -u vaultwarden-backup.service -n 100 --no-pager
```

Verify that the monitoring configuration file exists:

```bash
ls -l ~/.config/restic/healthchecks-url
```

### Potential Causes

- Monitoring URL is incorrect.
- The backup script exits before the notification step.
- Network connectivity is unavailable.
- Healthchecks is temporarily unreachable.
- Monitoring schedule or grace period is misconfigured.

### Resolution

Confirm that the monitoring URL is stored correctly and that the service can reach the monitoring endpoint.

Review the backup logs to determine whether the script reached its final notification step.

Do not print the monitoring URL in public logs or documentation.

---

## 12. Insufficient Disk Space

### Symptoms

- Backups fail during temporary staging.
- Vaultwarden cannot write application data.
- Docker reports storage errors.

### Diagnosis

Check disk space:

```bash
df -h
```

Check Vaultwarden directory usage:

```bash
du -sh ~/docker/vaultwarden/*
```

### Potential Causes

- Temporary backup directories were not cleaned up.
- Application data has grown.
- Docker images or logs consume excessive storage.
- Other services share the same storage device.

### Resolution

Identify which directories consume the most space.

Review old temporary backup directories carefully.

Do not delete application data, backup repositories, or Docker volumes without verifying their contents and purpose.

---

## 13. Backup Restoration Issues

### Symptoms

- Restored data is incomplete.
- Vaultwarden fails to start after restoration.
- The database is present but application files are missing.

### Diagnosis

List available snapshots:

```bash
restic snapshots --tag vaultwarden
```

Restore a selected snapshot to an isolated directory:

```bash
restic restore SNAPSHOT_ID \
  --target "$HOME/vaultwarden-recovery"
```

Replace `SNAPSHOT_ID` with the desired snapshot identifier.

Inspect the restored directory structure.

### Potential Causes

- Incorrect snapshot selected.
- Files restored to an unexpected directory.
- Missing application files.
- Incorrect ownership or permissions.
- Incompatible application version.

### Resolution

Verify the restored SQLite database and application files before attempting to start Vaultwarden.

Use an isolated recovery environment when possible.

See [Backup and Disaster Recovery](backup-recovery.md) for the full recovery procedure.

---

## 14. Useful Diagnostic Commands

| Command | Purpose |
|---------|---------|
| `docker ps` | View running containers |
| `docker ps -a` | View all containers |
| `docker logs vaultwarden` | Review application logs |
| `docker network ls` | List Docker networks |
| `docker network inspect portfolio-network` | Inspect shared network |
| `systemctl status docker` | Check Docker service |
| `systemctl status vaultwarden-backup.timer` | Check backup timer |
| `journalctl -u vaultwarden-backup.service` | Review backup logs |
| `restic snapshots` | List backup snapshots |
| `restic check` | Check repository integrity |
| `rclone listremotes` | List cloud storage remotes |
| `df -h` | Check disk usage |

---

## 15. Lessons Learned

This project reinforced several important infrastructure troubleshooting principles.

### Logs Are Essential

Application logs, Docker logs, and systemd journals provide valuable information when diagnosing failures.

### Networking Should Be Verified Before Changing Configurations

Container networking, DNS, and tunnel connectivity should be investigated systematically.

### Backups Require Verification

A successful backup command does not guarantee that data can be restored.

Repository integrity checks and restoration testing are necessary.

### Automation Requires Monitoring

Scheduled tasks can fail without being immediately visible.

Monitoring helps identify missed or unsuccessful executions.

### Documentation Improves Recovery

Maintaining configuration examples and troubleshooting procedures makes it easier to rebuild services following system failures.

---

## Conclusion

This troubleshooting guide provides a structured approach to diagnosing issues across the Vaultwarden application, Docker infrastructure, Cloudflare Tunnel, and encrypted backup system.

The procedures emphasize log analysis, service verification, safe recovery practices, and minimizing unnecessary configuration changes.