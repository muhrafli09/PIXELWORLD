CREATE TABLE IF NOT EXISTS players (
    id TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    character_id TEXT NOT NULL DEFAULT 'farmer',
    current_world_name TEXT NOT NULL DEFAULT 'START',
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS player_inventory (
    player_id TEXT NOT NULL REFERENCES players(id) ON DELETE CASCADE,
    item_id TEXT NOT NULL,
    amount INTEGER NOT NULL CHECK (amount >= 0),
    PRIMARY KEY (player_id, item_id)
);

CREATE TABLE IF NOT EXISTS player_hotbar (
    player_id TEXT NOT NULL REFERENCES players(id) ON DELETE CASCADE,
    slot_index INTEGER NOT NULL CHECK (slot_index >= 0 AND slot_index <= 4),
    item_id TEXT NOT NULL,
    PRIMARY KEY (player_id, slot_index)
);

CREATE TABLE IF NOT EXISTS worlds (
    name TEXT PRIMARY KEY,
    width INTEGER NOT NULL,
    height INTEGER NOT NULL,
    owner_id TEXT NOT NULL DEFAULT '',
    world_locked BOOLEAN NOT NULL DEFAULT FALSE,
    main_door_x INTEGER NOT NULL,
    main_door_y INTEGER NOT NULL,
    access_list JSONB NOT NULL DEFAULT '[]'::jsonb,
    area_locks JSONB NOT NULL DEFAULT '[]'::jsonb,
    version BIGINT NOT NULL DEFAULT 1,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS world_tiles (
    world_name TEXT NOT NULL REFERENCES worlds(name) ON DELETE CASCADE,
    x INTEGER NOT NULL,
    y INTEGER NOT NULL,
    block_id TEXT NOT NULL,
    planted_at BIGINT NOT NULL DEFAULT 0,
    PRIMARY KEY (world_name, x, y)
);

CREATE INDEX IF NOT EXISTS idx_world_tiles_world ON world_tiles(world_name);
