# MetaGest operations

## Backups

The database lives in the Docker volume of the `db` service. A backup is a `pg_dump` in custom format.

```
powershell -File scripts\backup.ps1                      # manual dump to backups\
powershell -File scripts\backup.ps1 -CopyTo \\server\ti  # also copy it to another disk or share
```

- `scripts\start.ps1` takes a dump (`backups\ebt-pre-start-*.dump`) before it rebuilds or migrates, and stops if the dump fails.
- The newest 14 scheduled and manual dumps are kept, locally and in the destination (`-Keep` changes that; the app's "Quantas cópias guardar" sets it). Safety dumps (`pre-start`, `before-restore`, `before-rebuild`...) do not count toward that limit and are removed only after 180 days. `backups\` and `*.dump` are gitignored: dumps hold real data.
- A dump on the same disk is not a backup against disk failure. Use `-CopyTo` with an external drive or a share.
- `scripts\backup.ps1` writes `backup-status\status.json` (count, newest file, time, size) after every run. The API container mounts only that folder read-only at `/backup-status` (`Backup__Directory`); admins see the newest dump in Configurações through `GET /api/admin/backup-status`.
- Exposure: the API never sees the dumps (real data), only the status file. The endpoint never returns the folder path.

### Automatic backup (set in the app)

Admins choose the schedule in **Configurações > Administração > Cópia de segurança > Configurar backup**: on/off, frequency (hourly, every 6 hours, daily, weekly), time of day, weekday, the folder, drive or share the copy goes to, and how many dumps to keep. "Fazer backup agora" asks for one right away.

The API container cannot run `pg_dump` (no Docker access, read-only), so the plan is stored in the table `backup_settings` and a small agent on the server computer carries it out:

```
powershell -File scripts\install-backup-agent.ps1            # once: registers the task "MetaGest backup agent" (starts at logon, then checks the plan every few seconds)
powershell -File scripts\install-backup-agent.ps1 -Remove    # unregister
```

- `scripts\backup-agent.ps1` reads the plan, runs `backup.ps1` when a backup is due (also `-CopyTo` the chosen destination), and writes the result and a heartbeat back. The app shows the last result, the next run and warns when the agent has not been seen for 15 minutes.
- "Fazer backup agora" starts within about 5 seconds because the agent loops. While a backup runs, `scripts\backup.ps1` writes `backup-status\progress.json` (percent and stage); the API reads it through the read-only mount and the app shows a progress bar. `pg_dump` reports no percentage, so the dump stage compares the growing file with the size of the previous dump (first run: a quarter of the database size); treat it as approximate. A progress file that stops updating for 90 seconds counts as a dead run.
- "Interromper" in the app sets `cancel_requested_at` (`POST /api/admin/backup-settings/cancel`); a request that has not started is simply dropped. The agent watches the flag every second while a backup runs, kills `backup.ps1` and its children, ends the `pg_dump` session inside the container, deletes the partial files of that run (local and in the destination) and records "Backup cancelado." as the result. A cancelled run counts as the last run, so it does not retrigger at once.
- Every backup is verified before it counts as done: `pg_restore -l` must read the archive, the SHA-256 of the file inside the container must equal the copy on this computer (a `.sha256` file is written next to each dump), and the copy in the destination must hash the same. Any mismatch fails the run and the app shows it as failed. The destination is passed to `backup.ps1` through the `METAGEST_BACKUP_COPYTO` environment variable, so a path ending in a backslash (`D:\`) works.
- The agent writes `backup-status/agent.log` (start, each backup, errors, why it exited; kept under 200 KB). If the app says the agent is not active, read that file: the task restarts a dead agent within a minute. A destination folder is required: the API refuses to turn on automatic backup or to start a backup without one (field `destination`), and the app disables the buttons until one is set.
- Daily and weekly times are local time of the server computer. A missed slot (computer off) runs at the next check.
- The destination must be a full path (`D:\backups\metagest` or `\\server\share`); the app and the agent both refuse anything else. A destination that is not reachable shows as a failed run in the app.
- The schedule rules live in `Ebt.Core/Maintenance/BackupSchedule.cs` and in `backup-agent.ps1`; change both together.
- Without the agent task the app can save settings but nothing runs. A manual dump with an external copy still works: `powershell -File scripts\backup.ps1 -CopyTo <folder>`.

## Restore

### From the app (Configurações > Administração > Cópia de segurança > Restaurar backup)

Pick a backup in the list (this computer and the destination folder are both listed), press "Restaurar este backup…", read the warning and type `RESTAURAR`. Restoring replaces ALL current data with the data of that backup; everything done after it is lost, the system is unavailable for a few minutes and everyone has to sign in again.

The API cannot run `pg_restore` itself, so the request goes to the backup agent, which runs `scripts\restore.ps1`:

1. checks the dump (SHA-256 sidecar when present, `pg_restore -l`) and takes a safety backup of the current data (`ebt-before-restore-*.dump`);
2. restores into a brand new database `ebt_restore` and sanity-checks it (tables, at least one user). Any failure up to here leaves the live database untouched and the app shows the reason;
3. stops the `api` container, renames the live database to `ebt_before_restore_<time>` and the new one to `ebt`, starts the `api` again and waits for it to be healthy (migrations run on start, so a dump from an older schema is brought forward).

The previous database stays inside Postgres as `ebt_before_restore_<time>` (only the newest one is kept) so a bad restore can be rolled back by hand:

```
docker exec metagest-db-1 psql -U ebt -d postgres -c "select datname from pg_database where datname like 'ebt%'"
docker compose stop api
docker exec metagest-db-1 psql -U ebt -d postgres -c "alter database ebt rename to ebt_bad"
docker exec metagest-db-1 psql -U ebt -d postgres -c "alter database ebt_before_restore_<time> rename to ebt"
docker compose start api
```

The outcome is written to `backup-status\restore-result.json` and shown by the app when the API is back. The list of dumps is published by the agent in `backup-status\backups.json` (refreshed after every backup, on start and every 10 minutes).

### By hand

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

## Production checklist (before real use)

Rotating secrets on the development machine does not carry over: production gets its own `.env`. Do this on the production host.

- [ ] `.env` from `.env.example` with fresh random values: `EBT_DB_PASSWORD`, `EBT_JWT_KEY` (at least 32 bytes, not a placeholder: the API refuses those), `EBT_ADMIN_PASSWORD`. Never reuse the development values (`sidergest123`, `ebt-dev-password`): outside Development the API refuses to create the bootstrap admin with `sidergest123`, and user/password changes reject it (and a password equal to the username).
- [ ] Admin password changed after first login (Configurações, or `POST /api/auth/password`); the bootstrap admin is only created when the database has no users.
- [ ] `EBT_SWAGGER=false`.
- [ ] `EBT_MAX_IDLE_MINUTES` set to the longest idle lock the company accepts (for example `30`; 0..480, default 0 = no cap). The server enforces the idle lock itself: users pick their own time in Configurações, but with a cap "never" and anything longer become the cap. Changing it needs an `api` recreate.
- [ ] TLS reverse proxy in front of the API; `EBT_BEHIND_PROXY=true`, `EBT_ALLOWED_HOSTS` set to the real host name, `EBT_CORS_ORIGIN` set to the real web origin. Clients built with an `https://` `API_URL`.
- [ ] Database port stays bound to `127.0.0.1` (compose default); no firewall rule opens 25432 or 8080 to the network.
- [ ] Backup plan set in the app (destination on another disk or share), agent task installed with `scripts\install-backup-agent.ps1`, one restore tested on a spare machine.
- [ ] Docker Desktop starts with Windows (containers use `restart: unless-stopped`).
- [ ] Fiscal: A1 certificate path and password only as environment variables (`Fiscal__Sefaz__*`), start in Homologation, leave emission disabled until a test NF is authorized.
- [ ] Changing `EBT_JWT_KEY` later signs everyone out; changing `EBT_DB_PASSWORD` needs `ALTER USER ebt PASSWORD '...'` on the running database first, then the new `.env` value and an `api` recreate.

## Behind a reverse proxy

Set `EBT_BEHIND_PROXY=true` so the API trusts the forwarded client IP. Without it every user shares one login rate-limit bucket, and ten logins a minute lock everyone out. Set `EBT_ALLOWED_HOSTS` to the real host name.
