package main

import (
	"log"

	"github.com/gin-gonic/gin"
	"groopx/backend/internal/config"
	"groopx/backend/internal/httpapi"
)

func main() {
	cfg := config.Load()
	router := gin.New()
	router.Use(gin.Logger(), gin.Recovery())
	httpapi.Register(router)
	log.Printf("GroopX API listening on %s", cfg.Address)
	log.Fatal(router.Run(cfg.Address))
}

