package main

import (
	"log"
	"net/http"

	"github.com/gin-gonic/gin"
	"groopx/backend/internal/config"
	"groopx/backend/internal/httpapi"
)

func main() {
	cfg := config.Load()

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

	httpapi.Register(router)

	log.Printf("GroopX API listening on %s", cfg.Address)
	log.Fatal(router.Run(cfg.Address))
}