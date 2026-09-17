# GroopX local setup

## Requirements

- Flutter SDK and Android Studio
- Go 1.23+
- PostgreSQL

## Backend

```bash
cd backend
go mod tidy
go run ./cmd/api
```

The API runs at `http://localhost:8080`. Development OTP: `123456`.

Apply migrations in numeric order with `psql` if database schema inspection is needed. Current development handlers still use temporary in-memory stores.

## Flutter

```bash
cd mobile
flutter create --platforms=android,ios .
flutter pub get
flutter analyze
flutter run
```

The default Android-emulator API URL is `http://10.0.2.2:8080/api/v1` and WebSocket URL is `ws://10.0.2.2:8080`.

For a physical device, pass the computer's LAN address:

```bash
flutter run \
  --dart-define=API_BASE_URL=http://192.168.1.10:8080/api/v1 \
  --dart-define=WS_BASE_URL=ws://192.168.1.10:8080
```

## LiveKit

Copy `.env.example` values into the backend environment before starting the API. The call UI works without these values, but media-room connection requires a configured LiveKit server.

