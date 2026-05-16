# PixelFarm Offline (Godot)

Starter project Godot 4 untuk fokus gameplay offline dulu, dengan arsitektur yang mudah diangkat ke multiplayer server-authoritative nanti.

## Fitur awal

- Welcome menu saat game dibuka (Play, Settings, Quit).
- Player move (arrow keys + WASD).
- Break block (`Z`).
- Switch karakter (`Q`/`E`) dengan passive berbeda.
- Hotbar slot `1-5` + item aktif.
- Use item aktif (`X` atau `C`) untuk place/plant.
- World fixed `100x60` (6000 block) dengan batas map.
- Baris bawah berisi `lava` dan `bedrock` yang tidak bisa dihancurkan.
- Multi-world offline (`START/FARM/TRADE`) dengan generate/load per world.
- Spawn selalu di `Main Door` tiap kali masuk world.
- Lock permission: `Small Lock` (area) dan `Big Lock` (seluruh world).
- Drop item muncul di world setelah break.
- Auto pickup saat player mendekat ke drop.
- Trade station offline (`T`) untuk jual `fruit` jadi `gem`, dan beli `seed` pakai `gem`.
- Action cooldown dan interaction range check dasar.
- Inventory lokal sederhana.
- Save (`F5`) / Load (`F9`) ke `user://player.json` dan folder `user://worlds/`.

## Struktur

- `scenes/MainMenu.tscn`: tampilan awal game.
- `scenes/Main.tscn`: scene utama.
- `scripts/main_menu.gd`: logic tombol menu + settings.
- `scripts/main.gd`: input + render grid debug.
- `scripts/game_logic.gd`: command gameplay offline-first.
- `scripts/world_data.gd`: state world tile/cell.
- `scripts/inventory.gd`: inventory data object.
- `scripts/save_system.gd`: persistensi lokal.

## Backend Online Starter

- `backend/migrations/001_init.sql`: schema PostgreSQL (`players`, `worlds`, `world_tiles`, inventory, hotbar).
- `backend/cmd/server`: API Go dasar (`/healthz`, `/v1/auth/login`, `/v1/players/{id}`, `/v1/worlds/{name}`, `/v1/worlds/{name}/actions`).
- `backend/cmd/import_local`: tool import `player.json` + `worlds/*.json` ke PostgreSQL.
- `backend/README.md`: langkah setup env + run backend.

## Kenapa ini bagus untuk next multiplayer

Semua gameplay action dipusatkan di `GameLogic` (command style: move, break, place, plant), jadi nanti command yang sama bisa dikirim ke server tanpa rombak total UI/render layer.
