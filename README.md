# GroopX

Flutter mobile client and Go API for the GroopX messaging platform.

## Structure

- `mobile/` — Flutter application
- `backend/` — Go REST/WebSocket API foundation

The UI is reconstructed from the supplied Figma reference at a 375×812 design baseline and scales responsively.

## Implemented

- Welcome, sign-in, sign-up, six-digit OTP and personal-info screens
- Figma-derived light/dark GroopX visual system
- Flutter navigation and real HTTP calls for OTP request/verification
- Go health, request-OTP, verify-OTP and profile endpoints
- PostgreSQL user and refresh-token migration
- Figma-derived chat list with filters, unread badges and bottom navigation
- One-to-one conversation UI with message bubbles and read status
- Flutter WebSocket client and Go WebSocket endpoint
- PostgreSQL conversations, members, messages and reactions migration
- Figma-derived Create Group, Group Info and Add Contact screens
- Contact, group, archive/delete and media pre-sign API contracts
- PostgreSQL contacts, group privacy, media and attachment migration
- Reminder/meeting list and create-reminder flow
- Audio/video calling UI and conversation call actions
- LiveKit-compatible backend JWT token endpoint
- Push-device registration and call/reminder API contracts
- PostgreSQL reminders, devices, calls and participants migration

LiveKit requires `LIVEKIT_URL`, `LIVEKIT_API_KEY` and `LIVEKIT_API_SECRET` environment variables.

Development OTP: `123456`. Replace the in-memory OTP store with a production SMS provider before release.
