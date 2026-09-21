package config

import (
	"os"
	"time"
)

type Config struct {
	Address          string
	DatabaseURL      string
	JWTSecret        string
	AccessTokenTTL   time.Duration
	RefreshTokenTTL  time.Duration
	DevelopmentMode bool
	S3Endpoint       string
	S3Region         string
	S3Bucket         string
	S3AccessKey      string
	S3SecretKey      string
	S3PublicBaseURL  string
	AdminEmail       string
	AdminPassword    string
	TwilioAccountSID string
	TwilioAuthToken  string
	TwilioVerifySID  string
}

func Load() Config {
	port := os.Getenv("PORT")
	if port == "" { port = "8080" }
	secret := os.Getenv("JWT_SECRET")
	if secret == "" { secret = "change-this-development-secret" }
	return Config{
		Address: ":" + port,
		DatabaseURL: os.Getenv("DATABASE_URL"),
		JWTSecret: secret,
		AccessTokenTTL: 15 * time.Minute,
		RefreshTokenTTL: 30 * 24 * time.Hour,
		DevelopmentMode: os.Getenv("APP_ENV") != "production",
		S3Endpoint: os.Getenv("S3_ENDPOINT"),
		S3Region: envOr("S3_REGION", "auto"),
		S3Bucket: os.Getenv("S3_BUCKET"),
		S3AccessKey: os.Getenv("S3_ACCESS_KEY"),
		S3SecretKey: os.Getenv("S3_SECRET_KEY"),
		S3PublicBaseURL: os.Getenv("S3_PUBLIC_BASE_URL"),
		AdminEmail: os.Getenv("ADMIN_EMAIL"),
		AdminPassword: os.Getenv("ADMIN_PASSWORD"),
		TwilioAccountSID: os.Getenv("TWILIO_ACCOUNT_SID"),
		TwilioAuthToken: os.Getenv("TWILIO_AUTH_TOKEN"),
		TwilioVerifySID: os.Getenv("TWILIO_VERIFY_SERVICE_SID"),
	}
}

func envOr(key, fallback string) string { if value:=os.Getenv(key); value!="" { return value }; return fallback }
