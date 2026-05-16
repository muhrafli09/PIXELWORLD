package app

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
	"os"
	"strconv"
	"strings"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"
)

type App struct {
	db *pgxpool.Pool
}

type PlayerResponse struct {
	ID               string         `json:"id"`
	Name             string         `json:"name"`
	CharacterID      string         `json:"character_id"`
	CurrentWorldName string         `json:"current_world_name"`
	Inventory        map[string]int `json:"inventory"`
	Hotbar           []string       `json:"hotbar"`
}

type WorldPayload struct {
	Name        string                 `json:"name"`
	Width       int                    `json:"width"`
	Height      int                    `json:"height"`
	OwnerID     string                 `json:"owner_id"`
	WorldLocked bool                   `json:"world_locked"`
	MainDoorPos map[string]int         `json:"main_door_pos"`
	AccessList  []string               `json:"access_list"`
	AreaLocks   []map[string]any       `json:"area_locks"`
	Cells       map[string]WorldCellIn `json:"cells"`
}

type WorldCellIn struct {
	Block     string `json:"block"`
	PlantedAt int64  `json:"planted_at"`
}

func New(ctx context.Context) (*App, error) {
	databaseURL := os.Getenv("DATABASE_URL")
	if databaseURL == "" {
		return nil, errors.New("DATABASE_URL is required")
	}
	pool, err := pgxpool.New(ctx, databaseURL)
	if err != nil {
		return nil, fmt.Errorf("create pool: %w", err)
	}
	if err := pool.Ping(ctx); err != nil {
		return nil, fmt.Errorf("ping db: %w", err)
	}
	return &App{db: pool}, nil
}

func (a *App) Close() {
	a.db.Close()
}

func (a *App) Handler() http.Handler {
	mux := http.NewServeMux()
	mux.HandleFunc("/healthz", a.handleHealth)
	mux.HandleFunc("/v1/auth/login", a.handleLogin)
	mux.HandleFunc("/v1/players/", a.handlePlayers)
	mux.HandleFunc("/v1/worlds/", a.handleWorlds)
	return withJSON(mux)
}

func (a *App) handleHealth(w http.ResponseWriter, _ *http.Request) {
	writeJSON(w, http.StatusOK, map[string]string{"status": "ok"})
}

func (a *App) handlePlayers(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		writeJSON(w, http.StatusMethodNotAllowed, map[string]string{"error": "method not allowed"})
		return
	}
	playerID := strings.TrimPrefix(r.URL.Path, "/v1/players/")
	if playerID == "" {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "player_id required"})
		return
	}
	ctx, cancel := context.WithTimeout(r.Context(), 5*time.Second)
	defer cancel()

	player, err := a.getPlayer(ctx, playerID)
	if err != nil {
		writeJSON(w, http.StatusNotFound, map[string]string{"error": err.Error()})
		return
	}
	writeJSON(w, http.StatusOK, player)
}

func (a *App) handleWorlds(w http.ResponseWriter, r *http.Request) {
	rawPath := strings.TrimSpace(strings.TrimPrefix(r.URL.Path, "/v1/worlds/"))
	if rawPath == "" {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "world_name required"})
		return
	}
	if strings.HasSuffix(rawPath, "/actions") {
		worldName := strings.TrimSuffix(rawPath, "/actions")
		a.handleWorldActions(w, r, strings.ToUpper(strings.TrimSpace(worldName)))
		return
	}
	worldName := rawPath
	switch r.Method {
	case http.MethodGet:
		ctx, cancel := context.WithTimeout(r.Context(), 8*time.Second)
		defer cancel()
		world, err := a.getWorld(ctx, strings.ToUpper(worldName))
		if err != nil {
			writeJSON(w, http.StatusNotFound, map[string]string{"error": err.Error()})
			return
		}
		writeJSON(w, http.StatusOK, world)
	case http.MethodPut:
		var payload WorldPayload
		if err := json.NewDecoder(r.Body).Decode(&payload); err != nil {
			writeJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid json body"})
			return
		}
		payload.Name = strings.ToUpper(worldName)
		if payload.Width == 0 {
			payload.Width = 100
		}
		if payload.Height == 0 {
			payload.Height = 60
		}
		ctx, cancel := context.WithTimeout(r.Context(), 10*time.Second)
		defer cancel()
		if err := a.upsertWorld(ctx, payload); err != nil {
			writeJSON(w, http.StatusInternalServerError, map[string]string{"error": err.Error()})
			return
		}
		writeJSON(w, http.StatusOK, map[string]string{"status": "saved", "world": payload.Name})
	default:
		writeJSON(w, http.StatusMethodNotAllowed, map[string]string{"error": "method not allowed"})
	}
}

func (a *App) getPlayer(ctx context.Context, playerID string) (*PlayerResponse, error) {
	var p PlayerResponse
	err := a.db.QueryRow(ctx, `
		SELECT id, name, character_id, current_world_name
		FROM players
		WHERE id = $1
	`, playerID).Scan(&p.ID, &p.Name, &p.CharacterID, &p.CurrentWorldName)
	if err != nil {
		return nil, errors.New("player not found")
	}
	p.Inventory = map[string]int{}
	p.Hotbar = []string{"", "", "", "", ""}

	rows, err := a.db.Query(ctx, `
		SELECT item_id, amount FROM player_inventory
		WHERE player_id = $1
	`, playerID)
	if err == nil {
		defer rows.Close()
		for rows.Next() {
			var itemID string
			var amount int
			if scanErr := rows.Scan(&itemID, &amount); scanErr == nil {
				p.Inventory[itemID] = amount
			}
		}
	}

	hRows, err := a.db.Query(ctx, `
		SELECT slot_index, item_id FROM player_hotbar
		WHERE player_id = $1
	`, playerID)
	if err == nil {
		defer hRows.Close()
		for hRows.Next() {
			var idx int
			var item string
			if scanErr := hRows.Scan(&idx, &item); scanErr == nil && idx >= 0 && idx < len(p.Hotbar) {
				p.Hotbar[idx] = item
			}
		}
	}
	return &p, nil
}

func (a *App) getWorld(ctx context.Context, worldName string) (map[string]any, error) {
	var (
		name        string
		width       int
		height      int
		ownerID     string
		worldLocked bool
		mainDoorX   int
		mainDoorY   int
		accessRaw   []byte
		locksRaw    []byte
	)
	err := a.db.QueryRow(ctx, `
		SELECT name, width, height, owner_id, world_locked, main_door_x, main_door_y, access_list::text, area_locks::text
		FROM worlds
		WHERE name = $1
	`, worldName).Scan(&name, &width, &height, &ownerID, &worldLocked, &mainDoorX, &mainDoorY, &accessRaw, &locksRaw)
	if err != nil {
		return nil, errors.New("world not found")
	}

	access := []string{}
	_ = json.Unmarshal(accessRaw, &access)
	locks := []map[string]any{}
	_ = json.Unmarshal(locksRaw, &locks)

	cells := map[string]map[string]any{}
	rows, err := a.db.Query(ctx, `
		SELECT x, y, block_id, planted_at
		FROM world_tiles
		WHERE world_name = $1
	`, worldName)
	if err == nil {
		defer rows.Close()
		for rows.Next() {
			var x, y int
			var block string
			var plantedAt int64
			if scanErr := rows.Scan(&x, &y, &block, &plantedAt); scanErr == nil {
				key := fmt.Sprintf("%d,%d", x, y)
				cells[key] = map[string]any{"block": block, "planted_at": plantedAt}
			}
		}
	}

	return map[string]any{
		"name":         name,
		"width":        width,
		"height":       height,
		"owner_id":     ownerID,
		"world_locked": worldLocked,
		"main_door_pos": map[string]int{
			"x": mainDoorX,
			"y": mainDoorY,
		},
		"access_list": access,
		"area_locks":  locks,
		"cells":       cells,
	}, nil
}

func (a *App) upsertWorld(ctx context.Context, payload WorldPayload) error {
	mainDoorX, mainDoorY := 50, 37
	if payload.MainDoorPos != nil {
		if v, ok := payload.MainDoorPos["x"]; ok {
			mainDoorX = v
		}
		if v, ok := payload.MainDoorPos["y"]; ok {
			mainDoorY = v
		}
	}
	accessJSON, _ := json.Marshal(payload.AccessList)
	locksJSON, _ := json.Marshal(payload.AreaLocks)

	tx, err := a.db.Begin(ctx)
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
	`, payload.Name, payload.Width, payload.Height, payload.OwnerID, payload.WorldLocked, mainDoorX, mainDoorY, string(accessJSON), string(locksJSON))
	if err != nil {
		return err
	}

	_, err = tx.Exec(ctx, `DELETE FROM world_tiles WHERE world_name = $1`, payload.Name)
	if err != nil {
		return err
	}
	for key, cell := range payload.Cells {
		parts := strings.Split(key, ",")
		if len(parts) != 2 {
			continue
		}
		x, xErr := strconv.Atoi(parts[0])
		y, yErr := strconv.Atoi(parts[1])
		if xErr != nil || yErr != nil {
			continue
		}
		if cell.Block == "" || cell.Block == "air" {
			continue
		}
		_, err = tx.Exec(ctx, `
			INSERT INTO world_tiles (world_name, x, y, block_id, planted_at)
			VALUES ($1, $2, $3, $4, $5)
		`, payload.Name, x, y, cell.Block, cell.PlantedAt)
		if err != nil {
			return err
		}
	}
	return tx.Commit(ctx)
}

func writeJSON(w http.ResponseWriter, status int, payload any) {
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(payload)
}

func withJSON(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		next.ServeHTTP(w, r)
	})
}
