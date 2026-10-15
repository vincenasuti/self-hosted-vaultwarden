#!/bin/bash

# ============================================================
# Self-Hosted Vaultwarden
# Automated Encrypted Backup Script
#
# Technologies:
#   - SQLite
#   - Rsync
#   - Restic
#   - Rclone
#   - Google Drive
#   - Healthchecks
#
# This is a sanitized example of the production backup script.
# Configure paths, credentials, and the Rclone remote before use.
# ============================================================

# Exit on errors, unset variables, and pipeline failures
set -Eeuo pipefail

# Restrict permissions on newly created files and directories
umask 077

# ============================================================
# CONFIGURATION
# ============================================================

# Vaultwarden application directories
VAULT_DIR="$HOME/docker/vaultwarden"
DATA_DIR="$VAULT_DIR/data"
BACKUP_DIR="$VAULT_DIR/backups"

# Restic repository hosted on Google Drive through Rclone
# Requires an existing Rclone remote named "gdrive"
export RESTIC_REPOSITORY="rclone:gdrive:Vaultwarden-Backups"

# Restic encryption password stored outside the repository
export RESTIC_PASSWORD_FILE="$HOME/.config/restic/vaultwarden-password"

# Healthchecks monitoring URL stored outside the repository
HEALTHCHECK_FILE="$HOME/.config/restic/healthchecks-url"

# ============================================================
# TEMPORARY BACKUP DIRECTORY
# ============================================================

# Ensure the local staging directory exists
mkdir -p "$BACKUP_DIR"

# Create a unique temporary directory for each backup
STAGING_DIR=$(mktemp -d "$BACKUP_DIR/staging.XXXXXXXX")

# Remove temporary files when the script exits
trap 'rm -rf -- "$STAGING_DIR"' EXIT

echo "Starting Vaultwarden backup..."

# ============================================================
# SQLITE DATABASE BACKUP
# ============================================================

# Create a consistent snapshot of the SQLite database
# without directly copying the active database file

sqlite3 "$DATA_DIR/db.sqlite3" \
  ".backup '$STAGING_DIR/db.sqlite3'"

# ============================================================
# APPLICATION DATA BACKUP
# ============================================================

# Copy remaining Vaultwarden application files
# Exclude the live database and SQLite temporary files

rsync -a \
  --exclude='db.sqlite3' \
  --exclude='db.sqlite3-shm' \
  --exclude='db.sqlite3-wal' \
  "$DATA_DIR/" "$STAGING_DIR/"

# ============================================================
# ENCRYPTED CLOUD BACKUP
# ============================================================

echo "Encrypting and uploading backup..."

# Restic encrypts the backup before storing it remotely
# Rclone provides access to the Google Drive repository

restic backup "$STAGING_DIR" \
  --tag vaultwarden

# ============================================================
# BACKUP RETENTION
# ============================================================

echo "Applying backup retention policy..."

# Retain:
#   7 daily snapshots
#   4 weekly snapshots
#   6 monthly snapshots

restic forget \
  --tag vaultwarden \
  --group-by host,tags \
  --keep-daily 7 \
  --keep-weekly 4 \
  --keep-monthly 6 \
  --prune

echo "Vaultwarden backup and retention completed successfully."

# ============================================================
# BACKUP MONITORING
# ============================================================

# Read the monitoring URL from a protected local file
HEALTHCHECK_URL=$(cat "$HEALTHCHECK_FILE")

# Notify Healthchecks after successful backup completion

curl --fail --silent --show-error \
  --retry 3 \
  --retry-delay 5 \
  --max-time 20 \
  "$HEALTHCHECK_URL"

echo "Backup monitoring notification sent successfully."