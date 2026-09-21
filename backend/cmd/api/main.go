package main

import (
	"context"
	"log"
	"net/http"

	"github.com/gin-gonic/gin"
	"github.com/jackc/pgx/v5/pgxpool"
	"groopx/backend/internal/config"
	"groopx/backend/internal/database"
	"groopx/backend/internal/httpapi"
)

func main() {
	cfg := config.Load()
	if cfg.DatabaseURL == "" {
		log.Fatal("DATABASE_URL is required")
	}
	db, err := pgxpool.New(context.Background(), cfg.DatabaseURL)
	if err != nil { log.Fatalf("database configuration failed: %v", err) }
	defer db.Close()
	if err := db.Ping(context.Background()); err != nil { log.Fatalf("database connection failed: %v", err) }
	if err := database.Migrate(context.Background(), db, "migrations"); err != nil { log.Fatalf("database migration failed: %v", err) }
	router := gin.New()
	router.Use(gin.Logger(), gin.Recovery())
	router.Use(func(c *gin.Context) {
		origin := c.GetHeader("Origin")
		if origin != "" {
			c.Header("Access-Control-Allow-Origin", origin)
			c.Header("Vary", "Origin")
			c.Header("Access-Control-Allow-Headers", "Content-Type, Authorization")
			c.Header("Access-Control-Allow-Methods", "GET, POST, PUT, PATCH, DELETE, OPTIONS")
		}
		if c.Request.Method == http.MethodOptions {
			c.AbortWithStatus(http.StatusNoContent)
			return
		}
		c.Next()
	})
	httpapi.Register(router, db, cfg)
	router.Static("/admin-panel", "./admin")
	router.GET("/admin", func(c *gin.Context) { c.Redirect(http.StatusTemporaryRedirect, "/admin-panel/") })
	log.Printf("GroopX API listening on %s", cfg.Address)
	log.Fatal(router.Run(cfg.Address))
}
