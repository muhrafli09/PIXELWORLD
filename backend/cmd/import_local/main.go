package main

import (
	"context"
	"encoding/json"
	"flag"
	"fmt"
	"log"
	"os"
	"path/filepath"
	"strings"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"
)

func main() {
	dataDir := flag.String("data-dir", "", "Directory containing player.json and worlds/")
	flag.Parse()
	if *dataDir == "" {
		log.Fatal("--data-dir is required")
	}
	databaseURL := os.Getenv("DATABASE_URL")
	if databaseURL == "" {
		log.Fatal("DATABASE_URL is required")
	}

	ctx, cancel := context.WithTimeout(context.Background(), 25*time.Second)
	defer cancel()
	pool, err := pgxpool.New(ctx, databaseURL)
	if err != nil {
		log.Fatalf("db pool: %v", err)
	}
	defer pool.Close()

	if err := importPlayer(ctx, pool, *dataDir); err != nil {
		log.Fatalf("import player: %v", err)
	}
	if err := importWorlds(ctx, pool, *dataDir); err != nil {
		log.Fatalf("import worlds: %v", err)
	}
	log.Println("import completed")
}

func importPlayer(ctx context.Context, pool *pgxpool.Pool, dataDir string) error {
	path := filepath.Join(dataDir, "player.json")
	raw, err := os.ReadFile(path)
	if err != nil {
		return fmt.Errorf("read player.json: %w", err)
	}
	var p map[string]any
	if err := json.Unmarshal(raw, &p); err != nil {
		return fmt.Errorf("parse player.json: %w", err)
	}

	playerID := asString(p["player_id"], "local_player")
	playerName := asString(p["player_name"], "Player")
	characterID := asString(p["current_character_id"], "farmer")
	currentWorld := strings.ToUpper(asString(p["current_world_name"], "START"))
	hotbar := asStringSlice(p["hotbar"], 5)
	inventory := extractInventory(p["inventory"])

	tx, err := pool.Begin(ctx)
	if err != nil {
		return err
	}
	defer tx.Rollback(ctx)

	_, err = tx.Exec(ctx, `
		INSERT INTO players (id, name, character_id, current_world_name, updated_at)
		VALUES ($1, $2, $3, $4, NOW())
		ON CONFLICT (id)
		DO UPDATE SET
			name = EXCLUDED.name,
			character_id = EXCLUDED.character_id,
			current_world_name = EXCLUDED.current_world_name,
			updated_at = NOW()
	`, playerID, playerName, characterID, currentWorld)
	if err != nil {
		return err
	}

	_, err = tx.Exec(ctx, `DELETE FROM player_inventory WHERE player_id = $1`, playerID)
	if err != nil {
		return err
	}
	for itemID, amount := range inventory {
		_, err = tx.Exec(ctx, `
			INSERT INTO player_inventory (player_id, item_id, amount) VALUES ($1, $2, $3)
		`, playerID, itemID, amount)
		if err != nil {
			return err
		}
	}

	_, err = tx.Exec(ctx, `DELETE FROM player_hotbar WHERE player_id = $1`, playerID)
	if err != nil {
		return err
	}
	for i := 0; i < 5; i++ {
		item := ""
		if i < len(hotbar) {
			item = hotbar[i]
		}
		_, err = tx.Exec(ctx, `
			INSERT INTO player_hotbar (player_id, slot_index, item_id) VALUES ($1, $2, $3)
		`, playerID, i, item)
		if err != nil {
			return err
		}
	}
	return tx.Commit(ctx)
}

func importWorlds(ctx context.Context, pool *pgxpool.Pool, dataDir string) error {
	worldDir := filepath.Join(dataDir, "worlds")
	entries, err := os.ReadDir(worldDir)
	if err != nil {
		return fmt.Errorf("read worlds dir: %w", err)
	}
	for _, entry := range entries {
		if entry.IsDir() || !strings.HasSuffix(strings.ToLower(entry.Name()), ".json") {
			continue
		}
		fullPath := filepath.Join(worldDir, entry.Name())
		raw, err := os.ReadFile(fullPath)
		if err != nil {
			return err
		}
		var world map[string]any
		if err := json.Unmarshal(raw, &world); err != nil {
			return err
		}
		if err := upsertWorld(ctx, pool, world); err != nil {
			return fmt.Errorf("upsert %s: %w", entry.Name(), err)
		}
	}
	return nil
}

func upsertWorld(ctx context.Context, pool *pgxpool.Pool, world map[string]any) error {
	name := strings.ToUpper(asString(world["world_name"], "START"))
	width := asInt(world["width"], 100)
	height := asInt(world["height"], 60)
	ownerID := asString(world["owner_id"], "")
	worldLocked := asBool(world["world_locked"], false)
	mainDoor := asMap(world["main_door_pos"])
	mainDoorX := asInt(mainDoor["x"], 50)
	mainDoorY := asInt(mainDoor["y"], 37)
	accessList := asAnySlice(world["access_list"])
	areaLocks := asAnySlice(world["area_locks"])
	cells := asMap(world["cells"])

	accessRaw, _ := json.Marshal(accessList)
	locksRaw, _ := json.Marshal(areaLocks)

	tx, err := pool.Begin(ctx)
	if err != nil {
		return err
	}
	defer tx.Rollback(ctx)

	_, err = tx.Exec(ctx, `
		INSERT INTO worlds (name, width, height, owner_id, world_locked, main_door_x, main_door_y, access_list, area_locks, updated_at)
		VALUES ($1, $2, $3, $4, $5, $6, $7, $8::jsonb, $9::jsonb, NOW())
		ON CONFLICT (name)
		DO UPDATE SET
			width = EXCLUDED.width,
			height = EXCLUDED.height,
			owner_id = EXCLUDED.owner_id,
			world_locked = EXCLUDED.world_locked,
			main_door_x = EXCLUDED.main_door_x,
			main_door_y = EXCLUDED.main_door_y,
			access_list = EXCLUDED.access_list,
			area_locks = EXCLUDED.area_locks,
			version = worlds.version + 1,
			updated_at = NOW()
	`, name, width, height, ownerID, worldLocked, mainDoorX, mainDoorY, string(accessRaw), string(locksRaw))
	if err != nil {
		return err
	}

	_, err = tx.Exec(ctx, `DELETE FROM world_tiles WHERE world_name = $1`, name)
	if err != nil {
		return err
	}
	for key, cellRaw := range cells {
		cell := asMap(cellRaw)
		block := asString(cell["block"], "")
		if block == "" || block == "air" {
			continue
		}
		parts := strings.Split(key, ",")
		if len(parts) != 2 {
			continue
		}
		x := atoiSafe(parts[0], 0)
		y := atoiSafe(parts[1], 0)
		plantedAt := asInt64(cell["planted_at"], 0)
		_, err = tx.Exec(ctx, `
			INSERT INTO world_tiles (world_name, x, y, block_id, planted_at)
			VALUES ($1, $2, $3, $4, $5)
		`, name, x, y, block, plantedAt)
		if err != nil {
			return err
		}
	}
	return tx.Commit(ctx)
}

func asMap(v any) map[string]any {
	if m, ok := v.(map[string]any); ok {
		return m
	}
	return map[string]any{}
}

func asAnySlice(v any) []any {
	if s, ok := v.([]any); ok {
		return s
	}
	return []any{}
}

func asString(v any, fallback string) string {
	if s, ok := v.(string); ok {
		return s
	}
	return fallback
}

func asStringSlice(v any, size int) []string {
	src, ok := v.([]any)
	if !ok {
		return []string{}
	}
	out := make([]string, 0, size)
	for _, item := range src {
		out = append(out, asString(item, ""))
	}
	return out
}

func extractInventory(v any) map[string]int {
	out := map[string]int{}
	root := asMap(v)
	items := asMap(root["items"])
	for itemID, raw := range items {
		out[itemID] = asInt(raw, 0)
	}
	return out
}

func asInt(v any, fallback int) int {
	switch t := v.(type) {
	case float64:
		return int(t)
	case int:
		return t
	case int64:
		return int(t)
	default:
		return fallback
	}
}

func asInt64(v any, fallback int64) int64 {
	switch t := v.(type) {
	case float64:
		return int64(t)
	case int64:
		return t
	case int:
		return int64(t)
	default:
		return fallback
	}
}

func asBool(v any, fallback bool) bool {
	if b, ok := v.(bool); ok {
		return b
	}
	return fallback
}

func atoiSafe(s string, fallback int) int {
	var n int
	_, err := fmt.Sscanf(strings.TrimSpace(s), "%d", &n)
	if err != nil {
		return fallback
	}
	return n
}
