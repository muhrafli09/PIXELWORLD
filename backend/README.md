# PixelFarm Backend (Go + PostgreSQL)

Starter backend untuk migrasi dari mode offline (`user://player.json`, `user://worlds/*.json`) ke server-authoritative.

## Prasyarat

- Go 1.23+
- PostgreSQL 15+

## Environment

Set env var berikut:

- `DATABASE_URL` (contoh: `postgres://postgres:postgres@localhost:5432/pixelfarm?sslmode=disable`)
- `PORT` (opsional, default `8080`)

## Menjalankan migrasi schema

Jalankan SQL di file:

- `migrations/001_init.sql`

Contoh:

```bash
psql "postgres://postgres:postgres@localhost:5432/pixelfarm?sslmode=disable" -f migrations/001_init.sql
```

## Menjalankan server

```bash
go run ./cmd/server
```

Endpoint awal:

- `GET /healthz`
- `POST /v1/auth/login`
- `GET /v1/players/{player_id}`
- `GET /v1/worlds/{world_name}`
- `PUT /v1/worlds/{world_name}`
- `POST /v1/worlds/{world_name}/actions`

Contoh action body:

```json
{
  "player_id": "local_player",
  "action": "break",
  "target": { "x": 50, "y": 40 }
}
```

Action yang didukung:

- `break`
- `place_dirt`
- `plant_seed`
- `place_small_lock`
- `place_big_lock`
- `trade`

## Import save lokal Godot ke PostgreSQL

Tool import:

```bash
go run ./cmd/import_local --data-dir "C:\path\to\godot\user_data\PixelFarm Offline"
```

Argumen:

- `--data-dir` direktori yang berisi `player.json` dan folder `worlds/`

Tool ini:

- Upsert player profile + inventory/hotbar
- Upsert world state (`worlds` + `world_tiles`)
