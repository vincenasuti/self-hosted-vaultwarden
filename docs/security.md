# Vaultwarden Security Implementation

## Overview

Security was a primary consideration when deploying my self-hosted Vaultwarden password manager.

Because password managers store highly sensitive information, I implemented multiple security controls to protect authentication, application access, infrastructure, and backup data.

This document outlines the security measures implemented in my deployment, their purposes, and potential improvements.

---

## 1. Security Objectives

The primary security objectives of this project were:

1. Protect stored credentials from unauthorized access.
2. Secure remote access to the Vaultwarden application.
3. Reduce unnecessary exposure of internal infrastructure.
4. Implement multifactor authentication.
5. Restrict unauthorized account registration.
6. Protect backup data through encryption.
7. Maintain recoverability following data loss or system failure.
8. Apply least-privilege principles where practical.

These objectives guided the architecture and configuration of the deployment.

---

## 2. Defense-in-Depth Architecture

The deployment uses multiple security controls rather than relying on a single protective mechanism.

```text
                  INTERNET
                     |
                     v
              Cloudflare HTTPS
                     |
                     v
              Cloudflare Tunnel
                     |
                     v
              Docker Network
                     |
                     v
              Vaultwarden
                     |
              Authentication
                     |
              Two-Factor Auth
                     |
                     v
              Encrypted Vault
                     |
                     v
              Persistent Storage
                     |
                     v
              Encrypted Backups
```

Each layer addresses different security concerns.

For example, Cloudflare Tunnel reduces direct network exposure, while multifactor authentication helps protect against unauthorized account access.

---

## 3. Secure Remote Access

### Cloudflare Tunnel

Vaultwarden is accessible remotely through Cloudflare Tunnel.

Instead of forwarding an inbound port from my router to the Raspberry Pi, the `cloudflared` container establishes an outbound connection to Cloudflare.

The application is accessed through a dedicated HTTPS subdomain.

### Security Benefits

This architecture:

- Eliminates the need for direct inbound port forwarding to Vaultwarden.
- Reduces direct exposure of the application's network interface.
- Provides encrypted connections between clients and Cloudflare.
- Allows Cloudflare to forward traffic through an established tunnel.

### Security Considerations

Cloudflare Tunnel does not automatically make an application private.

The configured public hostname remains reachable unless additional access restrictions are implemented.

Vaultwarden's authentication mechanisms remain essential for protecting accounts.

Cloudflare also becomes part of the application's availability and trust model.

---

## 4. Container Networking

Vaultwarden runs inside a Docker container.

The container connects to an existing external Docker network:

```yaml
networks:
  portfolio-network:
    external: true
```

The Cloudflare Tunnel container is connected to the same network.

This allows Cloudflare Tunnel to communicate with Vaultwarden through Docker networking.

### No Published Host Port

The Vaultwarden Compose configuration does not contain a `ports` mapping.

This means the application is not directly published through a Docker-managed host port.

Instead, Cloudflare Tunnel accesses the application internally.

### Security Benefits

- Reduces unnecessary host-port exposure.
- Allows communication between required containers.
- Separates application deployment from host-level networking.

### Limitations

Docker networking is not equivalent to complete security isolation.

Containers connected to the same network may communicate with one another.

A future improvement would involve reviewing network segmentation and limiting connectivity to only the services that require it.

---

## 5. Authentication Security

### Master Password Authentication

Vaultwarden uses account credentials to authenticate users.

A strong, unique master password is essential because it protects access to the password vault.

### Two-Factor Authentication

Two-factor authentication is enabled for my Vaultwarden account.

This adds an additional authentication requirement beyond the master password.

### Security Benefits

Multifactor authentication helps reduce the likelihood of unauthorized account access when a password is compromised.

### Recovery Considerations

Two-factor authentication recovery information should be stored securely and separately from the Vaultwarden instance.

Loss of both authentication factors and recovery information could prevent account access.

---

## 6. Account Registration Controls

Public account registration is disabled through the following Docker Compose environment variable:

```yaml
SIGNUPS_ALLOWED: "false"
```

### Purpose

This prevents unrestricted account creation through Vaultwarden's normal public registration process.

### Security Benefits

- Limits unauthorized account creation.
- Reduces unnecessary application usage.
- Supports a controlled account management process.

### Limitation

Disabling registration does not prevent attempts to authenticate to existing accounts.

Additional authentication protections remain necessary.

---

## 7. Host Security

Vaultwarden runs on a Raspberry Pi 5 using Linux.

The host also supports additional services, including a personal portfolio website, Pi-hole DNS filtering, and WireGuard VPN.

### SSH Authentication

Administrative access uses SSH public-key authentication.

Password-based SSH authentication was disabled during the Raspberry Pi's initial security configuration.

### UFW Firewall

UFW is used to manage host firewall rules.

Firewall rules are configured to permit required services while restricting unnecessary traffic.

### Security Benefits

These measures help reduce the attack surface of the underlying Linux host.

### Additional Considerations

Because multiple services share the Raspberry Pi, host security is especially important.

A compromise of the host could potentially affect multiple applications, including Vaultwarden.

---

## 8. Persistent Data Storage

Vaultwarden application data is stored using a Docker bind mount:

```yaml
volumes:
  - ./data:/data
```

This stores application data outside the container's writable filesystem.

### Benefits

- Preserves data when containers are recreated.
- Simplifies application backup procedures.
- Separates persistent data from the application container lifecycle.

### Security Considerations

Persistent storage does not automatically encrypt files stored on the Raspberry Pi.

Host filesystem permissions, operating system security, and physical access controls remain important.

Vaultwarden's client-side vault encryption protects vault contents, but not necessarily every file or metadata item in the application data directory.

---

## 9. Backup Security

An automated backup system protects Vaultwarden application data against accidental deletion, corruption, or infrastructure failure.

The backup solution uses:

- SQLite
- Rsync
- Restic
- Rclone
- Google Drive
- systemd
- Healthchecks

### SQLite Database Backup

The script uses SQLite's built-in backup functionality:

```bash
sqlite3 "$DATA_DIR/db.sqlite3" \
  ".backup '$STAGING_DIR/db.sqlite3'"
```

This creates a consistent database snapshot without directly copying the active database file.

### Temporary Backup Storage

Backup data is staged temporarily before being uploaded.

The script uses:

```bash
umask 077
```

This restricts permissions on newly created files and directories.

### Temporary File Cleanup

The script includes:

```bash
trap 'rm -rf -- "$STAGING_DIR"' EXIT
```

This removes the temporary staging directory when the script exits normally or through a handled shell error.

It does not guarantee cleanup following abrupt termination, such as a power failure.

---

## 10. Backup Encryption

Restic encrypts backup data before storing it in Google Drive.

The backup repository is configured through Rclone:

```bash
RESTIC_REPOSITORY="rclone:gdrive:Vaultwarden-Backups"
```

The encryption password is stored separately from the script:

```bash
RESTIC_PASSWORD_FILE="$HOME/.config/restic/vaultwarden-password"
```

### Security Benefits

- Backup contents are encrypted before remote storage.
- The encryption password is not embedded in the backup script.
- Remote storage does not require access to plaintext application data.

### Important Considerations

The Restic password must be protected and retained securely.

Without the correct repository password, encrypted backup data cannot be recovered.

Encryption also does not prevent an attacker with sufficient cloud-storage permissions from deleting backup files.

---

## 11. Backup Retention

Restic applies the following retention policy:

| Snapshot Type | Retention |
|---------------|-----------|
| Daily | 7 |
| Weekly | 4 |
| Monthly | 6 |

The retention policy provides multiple recovery points while helping manage storage usage.

### Security Considerations

Multiple recovery points can help recover from accidental changes or corruption.

However, retention policies do not replace protections against malicious backup deletion.

Additional protections, such as independent backup copies or storage immutability, could improve resilience.

---

## 12. Backup Automation

The backup process is executed using a systemd service and timer.

### Execution Account

The backup service runs under a non-root Linux user.

This avoids unnecessarily executing the backup script with root privileges.

### Scheduling

The timer uses:

```ini
OnCalendar=*-*-* 03:00:00
Persistent=true
```

Backups are scheduled daily at 3:00 AM.

The persistent timer configuration allows systemd to initiate missed scheduled executions when the timer becomes active again.

### Failure Handling

The service includes:

```ini
Restart=on-failure
RestartSec=5min
TimeoutStartSec=1800
```

These settings configure automatic retry behavior and prevent individual executions from running indefinitely.

---

## 13. Backup Monitoring

Healthchecks monitors backup completion.

After the backup and retention operations finish successfully, the script sends an HTTP request to the configured Healthchecks endpoint.

### Monitoring Workflow

```text
Scheduled Backup
       |
       v
Backup Execution
       |
       v
Restic Encryption
       |
       v
Remote Storage
       |
       v
Retention Policy
       |
       v
Healthchecks Ping
```

### Security and Reliability Benefits

This monitoring helps identify missed or failed scheduled executions.

### Limitations

A successful monitoring notification does not independently verify that backup data can be restored.

Periodic restoration testing is necessary to validate recoverability.

The Healthchecks URL is stored outside the script to avoid embedding the monitoring credential in source code.

---

## 14. Disaster Recovery

A restoration test was performed to validate the ability to recover Vaultwarden application data.

The recovery process involves accessing the encrypted Restic repository and restoring application files from an available snapshot.

### Recovery Objectives

The backup system is intended to support recovery following:

- Accidental data deletion.
- Application corruption.
- Container failure.
- Storage failure.
- Loss of the original Raspberry Pi.

Recovery from complete host loss additionally requires access to the Restic credentials, Rclone configuration, and replacement infrastructure.

### Recovery Limitations

Because backups run daily, changes made after the most recent successful backup may not be recoverable.

Recovery time depends on factors such as backup size, network connectivity, and replacement infrastructure availability.

Formal recovery time and recovery point objectives have not been established.

---

## 15. Threat Considerations

The following table summarizes several relevant threats and the controls implemented.

| Threat | Mitigation |
|--------|------------|
| Unauthorized account access | Master password and two-factor authentication |
| Unrestricted account creation | Disabled public registration |
| Direct exposure of Vaultwarden ports | Cloudflare Tunnel and internal Docker networking |
| Compromised remote backup storage | Restic encryption |
| Accidental data loss | Automated backups |
| Application or database corruption | Backup snapshots and restoration procedures |
| Missed backup executions | Healthchecks monitoring |
| Unauthorized administrative access | SSH key authentication and UFW |
| Excessive backup storage usage | Restic retention policy |

These controls reduce certain risks but do not eliminate them entirely.

---

## 16. Future Security Improvements

Potential improvements include:

1. Pin Vaultwarden to a tested Docker image version.
2. Implement periodic automated Restic integrity checks.
3. Schedule recurring disaster recovery tests.
4. Review Docker network segmentation.
5. Evaluate additional container hardening options.
6. Implement independent or immutable backup storage.
7. Establish formal recovery time and recovery point objectives.
8. Review application and host update procedures.
9. Expand monitoring for application availability and backup failures.

---

## Conclusion

This Vaultwarden deployment demonstrates a defense-in-depth approach to self-hosting a security-sensitive application.

The implementation combines secure remote access, multifactor authentication, container networking, Linux host security, encrypted off-site backups, automated scheduling, and monitoring.

The project reinforced the importance of protecting both the application and its supporting infrastructure while maintaining the ability to recover from failures.