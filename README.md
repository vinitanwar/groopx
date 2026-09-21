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
- Call history and incoming-call accept/decline screens
- Contact info, group editing and shared media/documents screens
- Storage/data, Help/About, notification detail and avatar preview screens
- Linked Devices with active-session history, individual remote logout and secure logout from all other devices
- Admin announcements with in-app/FCM delivery and integration health dashboard

LiveKit requires `LIVEKIT_URL`, `LIVEKIT_API_KEY` and `LIVEKIT_API_SECRET` environment variables.

Development OTP: `123456`. In production, GroopX uses Twilio Verify for real SMS
delivery and verification. Configure these Render environment variables:

- `APP_ENV=production`
- `TWILIO_ACCOUNT_SID` — Twilio Account SID
- `TWILIO_AUTH_TOKEN` — Twilio Auth Token
- `TWILIO_VERIFY_SERVICE_SID` — Verify Service SID beginning with `VA`

OTP requests use E.164 phone numbers, expire after 10 minutes, allow five verify
attempts, and enforce a 60-second resend cooldown. Never expose Twilio credentials
in the Flutter application.

## Admin dashboard

The Go service now includes a responsive GroopX admin dashboard at:

`https://YOUR_API_DOMAIN/admin`

Configure these server-side environment variables before opening it:

- `ADMIN_EMAIL` — administrator login email
- `ADMIN_PASSWORD` — strong administrator password
- `JWT_SECRET` — random secret of at least 32 characters

Admin functionality includes overview analytics, user search and suspension,
groups, privacy-safe conversation metadata, safety reports, calls, and an audit
trail. Private message bodies are intentionally not available to administrators.

## Media and profile photos

Chat attachments and profile photos use S3-compatible object storage. Configure
these server-side variables on Render before testing photo uploads:

- `S3_ENDPOINT` — storage API endpoint (for example, an R2 S3 endpoint)
- `S3_REGION` — storage region; use `auto` for Cloudflare R2
- `S3_BUCKET` — bucket name
- `S3_ACCESS_KEY` — bucket access key
- `S3_SECRET_KEY` — bucket secret key
- `S3_PUBLIC_BASE_URL` — public or custom-domain URL for stored files

The mobile app accepts JPEG, PNG, WebP, and HEIC profile photos up to 10 MB.

## Push notifications

The app registers FCM device tokens, handles foreground alerts, and opens the
correct chat or call when a notification is tapped from background or a closed
state. Add the Firebase Android configuration file at
`mobile/android/app/google-services.json` using the final Android application ID.
On Render, set `GOOGLE_APPLICATION_CREDENTIALS` to the mounted Firebase service
account JSON path. Keep both Firebase files and service-account credentials out
of Git.

## Android release identity and signing

The production Android application ID is `com.futureittouch.groopx`. Copy
`mobile/android/key.properties.example` to `mobile/android/key.properties`, add
the release keystore under `mobile/android/app/`, and replace all placeholder
passwords before publishing. Firebase must use the same application ID.
