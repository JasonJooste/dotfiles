# Backups (Syncthing + snapshots)

Devices (laptop, phone) sync to the backup server with Syncthing, and the server takes daily snapshots of
everything it receives, plus folders that only live on the backup drive (Music etc.). Nothing on a device can
change or delete the snapshots, so ransomware or mistakes on a device can at worst affect the latest copy.

```
laptop ─┐ Syncthing, send only                 homebackup, daily
phone  ─┴──────────────────► <drive>/sync/<folder>/ ──────────► <drive>/snapshots/<source>/<date>/
                             <drive>/Music, for_dad, … ───────┘
```

- **Syncing:** each device shares folders as *Send Only*; the server receives them as *Receive Only* under
  `<drive>/sync/<folder label>/`. Syncthing only talks over the tailnet: no relays, discovery or NAT traversal,
  and its port is only open on `tailscale0`. It runs as your user on both machines.
- **Snapshots:** `backup-snapshot.timer` runs hourly as the dedicated `homebackup` account. Once a day per source,
  and only when Syncthing reports the folder idle and fully synced, it takes a snapshot into
  `<drive>/snapshots/<source>/<date>/` (unchanged files are hard links to the previous one, so they take almost
  no space) and points `latest` at it. Keeps the newest snapshot of each of the last 7 days, 4 weeks and 4 months,
  plus the newest of every year; a `seed` snapshot is never pruned.
- **Sources:** every receive-only Syncthing folder (named by its label), plus the drive folders in `sources`.
- **Permissions:** snapshots are owned by `homebackup`. You're in its group, so you can read everything but not
  change or delete it. The snapshot service can read any synced file (`CAP_DAC_READ_SEARCH`) without being root,
  and is sandboxed to only write snapshots and alerts.
- **Alerts:** problems (drive not mounted, a device not seen for 2 days, sync errors, failed or overdue
  snapshots) are written to `/var/lib/server-alerts/`. The laptop's `check_server` shows them, and any failed
  services on the server, as notifications once a day. Anything else on the server can raise an alert by
  writing a one-line message to a file there (and clear it by deleting the file).
- The server's tailnet name and the drive's mount point are in the repo's `.env`.

## Install (fresh server)

Both machines need to be on the tailnet (`server/setup_tailscale.sh`), and the server needs the server tier.

1. **On the server**, with the drive's UUID from `lsblk -o NAME,UUID,LABEL`:
   ```bash
   sudo ~/.setup/backup_server/install.sh <drive UUID>
   ```
   This mounts the drive at `BACKUP_DRIVE` via fstab (replacing the desktop auto-mount), sets up Syncthing as
   your user, creates the `homebackup` account, and enables the hourly snapshots. Log out and back in afterwards
   so your account picks up the `homebackup` group.
2. **Optionally seed** a device's snapshots from folders already at the top of the drive. They move into a `seed`
   snapshot, are replaced with links to the latest snapshot, and are copied into the device's synced folder, so
   Syncthing doesn't upload them again. Files only in the seed stay there forever.
   ```bash
   sudo ~/.setup/backup_server/seed.sh <hostname>-home Documents Games Pictures Videos
   ```
3. **Laptop:** run `./install.sh personal`. `personal/setup_syncthing.sh` installs Syncthing, pairs with the
   server over SSH and shares `~` as `<hostname>-home`, filtered by `~/.stignore` (`personal/dotfiles/stignore`).
   `check_server.timer` starts the daily alert check.
4. **Phone:** install *Syncthing-Fork* (F-Droid or Play Store). Then:
   - On the server, add the phone with the device ID from the app (*Settings → Show device ID*):
     ```bash
     ~/.setup/backup_server/add_device.sh <phone name> <phone device id>
     ```
   - In the app, add the server as a device, with the ID printed by `install.sh` (or `syncthing device-id` on
     the server) and the address `tcp://server:22000`. Keep Tailscale connected on the phone to sync away from
     home.
   - Share each folder with the server as **Send Only**, labelled `<phone name>-<folder>` (e.g.
     `phone-DCIM`): DCIM, Pictures, Documents, Download, Movies, Music, Recordings, and
     `Android/media/com.whatsapp/WhatsApp/Media`. The server accepts them automatically into `<drive>/sync/`.

Watch the first snapshots with `journalctl -fu backup-snapshot`, or run one now with
`sudo systemctl start backup-snapshot.service`.

## Migrating from the pull-based setup

1. **On the server:**
   ```bash
   cd ~/.setup && git pull
   sudo ~/.setup/backup_server/install.sh <drive UUID>   # leaves the snapshot timer off while backups/ exists
   sudo ~/.setup/backup_server/migrate.sh <laptop name>
   ```
   `migrate.sh` removes the pull service and key, moves `backups/<laptop>/` to `snapshots/<laptop>-home/`,
   moves Music back out of the seed into a real folder (owned by you, like `for_dad` and `for_mum`), repoints
   the top-level links, fills `sync/<laptop>-home/` from the latest snapshot so Syncthing doesn't re-upload it,
   and enables the snapshot timer.
2. **On the laptop,** remove the pull setup's SSH server and key, then run `./install.sh personal`:
   ```bash
   sed -i '/rrsync -ro/d' ~/.ssh/authorized_keys
   sudo rm -f /etc/ssh/sshd_config.d/10-keys-only.conf
   sudo ufw delete allow in on tailscale0 to any port 22 proto tcp
   sudo apt remove openssh-server
   ```

## Notes

- Everything that runs as `homebackup` is installed as root-owned copies (`/usr/local/lib/home-backup`,
  `/etc/home-backup`, `/etc/systemd/system`), so the account devices can log in as can't change it. Rerun
  `install.sh` after changing any file here.
- Files that are on the server but not on a device (e.g. from a seed) show as *locally changed* in the server's
  Syncthing folder; they're kept, and are in the snapshots.
- Don't edit files under `snapshots/` or the top-level links by hand.
- Restore by copying out of a snapshot, e.g.
  `rsync -a /mnt/tosh/snapshots/<hostname>-home/latest/Documents/ ~/Documents/`.
