package app

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"math"
	"net/http"
	"strings"
	"time"

	"github.com/jackc/pgx/v5"
)

const (
	blockAir      = "air"
	blockDirt     = "dirt"
	blockPlant0   = "plant_0"
	blockPlant1   = "plant_1"
	blockPlant2   = "plant_2"
	blockLava     = "lava"
	blockBedrock  = "bedrock"
	blockMainDoor = "main_door"
)

type LoginRequest struct {
	PlayerID string `json:"player_id"`
	Name     string `json:"name"`
}

type ActionRequest struct {
	PlayerID string         `json:"player_id"`
	Action   string         `json:"action"`
	Target   map[string]int `json:"target"`
}

func (a *App) handleLogin(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		writeJSON(w, http.StatusMethodNotAllowed, map[string]string{"error": "method not allowed"})
		return
	}
	var req LoginRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid json body"})
		return
	}
	req.PlayerID = strings.TrimSpace(req.PlayerID)
	req.Name = strings.TrimSpace(req.Name)
	if req.PlayerID == "" {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "player_id required"})
		return
	}
	if req.Name == "" {
		req.Name = "Player"
	}
	ctx, cancel := context.WithTimeout(r.Context(), 5*time.Second)
	defer cancel()
	if err := a.upsertPlayerDefaults(ctx, req.PlayerID, req.Name); err != nil {
		writeJSON(w, http.StatusInternalServerError, map[string]string{"error": err.Error()})
		return
	}
	writeJSON(w, http.StatusOK, map[string]string{
		"status":    "ok",
		"player_id": req.PlayerID,
		"name":      req.Name,
		"token":     "dev-" + req.PlayerID,
	})
}

func (a *App) handleWorldActions(w http.ResponseWriter, r *http.Request, worldName string) {
	if r.Method != http.MethodPost {
		writeJSON(w, http.StatusMethodNotAllowed, map[string]string{"error": "method not allowed"})
		return
	}
	var req ActionRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid json body"})
		return
	}
	req.PlayerID = strings.TrimSpace(req.PlayerID)
	req.Action = strings.TrimSpace(req.Action)
	if req.PlayerID == "" || req.Action == "" {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "player_id and action are required"})
		return
	}

	ctx, cancel := context.WithTimeout(r.Context(), 8*time.Second)
	defer cancel()
	result, err := a.applyWorldAction(ctx, worldName, req)
	if err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": err.Error()})
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{
		"status": "ok",
		"result": result,
	})
}

func (a *App) upsertPlayerDefaults(ctx context.Context, playerID, name string) error {
	tx, err := a.db.Begin(ctx)
	if err != nil {
		return err
	}
	defer tx.Rollback(ctx)

	_, err = tx.Exec(ctx, `
		INSERT INTO players (id, name, character_id, current_world_name, updated_at)
		VALUES ($1, $2, 'farmer', 'START', NOW())
		ON CONFLICT (id)
		DO UPDATE SET name = EXCLUDED.name, updated_at = NOW()
	`, playerID, name)
	if err != nil {
		return err
	}

	var inventoryCount int
	_ = tx.QueryRow(ctx, `SELECT COUNT(1) FROM player_inventory WHERE player_id = $1`, playerID).Scan(&inventoryCount)
	if inventoryCount == 0 {
		defaultItems := map[string]int{
			"dirt":       64,
			"seed":       20,
			"small_lock": 2,
			"big_lock":   1,
		}
		for itemID, amount := range defaultItems {
			_, err = tx.Exec(ctx, `
				INSERT INTO player_inventory (player_id, item_id, amount)
				VALUES ($1, $2, $3)
			`, playerID, itemID, amount)
			if err != nil {
				return err
			}
		}
		hotbar := []string{"dirt", "seed", "small_lock", "big_lock", ""}
		for i, itemID := range hotbar {
			_, err = tx.Exec(ctx, `
				INSERT INTO player_hotbar (player_id, slot_index, item_id)
				VALUES ($1, $2, $3)
			`, playerID, i, itemID)
			if err != nil {
				return err
			}
		}
	}

	return tx.Commit(ctx)
}

func (a *App) applyWorldAction(ctx context.Context, worldName string, req ActionRequest) (map[string]any, error) {
	tx, err := a.db.Begin(ctx)
	if err != nil {
		return nil, err
	}
	defer tx.Rollback(ctx)

	if _, err := tx.Exec(ctx, `SELECT id FROM players WHERE id = $1 FOR UPDATE`, req.PlayerID); err != nil {
		return nil, errors.New("player not found")
	}

	var (
		width       int
		height      int
		ownerID     string
		worldLocked bool
		accessRaw   []byte
		locksRaw    []byte
	)
	err = tx.QueryRow(ctx, `
		SELECT width, height, owner_id, world_locked, access_list::text, area_locks::text
		FROM worlds
		WHERE name = $1
		FOR UPDATE
	`, worldName).Scan(&width, &height, &ownerID, &worldLocked, &accessRaw, &locksRaw)
	if err != nil {
		return nil, errors.New("world not found")
	}

	targetX := req.Target["x"]
	targetY := req.Target["y"]
	if req.Action != "trade" {
		if targetX < 0 || targetX >= width || targetY < 0 || targetY >= height {
			return nil, errors.New("target out of bounds")
		}
	}

	accessList := []string{}
	_ = json.Unmarshal(accessRaw, &accessList)
	areaLocks := []map[string]any{}
	_ = json.Unmarshal(locksRaw, &areaLocks)

	switch req.Action {
	case "break":
		if !canModify(req.PlayerID, ownerID, worldLocked, accessList, areaLocks, targetX, targetY) {
			return nil, errors.New("permission denied")
		}
		block, plantedAt, err := getBlockTx(ctx, tx, worldName, targetX, targetY)
		if err != nil {
			return nil, err
		}
		if block == blockAir {
			return nil, errors.New("no block")
		}
		if block == blockLava || block == blockBedrock || block == blockMainDoor {
			return nil, errors.New("block cannot be broken")
		}
		if err := deleteBlockTx(ctx, tx, worldName, targetX, targetY); err != nil {
			return nil, err
		}
		drops := map[string]int{}
		switch block {
		case blockDirt:
			drops["dirt"] = 1
		case blockPlant0, blockPlant1:
			drops["seed"] = 1
		case blockPlant2:
			drops["fruit"] = 1
			drops["seed"] = 2
		default:
			_ = plantedAt
		}
		for itemID, amount := range drops {
			if err := addInventoryTx(ctx, tx, req.PlayerID, itemID, amount); err != nil {
				return nil, err
			}
		}
		if err := tx.Commit(ctx); err != nil {
			return nil, err
		}
		return map[string]any{"action": req.Action, "drops": drops}, nil

	case "place_dirt":
		if !canModify(req.PlayerID, ownerID, worldLocked, accessList, areaLocks, targetX, targetY) {
			return nil, errors.New("permission denied")
		}
		block, _, err := getBlockTx(ctx, tx, worldName, targetX, targetY)
		if err != nil {
			return nil, err
		}
		if block != blockAir {
			return nil, errors.New("target not empty")
		}
		if err := consumeInventoryTx(ctx, tx, req.PlayerID, "dirt", 1); err != nil {
			return nil, err
		}
		if err := setBlockTx(ctx, tx, worldName, targetX, targetY, blockDirt, 0); err != nil {
			return nil, err
		}
		if err := tx.Commit(ctx); err != nil {
			return nil, err
		}
		return map[string]any{"action": req.Action}, nil

	case "plant_seed":
		if !canModify(req.PlayerID, ownerID, worldLocked, accessList, areaLocks, targetX, targetY) {
			return nil, errors.New("permission denied")
		}
		block, _, err := getBlockTx(ctx, tx, worldName, targetX, targetY)
		if err != nil {
			return nil, err
		}
		if block != blockAir {
			return nil, errors.New("target not empty")
		}
		belowBlock, _, err := getBlockTx(ctx, tx, worldName, targetX, targetY+1)
		if err != nil {
			return nil, err
		}
		if belowBlock != blockDirt {
			return nil, errors.New("plant requires dirt below")
		}
		if err := consumeInventoryTx(ctx, tx, req.PlayerID, "seed", 1); err != nil {
			return nil, err
		}
		if err := setBlockTx(ctx, tx, worldName, targetX, targetY, blockPlant0, time.Now().Unix()); err != nil {
			return nil, err
		}
		if err := tx.Commit(ctx); err != nil {
			return nil, err
		}
		return map[string]any{"action": req.Action}, nil

	case "place_small_lock":
		if !canModifyForLock(req.PlayerID, ownerID) {
			return nil, errors.New("only owner can place lock")
		}
		block, _, err := getBlockTx(ctx, tx, worldName, targetX, targetY)
		if err != nil {
			return nil, err
		}
		if block != blockAir {
			return nil, errors.New("target not empty")
		}
		if err := consumeInventoryTx(ctx, tx, req.PlayerID, "small_lock", 1); err != nil {
			return nil, err
		}
		updatedOwner := ownerID
		if updatedOwner == "" {
			updatedOwner = req.PlayerID
		}
		accessList = ensureAccess(accessList, updatedOwner)
		areaLocks = append(areaLocks, map[string]any{
			"owner_id": updatedOwner,
			"radius":   10,
			"center": map[string]int{
				"x": targetX,
				"y": targetY,
			},
		})
		if err := updateWorldLockDataTx(ctx, tx, worldName, updatedOwner, worldLocked, accessList, areaLocks); err != nil {
			return nil, err
		}
		if err := tx.Commit(ctx); err != nil {
			return nil, err
		}
		return map[string]any{"action": req.Action, "owner_id": updatedOwner}, nil

	case "place_big_lock":
		if !canModifyForLock(req.PlayerID, ownerID) {
			return nil, errors.New("only owner can place lock")
		}
		block, _, err := getBlockTx(ctx, tx, worldName, targetX, targetY)
		if err != nil {
			return nil, err
		}
		if block != blockAir {
			return nil, errors.New("target not empty")
		}
		if err := consumeInventoryTx(ctx, tx, req.PlayerID, "big_lock", 1); err != nil {
			return nil, err
		}
		updatedOwner := ownerID
		if updatedOwner == "" {
			updatedOwner = req.PlayerID
		}
		accessList = ensureAccess(accessList, updatedOwner)
		if err := updateWorldLockDataTx(ctx, tx, worldName, updatedOwner, true, accessList, areaLocks); err != nil {
			return nil, err
		}
		if err := tx.Commit(ctx); err != nil {
			return nil, err
		}
		return map[string]any{"action": req.Action, "owner_id": updatedOwner, "world_locked": true}, nil

	case "trade":
		fruitCount, err := getInventoryAmountTx(ctx, tx, req.PlayerID, "fruit")
		if err != nil {
			return nil, err
		}
		if fruitCount > 0 {
			if err := consumeInventoryTx(ctx, tx, req.PlayerID, "fruit", fruitCount); err != nil {
				return nil, err
			}
			gain := fruitCount * 5
			if err := addInventoryTx(ctx, tx, req.PlayerID, "gem", gain); err != nil {
				return nil, err
			}
			if err := tx.Commit(ctx); err != nil {
				return nil, err
			}
			return map[string]any{"action": req.Action, "sold_fruit": fruitCount, "gained_gem": gain}, nil
		}
		gemCount, err := getInventoryAmountTx(ctx, tx, req.PlayerID, "gem")
		if err != nil {
			return nil, err
		}
		if gemCount >= 2 {
			if err := consumeInventoryTx(ctx, tx, req.PlayerID, "gem", 2); err != nil {
				return nil, err
			}
			if err := addInventoryTx(ctx, tx, req.PlayerID, "seed", 1); err != nil {
				return nil, err
			}
			if err := tx.Commit(ctx); err != nil {
				return nil, err
			}
			return map[string]any{"action": req.Action, "spent_gem": 2, "bought_seed": 1}, nil
		}
		return nil, errors.New("trade failed: not enough fruit or gem")

	default:
		return nil, errors.New("unknown action")
	}
}

func getBlockTx(ctx context.Context, tx pgx.Tx, world string, x, y int) (string, int64, error) {
	var block string
	var plantedAt int64
	err := tx.QueryRow(ctx, `
		SELECT block_id, planted_at
		FROM world_tiles
		WHERE world_name = $1 AND x = $2 AND y = $3
	`, world, x, y).Scan(&block, &plantedAt)
	if err != nil {
		return blockAir, 0, nil
	}
	return block, plantedAt, nil
}

func setBlockTx(ctx context.Context, tx pgx.Tx, world string, x, y int, block string, plantedAt int64) error {
	_, err := tx.Exec(ctx, `
		INSERT INTO world_tiles (world_name, x, y, block_id, planted_at)
		VALUES ($1, $2, $3, $4, $5)
		ON CONFLICT (world_name, x, y)
		DO UPDATE SET block_id = EXCLUDED.block_id, planted_at = EXCLUDED.planted_at
	`, world, x, y, block, plantedAt)
	return err
}

func deleteBlockTx(ctx context.Context, tx pgx.Tx, world string, x, y int) error {
	_, err := tx.Exec(ctx, `
		DELETE FROM world_tiles WHERE world_name = $1 AND x = $2 AND y = $3
	`, world, x, y)
	return err
}

func getInventoryAmountTx(ctx context.Context, tx pgx.Tx, playerID, itemID string) (int, error) {
	var amount int
	err := tx.QueryRow(ctx, `
		SELECT amount FROM player_inventory
		WHERE player_id = $1 AND item_id = $2
	`, playerID, itemID).Scan(&amount)
	if err != nil {
		return 0, nil
	}
	return amount, nil
}

func addInventoryTx(ctx context.Context, tx pgx.Tx, playerID, itemID string, amount int) error {
	if amount <= 0 {
		return nil
	}
	_, err := tx.Exec(ctx, `
		INSERT INTO player_inventory (player_id, item_id, amount)
		VALUES ($1, $2, $3)
		ON CONFLICT (player_id, item_id)
		DO UPDATE SET amount = player_inventory.amount + EXCLUDED.amount
	`, playerID, itemID, amount)
	return err
}

func consumeInventoryTx(ctx context.Context, tx pgx.Tx, playerID, itemID string, amount int) error {
	current, err := getInventoryAmountTx(ctx, tx, playerID, itemID)
	if err != nil {
		return err
	}
	if current < amount {
		return fmt.Errorf("not enough %s", itemID)
	}
	next := current - amount
	if next == 0 {
		_, err = tx.Exec(ctx, `
			DELETE FROM player_inventory
			WHERE player_id = $1 AND item_id = $2
		`, playerID, itemID)
		return err
	}
	_, err = tx.Exec(ctx, `
		UPDATE player_inventory
		SET amount = $3
		WHERE player_id = $1 AND item_id = $2
	`, playerID, itemID, next)
	return err
}

func updateWorldLockDataTx(ctx context.Context, tx pgx.Tx, worldName, ownerID string, worldLocked bool, access []string, areaLocks []map[string]any) error {
	accessRaw, _ := json.Marshal(access)
	locksRaw, _ := json.Marshal(areaLocks)
	_, err := tx.Exec(ctx, `
		UPDATE worlds
		SET owner_id = $2,
			world_locked = $3,
			access_list = $4::jsonb,
			area_locks = $5::jsonb,
			updated_at = NOW(),
			version = version + 1
		WHERE name = $1
	`, worldName, ownerID, worldLocked, string(accessRaw), string(locksRaw))
	return err
}

func canModifyForLock(playerID, ownerID string) bool {
	return ownerID == "" || ownerID == playerID
}

func canModify(playerID, ownerID string, worldLocked bool, access []string, areaLocks []map[string]any, x, y int) bool {
	if ownerID == "" {
		return true
	}
	if playerID == ownerID || contains(access, playerID) {
		return true
	}
	if worldLocked {
		return false
	}
	return !isInAnyAreaLock(areaLocks, x, y)
}

func isInAnyAreaLock(areaLocks []map[string]any, x, y int) bool {
	for _, lock := range areaLocks {
		center, ok := lock["center"].(map[string]any)
		if !ok {
			continue
		}
		cx := asInt(center["x"], 0)
		cy := asInt(center["y"], 0)
		radius := asInt(lock["radius"], 10)
		if int(math.Abs(float64(x-cx))) <= radius && int(math.Abs(float64(y-cy))) <= radius {
			return true
		}
	}
	return false
}

func contains(values []string, candidate string) bool {
	for _, v := range values {
		if v == candidate {
			return true
		}
	}
	return false
}

func ensureAccess(values []string, playerID string) []string {
	if contains(values, playerID) {
		return values
	}
	return append(values, playerID)
}

func asInt(v any, fallback int) int {
	switch t := v.(type) {
	case float64:
		return int(t)
	case int:
		return t
	case int32:
		return int(t)
	case int64:
		return int(t)
	default:
		return fallback
	}
}
