# MetaGest operations

## Backups

The database lives in the Docker volume of the `db` service. A backup is a `pg_dump` in custom format.

```
powershell -File scripts\backup.ps1                      # manual dump to backups\
powershell -File scripts\backup.ps1 -CopyTo \\server\ti  # also copy it to another disk or share
```

- `scripts\start.ps1` takes a dump (`backups\ebt-pre-start-*.dump`) before it rebuilds or migrates, and stops if the dump fails.
- The newest 14 dumps are kept (`-Keep` changes that). `backups\` and `*.dump` are gitignored: dumps hold real data.
- A dump on the same disk is not a backup against disk failure. Use `-CopyTo` with an external drive or a share.
- `scriptsackup.ps1` writes `backup-statusstatus.json` (count, newest file, time, size) after every run. The API container mounts only that folder read-only at `/backup-status` (`Backup__Directory`); admins see the newest dump in Configurações through `GET /api/admin/backup-status`. Recreate the `api` container once after pulling this change so the new mount exists, and run one backup so the file exists.
- Exposure: the API never sees the dumps (real data), only the status file. The endpoint never returns the folder path.

### Nightly backup (Windows Task Scheduler)

```
schtasks /Create /SC DAILY /ST 22:00 /TN "MetaGest backup" /TR "powershell -NoProfile -File C:\Users\italo\Desktop\sidergest\scripts\backup.ps1 -Reason nightly -CopyTo D:\backups\metagest"
```

## Restore

Restoring replaces the whole database. Take a fresh dump first (`scripts\backup.ps1 -Reason before-restore`).

```
docker compose stop api
docker cp backups\ebt-<name>.dump metagest-db-1:/tmp/restore.dump
docker exec metagest-db-1 pg_restore -U ebt -d ebt --clean --if-exists --no-owner /tmp/restore.dump
docker compose start api
```

Check the login and a recent order before telling anyone the system is back. Test the restore on a spare machine once; an untested backup is a guess.

## Restart behavior

`db` and `api` use `restart: unless-stopped`: they come back after a reboot as soon as Docker Desktop starts. Set Docker Desktop to start with Windows. `stop.bat` stops them on purpose and they stay down until `start.bat`.

## Logs

Container logs rotate at 10 MB x 5 files per service. Read them with `docker compose logs --tail 200 api`.

## Secrets to rotate before real use

- Admin password `sidergest123` (local mode) and the database password `ebt-dev-password` (volumes created before `.env` existed).
- `EBT_JWT_KEY` (changing it signs everyone out).

## Behind a reverse proxy

Set `EBT_BEHIND_PROXY=true` so the API trusts the forwarded client IP. Without it every user shares one login rate-limit bucket, and ten logins a minute lock everyone out. Set `EBT_ALLOWED_HOSTS` to the real host name.
