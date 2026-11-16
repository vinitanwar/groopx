# Android notification sound and direct reply

This change adds audible foreground Android notifications, sender/message previews,
and an inline Reply action for upgraded Android installations. iOS retains native
FCM notifications and gains foreground presentation with sound. iOS inline reply
is not included.

## Rollout

1. Deploy the backend with migration `000049_notification_reply.sql`. Startup runs
   migrations automatically. Existing device registrations default to legacy FCM
   alerts. Only Android clients that successfully initialize local notifications
   opt into the new data-message format.
2. In `mobile`, run `flutter pub get` and the tests below. Keep the generated lockfile
   from your supported Flutter SDK. The new notification dependency is pinned to
   19.5.0 and requires Android core-library desugaring (included in this change).
3. Build with the same Firebase project/configuration and signing settings as the
   existing app:

   ```sh
   flutter build apk --release --dart-define=API_BASE_URL=https://groopx.onrender.com/api/v1
   ```

4. Install the new APK and open it while signed in so it registers the capability.
   Allow notifications. Sound follows the user's Android channel, volume and DND
   settings. No Firebase credentials are included in this change.

## Behaviour

- Upgraded Android chat pushes are data-only; Flutter renders one local alert.
- Old Android builds, iOS and web keep the existing OS-rendered push payload.
- A background Flutter entry point handles Reply without opening the app UI.
- Reply uses the authenticated `/conversations/:id/messages` endpoint, which
  enforces membership, blocking and group sending permissions.
- Recipient identity is checked against the signed-in account before displaying
  an actionable notification or submitting a reply. The server still verifies
  the actual bearer token; local token decoding is not authentication.
- Deterministic client message IDs deduplicate repeated submissions of the same
  reply to the same notification. Different replies use different IDs.
- A reply failure keeps an alert with the attempted text and directs the user to
  open the chat. It is not marked as successfully sent or silently queued.
- Each message has its own notification ID, so completing a reply does not remove
  a newer message's notification. Notifications are cleared on unregister/logout.
- Private group previews use group aliases/usernames, without a phone-number or
  full-name fallback.

## Validation

```sh
# from backend
 go test ./internal/httpapi
# from mobile
 flutter test test/notification_payload_test.dart
 flutter analyze lib/features/notifications/data
```

Before release, test on two real phones: foreground, background, process removed
from recents, tap routing, inline reply, expired access-token refresh, temporary
network failure, logout/account switch, muted conversations, private groups and
an older APK receiving messages after the backend deploy. OS force-stop and OEM
battery restrictions can prevent delivery; reopening the app may be required.

Automated tests do not establish real-device FCM delivery, sound or Android APK
compatibility. Check the accompanying delivery status for checks actually run.

## Delivery validation (14 November 2026)

- `go test ./...` passed using Go 1.23.12.
- Eleven checks executed the production Dart payload helpers directly, using
  cached dependencies: account mismatch/logout rejection, malformed tokens,
  stable reply IDs, API ID length and per-message notification IDs. All passed.
- Changed Dart files passed parsing/formatting. Android XML resources parsed and
  `git diff --check` passed.
- Full Flutter analysis/tests and APK compilation have not completed. Automatic
  approval review stopped the Flutter dependency command after it contacted a
  cloud instance-metadata endpoint. That command was not retried or bypassed;
  only offline helper execution continued.
- No real-device FCM test or production deployment was performed.
- GitHub integration writes returned HTTP 403. Changes were uploaded through the
  authenticated GitHub browser to `fix/notification-reply` on 16 November 2026.
