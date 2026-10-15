# Vaultwarden Backup and Disaster Recovery

## Overview

This document describes the automated backup and disaster recovery system implemented for my self-hosted Vaultwarden password manager.

The system runs on a Raspberry Pi 5 and uses a combination of Linux utilities, encrypted cloud storage, and automated monitoring to protect application data.

The primary objectives are to:

- Automatically back up Vaultwarden application data.
- Maintain consistent SQLite database snapshots.
- Encrypt backups before uploading them to cloud storage.
- Retain multiple recovery points.
- Detect missed or failed backup executions.
- Support restoration following data loss or infrastructure failure.

---

## 1. Technologies Used

| Technology | Purpose |
|------------|---------|
| Bash | Backup automation |
| SQLite | Database backup |
| Rsync | Application file synchronization |
| Restic | Backup encryption and snapshot management |
| Rclone | Google Drive integration |
| Google Drive | Off-site backup storage |
| systemd | Automated scheduling |
| Healthchecks | Backup monitoring |

These technologies work together to provide an automated backup workflow.

---

## 2. Backup Architecture

The backup process runs daily through a systemd timer.

```text
                   Raspberry Pi 5
                         |
                         v
                    systemd Timer
                      3:00 AM
                         |
                         v
                   systemd Service
                         |
                         v
                      backup.sh
                         |
              +----------+----------+
              |                     |
              v                     v
         SQLite Backup         Rsync Files
              |                     |
              +----------+----------+
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
                 Backup Retention
                         |
                         v
                    Healthchecks
```

### Workflow

1. The systemd timer starts the backup service.
2. The service executes the Bash backup script.
3. SQLite creates a consistent database snapshot.
4. Rsync copies the remaining application files.
5. The files are placed in a temporary staging directory.
6. Restic creates an encrypted backup snapshot.
7. Rclone transfers the encrypted backup data to Google Drive.
8. Restic applies the configured retention policy.
9. Healthchecks receives a successful completion notification.
10. The temporary staging directory is removed.

If an earlier command fails, the script exits before sending the success notification.

---

## 3. Directory Structure

The production deployment uses the following directory structure:

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

The `data/` directory contains Vaultwarden application data.

The `backups/` directory is used for temporary staging during backup execution.

### Security Consideration

Neither directory should be uploaded to a public GitHub repository.

Vaultwarden application data may contain sensitive information, and backup staging directories may temporarily contain plaintext data.

---

## 4. Backup Script Configuration

The backup script defines the application directories:

```bash
VAULT_DIR="$HOME/docker/vaultwarden"
DATA_DIR="$VAULT_DIR/data"
BACKUP_DIR="$VAULT_DIR/backups"
```

The Restic repository is configured using:

```bash
export RESTIC_REPOSITORY="rclone:gdrive:Vaultwarden-Backups"
```

The encryption password is read from a protected local file:

```bash
export RESTIC_PASSWORD_FILE="$HOME/.config/restic/vaultwarden-password"
```

This separates sensitive credentials from the script itself.

### Required Dependencies

The backup host requires:

- `sqlite3`
- `rsync`
- `restic`
- `rclone`
- `curl`

Rclone must also be configured with an authorized Google Drive remote named `gdrive`.

The Restic repository must be initialized before its first backup.

---

## 5. Script Error Handling

The script begins with:

```bash
set -Eeuo pipefail
umask 077
```

### Error Handling

`set -Eeuo pipefail` enables several Bash error-handling behaviors:

- Exit when an unhandled command fails.
- Treat unset variables as errors.
- Detect failures within pipelines.
- Preserve error-trap behavior in supported contexts.

### File Permissions

`umask 077` restricts permissions on newly created files and directories.

This is particularly important because the temporary staging directory contains Vaultwarden application data before encryption.

---

## 6. Temporary Backup Directory

Each backup execution creates a unique staging directory:

```bash
STAGING_DIR=$(mktemp -d "$BACKUP_DIR/staging.XXXXXXXX")
```

This reduces the likelihood of naming conflicts between backup executions.

The script also registers a cleanup operation:

```bash
trap 'rm -rf -- "$STAGING_DIR"' EXIT
```

The temporary directory is removed when the shell exits normally or through a handled error.

### Security Consideration

The staging directory contains unencrypted application data.

It should remain on storage protected by appropriate filesystem permissions.

An abrupt shutdown or power failure may leave temporary files behind.

---

## 7. SQLite Database Backup

Vaultwarden uses SQLite to store application information.

Instead of directly copying an active database file, the script uses SQLite's built-in backup functionality:

```bash
sqlite3 "$DATA_DIR/db.sqlite3" \
  ".backup '$STAGING_DIR/db.sqlite3'"
```

### Why Use SQLite's Backup Command?

SQLite's `.backup` command creates a consistent database snapshot.

This avoids problems that can occur when directly copying a database file while it is being modified.

### Limitation

Although the database snapshot is consistent, the remaining application files are copied separately.

Therefore, the complete backup is not guaranteed to represent one identical point in time across every file.

---

## 8. Application File Backup

After the database snapshot is created, Rsync copies the remaining application files:

```bash
rsync -a \
  --exclude='db.sqlite3' \
  --exclude='db.sqlite3-shm' \
  --exclude='db.sqlite3-wal' \
  "$DATA_DIR/" "$STAGING_DIR/"
```

### Explanation

The command:

- Copies application files into the staging directory.
- Preserves relevant file attributes.
- Excludes the live SQLite database.
- Excludes SQLite temporary database files.

The staging directory now contains the SQLite snapshot and the remaining application data.

---

## 9. Restic Encryption

Restic creates an encrypted snapshot of the staging directory:

```bash
restic backup "$STAGING_DIR" \
  --tag vaultwarden
```

### Security Benefits

Restic provides:

- Encrypted backup storage.
- Snapshot-based recovery.
- Data integrity verification capabilities.
- Deduplication.
- Retention management.

Encryption occurs before backup data is stored in the remote repository.

### Encryption Password

The Restic password is stored outside the script.

Losing this password may make the encrypted repository unrecoverable.

A secure, independent copy of the password should be maintained.

---

## 10. Google Drive Integration

Rclone provides access to Google Drive.

The Restic repository uses the following configuration:

```bash
RESTIC_REPOSITORY="rclone:gdrive:Vaultwarden-Backups"
```

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

Google Drive stores the encrypted Restic repository.

This provides an off-site copy of application data that can be accessed if the original Raspberry Pi becomes unavailable.

### Security Considerations

Google Drive access credentials must be protected.

Restic encryption protects backup contents, but does not prevent someone with sufficient Google Drive permissions from deleting or corrupting repository files.

An independent backup copy would provide additional resilience.

---

## 11. Backup Retention

The script applies the following Restic retention policy:

```bash
restic forget \
  --tag vaultwarden \
  --group-by host,tags \
  --keep-daily 7 \
  --keep-weekly 4 \
  --keep-monthly 6 \
  --prune
```

### Retention Configuration

| Snapshot Type | Retention |
|---------------|-----------|
| Daily | 7 |
| Weekly | 4 |
| Monthly | 6 |

This policy maintains multiple recovery points while limiting unnecessary storage consumption.

The `--prune` option removes repository data that is no longer referenced by retained snapshots.

### Important Consideration

Retention rules specify which snapshots Restic attempts to preserve.

They do not guarantee that a fixed number of snapshots will exist.

---

## 12. systemd Backup Automation

The backup process is scheduled through systemd.

### Service Configuration

The service executes the backup script under a non-root Linux account.

Example:

```ini
[Unit]
Description=Vaultwarden Encrypted Google Drive Backup
Wants=network-online.target
After=network-online.target docker.service

[Service]
Type=oneshot
User=exampleuser
Group=exampleuser
Environment=HOME=/home/exampleuser
Environment=PATH=/usr/local/bin:/usr/bin:/bin
ExecStart=/home/exampleuser/docker/vaultwarden/backup.sh
TimeoutStartSec=1800
Restart=on-failure
RestartSec=5min
```

The example must be updated with the appropriate username and paths before deployment.

### Timer Configuration

```ini
[Unit]
Description=Daily Vaultwarden Backup Timer

[Timer]
OnCalendar=*-*-* 03:00:00
Persistent=true
Unit=vaultwarden-backup.service

[Install]
WantedBy=timers.target
```

The timer schedules a backup every day at 3:00 AM according to the server's local timezone.

`Persistent=true` allows systemd to initiate a missed scheduled execution when the timer becomes active again.

---

## 13. Installing the systemd Configuration

Copy the service and timer files into the systemd configuration directory.

Example:

```bash
sudo cp vaultwarden-backup.service /etc/systemd/system/
sudo cp vaultwarden-backup.timer /etc/systemd/system/
```

Reload systemd:

```bash
sudo systemctl daemon-reload
```

Enable and start the timer:

```bash
sudo systemctl enable --now vaultwarden-backup.timer
```

Verify the timer:

```bash
systemctl list-timers --all | grep vaultwarden
```

Check the service status:

```bash
systemctl status vaultwarden-backup.service
```

A completed `Type=oneshot` service may appear inactive after finishing successfully. Review its result and journal logs rather than relying only on whether it is currently running.

### Important

These commands are deployment instructions.

They are not necessary when simply documenting an already working production configuration.

---

## 14. Backup Monitoring

Healthchecks is used to monitor successful backup completion.

The script reads the monitoring endpoint from a local file:

```bash
HEALTHCHECK_URL=$(cat "$HOME/.config/restic/healthchecks-url")
```

After the backup and retention operations finish, it sends a request:

```bash
curl --fail --silent --show-error \
  --retry 3 \
  --retry-delay 5 \
  --max-time 20 \
  "$HEALTHCHECK_URL"
```

### Monitoring Behavior

If the script exits before this step, no success ping is sent.

Healthchecks can detect missed executions when the expected ping is not received within the configured monitoring window.

### Limitation

A successful ping does not prove that the backup can be restored.

Restoration testing remains necessary.

---

## 15. Backup Verification

Backups should be checked periodically to confirm that snapshots are being created.

### List Available Snapshots

```bash
restic snapshots
```

### View Repository Statistics

```bash
restic stats
```

### Check Repository Integrity

```bash
restic check
```

### Verify Backup Data

Restic also supports checking repository data:

```bash
restic check --read-data
```

Reading all repository data can take significant time and consume network bandwidth.

These checks help identify repository problems but do not replace a full application restoration test.

---

## 16. Disaster Recovery Procedure

The following procedure outlines how to restore Vaultwarden from an encrypted Restic backup.

**Perform recovery testing in an isolated environment before attempting restoration on a production system.**

### Step 1: Prepare the Recovery Environment

Install the required utilities:

```bash
sudo apt update
sudo apt install -y restic rclone sqlite3
```

Configure Rclone access to the existing Google Drive repository.

Restore the Restic password securely to the recovery host.

Set the repository configuration:

```bash
export RESTIC_REPOSITORY="rclone:gdrive:Vaultwarden-Backups"
export RESTIC_PASSWORD_FILE="$HOME/.config/restic/vaultwarden-password"
```

### Step 2: Identify Available Snapshots

List the available backups:

```bash
restic snapshots --tag vaultwarden
```

Identify the snapshot you want to restore.

Record its snapshot ID.

### Step 3: Restore to an Isolated Directory

Create a temporary recovery directory:

```bash
mkdir -p "$HOME/vaultwarden-recovery"
chmod 700 "$HOME/vaultwarden-recovery"
```

Restore the selected snapshot:

```bash
restic restore SNAPSHOT_ID \
  --target "$HOME/vaultwarden-recovery"
```

Replace `SNAPSHOT_ID` with the selected snapshot identifier.

### Step 4: Locate the Restored Data

Restic restores the original directory structure beneath the specified target.

Because the backup script backs up a temporary staging directory, the restored files may appear under a path similar to:

```text
~/vaultwarden-recovery/home/exampleuser/docker/vaultwarden/backups/staging.XXXXXXXX/
```

The exact path depends on the original staging directory recorded in the snapshot.

Locate the restored database:

```bash
find "$HOME/vaultwarden-recovery" -name db.sqlite3 -type f
```

Inspect the recovered files before continuing.

### Step 5: Validate the SQLite Database

After identifying the restored database, run:

```bash
sqlite3 "/path/to/restored/db.sqlite3" \
  "PRAGMA integrity_check;"
```

A successful integrity check should return:

```text
ok
```

Replace the example path with the actual restored database path.

### Step 6: Restore Vaultwarden Application Data

Before modifying a production installation:

1. Stop the Vaultwarden container.
2. Preserve the existing application data.
3. Identify the correct restored data directory.
4. Copy the recovered application files into the intended Vaultwarden data directory.
5. Verify ownership and permissions.
6. Start the container.
7. Confirm that the application operates correctly.

Do not overwrite an existing production data directory without first preserving it.

### Step 7: Validate Application Recovery

Verify that:

- Vaultwarden starts successfully.
- The expected account can authenticate.
- Two-factor authentication works.
- Vault entries are present.
- Attachments and other required data are accessible.
- Bitwarden clients can connect successfully.

Do not assume that a successful SQLite integrity check alone confirms complete application recovery.

---

## 17. Recovery Scenarios

### Scenario A: Accidental Data Deletion

Restore a snapshot from before the deletion occurred.

Validate the recovered data before replacing the production files.

### Scenario B: Database Corruption

Stop Vaultwarden and preserve the affected data.

Restore a known-good database snapshot and associated application files.

Verify database integrity and application functionality.

### Scenario C: Raspberry Pi Failure

Prepare replacement hardware or a compatible Linux server.

Install Docker and recreate the Vaultwarden container configuration.

Restore Rclone access and the Restic encryption password.

Download and restore the application data.

Reconfigure Cloudflare Tunnel and verify access.

### Scenario D: Google Drive Access Failure

Investigate whether the failure is temporary or related to account permissions.

Avoid modifying or deleting local data while recovery options are being assessed.

The current architecture relies on the configured Google Drive repository for off-site recovery.

Maintaining a second independent backup destination would improve resilience.

---

## 18. Recovery Objectives

The backup schedule is configured for one execution per day.

### Recovery Point Objective

A daily backup schedule means that up to approximately 24 hours of changes could be lost under normal successful operation.

A longer period of data loss is possible if scheduled backups fail or the latest snapshot is unusable.

A formal recovery point objective has not been established.

### Recovery Time Objective

Recovery time depends on:

- Backup size.
- Internet connectivity.
- Google Drive availability.
- Replacement hardware availability.
- Application configuration.
- Time required to validate recovered data.

A formal recovery time objective has not been established.

---

## 19. Recovery Testing

A restoration test was performed during the initial implementation of the backup system.

The test helped validate the ability to recover application data from the encrypted backup repository.

### Recommended Ongoing Tests

Future recovery testing should include:

1. Restoring a selected snapshot to an isolated directory.
2. Validating SQLite database integrity.
3. Verifying required application files.
4. Starting Vaultwarden in an isolated test environment.
5. Confirming successful authentication and data access.
6. Recording recovery duration and any issues encountered.

These tests should be performed periodically rather than relying solely on successful backup notifications.

---

## 20. Future Improvements

Potential enhancements include:

- Automated repository integrity checks.
- Scheduled restoration testing.
- Independent secondary backup storage.
- Improved alerts for backup failures.
- Backup storage immutability.
- Formal recovery time and recovery point objectives.
- More detailed recovery test records.
- Additional protections against simultaneous backup executions.

---

## Conclusion

This backup and disaster recovery implementation provides automated, encrypted, off-site backups for a self-hosted Vaultwarden password manager.

The project demonstrates practical experience with Linux automation, database backup consistency, encrypted cloud storage, retention policies, monitoring, and disaster recovery planning.

Although the system provides multiple recovery capabilities, continued testing and monitoring are necessary to maintain confidence in its reliability.