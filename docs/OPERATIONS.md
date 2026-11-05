# MetaGest operations

## Backups

The database lives in the Docker volume of the `db` service. A backup is a `pg_dump` in custom format.

```
powershell -File scripts\backup.ps1                      # manual dump to backups\
powershell -File scripts\backup.ps1 -CopyTo \\server\ti  # also copy it to another disk or share
```

- `scripts\start.ps1` takes a dump (`backups\ebt-pre-start-*.dump`) before it rebuilds or migrates, and stops if the dump fails. When the database container is stopped, it starts `db` alone first so the dump still happens.
- `stop.bat -Purge` dumps the database first (`ebt-before-purge-*`), aborts if the dump fails and asks for the word `DELETE` (`-Yes` skips only the question).
- At most 5 backups are kept, in one pool for every kind (manual, scheduled, pre-start, before-restore...), locally and in the destination. A new backup replaces the oldest one, and only after the new one passed verification, so a failed backup never costs an old one. The app's "Quantas cópias guardar" can lower the number (1 to 5) but not raise it. Safety copies (`pre-start`, `before-rebuild`, `before-restore`, `before-purge`) keep only the newest one of each kind, so they never push the manual and scheduled backups out. A failed run removes its partial dump; a dump without a `.sha256` file is never offered for restoring and is deleted after 10 minutes. "Limpar dados" (Configurações > Administração) needs the admin password and a backup younger than 1 hour.
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
- A backup can be deleted from the list in the app (trash icon, then type `EXCLUIR`): the request is recorded (`POST /api/admin/backups/delete`) and the agent removes the dump and its `.sha256` from this computer and from the destination, recomputes `status.json`, republishes `backups.json` and writes `delete-result.json`. It is refused while a backup or restore runs.
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

### Restore drill (does the backup really restore?)

`scripts\restore-drill.ps1` restores the newest verified dump (the backup destination first, then `backups\`) into a throwaway database `metagest_drill_<timestamp>` inside the `db` container, compares row counts of the key tables (`users`, `customers`, `products`, `quotes`, `sales_orders`, `production_orders`, `stock_documents`, `fiscal_documents`, whichever exist) and the migration history with the live database, then drops the throwaway database (always, even on failure). The live database is only read. Counts normally differ a little because the dump is older than the live data; the drill fails only when the restore fails, a key table is missing, the copy has no users or the dump has a migration the live database does not know.

The result goes to `backup-status\drill.json` (`ok`, `startedAt`, `finishedAt`, `dump`, `counts`, `migrations`, `errors`). The backup agent runs it by itself when the automatic plan is on: weekly, and again a day after a failed drill (rules in `Test-DrillDue` in `backup-agent.ps1`). Run it by hand any time: `powershell -File scripts\restore-drill.ps1`. `GET /health/ready` shows the last drill (`backup.drill`) and a failed one raises a warning and the alert mail.

## Updating the API

```
powershell -File scripts\update.ps1          # after the code is committed
powershell -File scripts\update.ps1 -Force   # also with uncommitted changes under src\ (image tagged <sha>-dirty)
```

It refuses to run with uncommitted changes in `src\`, takes a verified backup (`before-rebuild`) and stops if that fails, keeps the running image as `metagest-api:previous`, builds `metagest-api:<sha>` (also `latest`), recreates only the `api` container (the database container is never touched) and waits up to 90 seconds for `GET /health/ready`. If the new API does not become ready it puts `previous` back and exits with an error. `scripts\start.ps1` uses the same tags when it rebuilds.

A rollback restores the old code, not the old data: the new API migrates the schema when it starts, so a migration may already be applied when it fails. If the old code does not work with the migrated database, restore the dump taken at the start of the update (`backups\ebt-before-rebuild-*.dump`, see Restore). Manual rollback: `docker tag metagest-api:previous metagest-api:latest` and `docker compose -p metagest up -d --no-deps --force-recreate --pull never api`.

## Health and alerts

- `GET /health`: the container health check; 200 when the database answers.
- `GET /health/ready` (anonymous, no secrets): `{status, db, pendingMigrations, backup: {lastOkAt, ageHours, agentSeenAt, drill}, warnings}`. 503 when the database is unreachable or migrations are pending, 200 otherwise. `status` is `ok`, `degraded` (200 with warnings) or `unavailable`. Warnings: `backup_failed` (last run failed), `backup_stale` (plan on, no good backup for 26 hours), `agent_silent` (plan on, no agent heartbeat for 10 minutes), `drill_failed`. They never turn the answer into 503.
- Alert mail: set `EBT_ALERT_TO` (one or more addresses separated by `;`; needs the `EBT_SMTP_*` mail settings) and recreate the `api`. The API checks the conditions above every 5 minutes (`Alerts__IntervalSeconds`) and, when something is wrong (also database down or pending migrations), sends one mail and repeats it at most every 6 hours; the first check runs 2 minutes after the API starts. The time of the last alert is kept in memory, so restarting the API during a problem can send one more mail. Without the address or without working mail nothing is sent.

## Reverse proxy and web app (optional)

`docker compose --profile proxy up -d caddy` adds Caddy (`caddy\Caddyfile`): TLS on 443 (80 redirects), the Flutter web build as the site and `/api` and `/health` forwarded to the API. The default `docker compose up` does not start it.

1. In `.env`: `EBT_PUBLIC_HOST=metagest.empresa.local` (the name users type), `EBT_BEHIND_PROXY=true`, `EBT_ALLOWED_HOSTS=metagest.empresa.local`, `EBT_CORS_ORIGIN=https://metagest.empresa.local`. Recreate the `api` after changing them (CLAUDE.md, "Rebuilding the API container").
2. Build the web app for that name: `powershell -File scripts\build-web.ps1` (default `API_URL=https://<EBT_PUBLIC_HOST>`, or `-ApiUrl https://...`). It writes `clients\flutter\build\web`, which Caddy serves read-only. `API_URL` is compiled in: rebuild after changing the name.
3. `docker compose --profile proxy up -d caddy`. The name must resolve to this computer (DNS or hosts file) and ports 80/443 must be free (`EBT_HTTP_PORT`/`EBT_HTTPS_PORT`).
4. `EBT_CADDY_TLS=internal` (default) uses Caddy's own certificate authority. Browsers warn until its root certificate is installed on each client: copy it with `docker compose cp caddy:/data/caddy/pki/authorities/local/root.crt .` and import it as a trusted root. The authority lives in the `caddy_data` volume; losing the volume means a new root to install again. For a company or public certificate mount the files into the container and set `EBT_CADDY_TLS=/certs/site.crt /certs/site.key`.
5. The API port 8080 stays bound to `127.0.0.1`; only Caddy is exposed to the network.

## Android release signing

`scripts\release-android.ps1` builds the signed APK (`-Bundle` also the `.aab`, `-Bump` raises the build number in `pubspec.yaml`, `-ApiUrl https://...` sets the server) and copies it to `releases\` (gitignored) with its SHA-256. Signing reads `clients\flutter\android\key.properties`; without it the build uses the debug key and says so.

Create the key once (keep the password in a password manager):

```
keytool -genkeypair -v -keystore C:\metagest-keys\metagest-release.jks -alias metagest -keyalg RSA -keysize 2048 -validity 10000
```

Then `clients\flutter\android\key.properties` (never committed; `key.properties` and `*.jks` are gitignored):

```
storeFile=C:/metagest-keys/metagest-release.jks
storePassword=<senha do keystore>
keyAlias=metagest
keyPassword=<senha da chave>
```

**Back up the keystore and its passwords off this computer** (encrypted copy on another machine or in the cloud). An app signed with a lost key can never be updated: users would have to uninstall and reinstall.

## Resource limits

`db` and `api` have memory limits (`EBT_DB_MEM`, default 1g; `EBT_API_MEM`, default 512m) and the API connection string sets `Maximum Pool Size` from `EBT_DB_POOL` (default 40, below Postgres' 100 connections). Raise them in `.env` and recreate the container if logs show out-of-memory kills (`docker inspect -f '{{.State.OOMKilled}}' metagest-api-1`).

## Disaster recovery (the computer is gone)

Expected time: about 1 to 2 hours with the files at hand (Docker Desktop install 15 min, build 5 min, restore a few minutes for a database of this size).

What must exist outside this computer, or there is nothing to recover from:

- the newest dump in the backup destination, **on another physical disk or machine** (`backup.ps1` warns when the destination is on the system drive, which is where Docker keeps the database volume);
- an encrypted copy of `.env` (7-Zip with AES and a passphrase kept in a password manager or a sealed envelope). It holds `EBT_JWT_KEY`, the passwords and the SMTP settings; a new `.env` also works but signs everyone out;
- the Android keystore and `key.properties` values (see above), the fiscal A1 certificate and its password when the NF-e is on, and the Caddy root certificate if clients trust it;
- a second off-site copy of the dumps (cloud folder or a drive taken home), because a fire or theft takes the share too.

Checklist:

1. A Windows PC with Docker Desktop (WSL 2), Git and PowerShell. Clone the repository.
2. Put `.env` back in the repo root (decrypt the copy). Create `backup-status\` if missing.
3. `docker compose up -d db`, wait until healthy, copy the newest dump in and restore it into the empty `ebt` database:

   ```
   docker cp <dump> metagest-db-1:/tmp/restore.dump
   docker exec metagest-db-1 pg_restore -U ebt -d ebt --clean --if-exists --no-owner /tmp/restore.dump
   ```
4. Build and start the API (CLAUDE.md, "Rebuilding the API container"): `docker build --target api -t metagest-api:latest .` then `docker compose -p metagest up -d --no-deps --pull never api`. Migrations run on start.
5. `curl http://localhost:8080/health/ready` must say `ok` (or `degraded` while the backup agent is not back yet). Sign in and open a recent order.
6. `powershell -File scripts\install-backup-agent.ps1` (the plan itself is in the restored database; check the destination in Configurações), then `scripts\backup.ps1` once.
7. Proxy and web app (`scripts\build-web.ps1`, `docker compose --profile proxy up -d caddy`), DNS name, client certificates, then tell users to sign in again.
8. Run `scripts\restore-drill.ps1` and keep the new machine's first backup off-site.

Keeping the server alive: connect it to a UPS that shuts Windows down cleanly; set the BIOS to power on after a power loss; and let Windows sign in by itself after a restart (`netplwiz`, or Autologon from Sysinternals), because Docker Desktop and the backup agent task start at logon and the containers only come back when it runs. Auto-login means anyone at the keyboard has the session: keep the room locked and lock the screen with the Windows key + L (or the screen-saver lock, which does not stop Docker). Docker Desktop: Settings > General > "Start Docker Desktop when you sign in".

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

Set `EBT_BEHIND_PROXY=true` so the API trusts the forwarded client IP. Without it every user shares one login rate-limit bucket, and ten logins a minute lock everyone out. Set `EBT_ALLOWED_HOSTS` to the real host name (and `EBT_CORS_ORIGIN` to the public `https://` origin). The optional Caddy service above does the TLS part.

## Price history (suggestion of price for a tube)

The price suggestion (Comercial > orcamento) learns from what EBT charged before. Two legacy sources feed `price_history`, plus the live
MetaGest order lines (test-source orders are ignored):

1. the master sales workbook `PEDIDO DE VENDAS Anos 24 & 26 - EBT e BST.xlsx` (read through Excel COM, read-only);
2. the folder of "Pedido Interno de Venda" workbooks (one xlsx per order; read as zip, no Excel). Only this source carries the material
   specification, which moves the price a lot.

Export both into one CSV, then import it:

```
powershell -File scripts\export-price-history.ps1 [-Workbook <xlsx>] [-PedidosFolder <folder>] [-Out price-history.csv]
```

The script prints the counts per source and writes `price-history.csv` (`date;customer;diameter;thickness;length;unit;price;quantity;spec`, UTF-8).
The file holds real customer prices: `price-history*.csv` is git-ignored, never commit it. Import it in the app (Comercial > Simulador de preço > "Importar histórico (CSV)", needs the
`price-edit` role: Admin, SalesManager) or with `POST /api/sales/price-history/import` (multipart field `file`; UTF-8 or Windows-1252, `;` `,` or tab).
The result says read / imported / updated / duplicates / skipped.

- A sale is identified by the first 6 letters of the customer name, diameter, thickness, length, unit and price (2 decimals). Importing again is
  safe: a known sale only gets the later date and, if it lacked one, the specification (upsert); nothing is duplicated.
- `spec` is classified into EN10305 (E420, E355, 10305, CR2), NBK, BK, NBR (5599, NBR), SAE (SAE, 1010, 1008, 1020) or other (`PriceSpec.Classify`).
- It is reference data, like the price list: the data reset never deletes it, and a restore brings it back with the rest of the database.
## E-mail (quote sending)

The API sends the quote PDF to the customer from one company mailbox (`Ebt.Core/Mail`, `POST /api/sales/quotes/{id}/email`). Set it in `.env`, then recreate the `api` container (see CLAUDE.md, "Rebuilding the API container"):

```
EBT_SMTP_HOST=smtp.office365.com
EBT_SMTP_PORT=587
EBT_SMTP_USER=orcamentos@empresa.com.br
EBT_SMTP_PASSWORD=<senha do e-mail ou senha de app>
EBT_SMTP_FROM=orcamentos@empresa.com.br
```

- Without `EBT_SMTP_HOST` and `EBT_SMTP_FROM` sending is off and the quote screen shows only "Registrar envio". `GET /api/system/mail` tells the app which.
- Encryption follows the port by default (`EBT_SMTP_SECURITY=Auto`): 465 is SSL from the first byte, any other port uses STARTTLS when the server offers it. Force it with `Ssl`, `StartTls` or `None` (a relay inside the company network).
- Locaweb mailbox (Painel de e-mail > Programa de e-mail): `EBT_SMTP_HOST=email-ssl.com.br`, `EBT_SMTP_PORT=465`, user = the full mailbox address, `EBT_SMTP_FROM` = the same mailbox.
- Microsoft 365 and Gmail usually need an app password (or SMTP AUTH enabled for the mailbox) instead of the normal password.
- The password lives only in `.env`/environment, never in the database or the app. Each send is written to the quote history (`sent` or `emailed`, with the addresses).
