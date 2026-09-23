# Laptop backup (pull-based)

The backup server pulls daily snapshots of the laptop's home dir onto its backup drive. The laptop has no
access to the backups, so ransomware or anything else running as you on the laptop can't delete them.

- A dedicated `homebackup` account on the server tries every hour, taking at most one snapshot a day
  (skipped while the laptop is asleep or away).
- Each snapshot is a dated folder in `<drive>/backups/<laptop>/`; unchanged files are hard links to the previous
  snapshot, so they take almost no extra space. `latest` points at the newest.
- Keeps the newest snapshot of each of the last 7 days, 4 weeks and 4 months, plus the newest of every year.
  The `seed` snapshot (see below) is never pruned.
- Snapshots are owned by `homebackup`. Your account is in its group, so you can read everything but not change
  or delete anything.
- The laptop only accepts the server's key for read-only rsync of the home dir (`rrsync -ro`), and only
  accepts SSH over the tailnet.
- The laptop warns you (daily) if the newest snapshot is over 2 days old.
- Excluded paths are in `excludes`.

## Install

Both machines need to be on the tailnet (`server/setup_tailscale.sh`).

1. **On the server**, with the drive's UUID from `lsblk -o NAME,UUID,LABEL`:
   ```bash
   sudo ~/.setup/backup_server/install.sh <laptop tailnet name> <drive UUID>
   ```
   This creates the `homebackup` account and its pull key, mounts the drive at `BACKUP_DRIVE` (set in the
   repo's `.env`, along with the server's tailnet name) via fstab, replacing the desktop auto-mount, and
   enables the hourly `home-backup.timer`. Log out and back in afterwards so your account
   picks up the `homebackup` group.

2. **Optionally seed** from folders already at the top of the drive (moves them into a `seed` snapshot and
   replaces them with links to the latest snapshot; files only on the drive stay in `seed` forever):
   ```bash
   sudo ~/.setup/backup_server/seed.sh Documents Games Music Pictures Videos
   ```

3. **On the laptop**, run `./install.sh personal`. `personal/setup_server_ssh.sh` sets up its SSH server and
   authorizes the pull key, and `check_backup_age.timer` starts the daily age check.

4. **First backup**, on the server (it's large, so ideally with both machines on the same network):
   ```bash
   sudo systemctl start home-backup.service
   journalctl -fu home-backup
   ```

## Notes

- Everything that runs as `homebackup` is installed as root-owned copies (`/usr/local/lib/home-backup`,
  `/etc/home-backup`, `/etc/systemd/system`), so the account the laptop can log in as can't change it.
  Rerun `install.sh` after changing any file here.
- Don't edit files under the drive's `backups/` folder or the top-level links by hand.
- Restore by copying files out of a snapshot, e.g. `rsync -a /mnt/tosh/backups/<laptop>/latest/Documents/ ~/Documents/`.
