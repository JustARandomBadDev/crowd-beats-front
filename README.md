# Crowd Beats

Crowd Beats is the Flutter customer application for a mobile Crowd DJ MVP for
bars and clubs. A guest scans a venue QR code, joins a Room with a temporary
nickname, sees the shared queue, proposes Spotify tracks through the Crowd
Beats backend, and votes for active tracks.

The client uses anonymous sessions and treats the frozen backend contract as
the source of truth. It does not contact Spotify directly or control music
playback.

## MVP features

- Anonymous QR join with a nickname.
- Secure session-token storage, startup restoration, heartbeat, leave, and
  single-Room switching.
- Room details, now playing, and the ordered queue from REST.
- Live queue synchronization and reconnect handling over WebSocket.
- Spotify search through the Crowd Beats backend.
- Track proposal, including the duplicate-track path to the shared vote action.
- Voting with backend-confirmed personal `votes_remaining` feedback.
- Responsive dark mobile UI with loading, empty, retry, and connection states.

## User flow

```text
Launch
  -> restore a valid stored session, or scan a temporary venue QR
  -> enter a nickname
  -> Room
  -> view now playing and the queue
  -> search Spotify through the backend
  -> propose a track
  -> vote for an active Room track
  -> leave, or scan another QR to switch Rooms
```

A Room switch keeps the current client session usable until the new QR join
succeeds. The returned token is stored before the UI enters the new Room.

## Architecture

The application uses Flutter and Riverpod with small feature-scoped
controllers:

| Area | Responsibility |
| --- | --- |
| API | HTTP transport, response envelopes, structured failures, typed DTOs, and endpoint methods. |
| Session | Bootstrap, `/sessions/me` restoration, QR join, secure token persistence, 45-second heartbeat, leave, switching, and authoritative invalidation. |
| Room | Initial Room and queue REST state, manual refresh, WebSocket lifecycle, reconnect, resynchronization, and snapshot freshness. |
| Search/proposal | Backend Spotify search, stale-search protection, proposal actions, and business feedback. |
| Voting | Per-track request state, backend-confirmed results, and known personal vote quota. |
| Storage | The current opaque session token in `flutter_secure_storage`. |
| UI | Material dark theme and shared presentation widgets under `lib/core/theme` and `lib/core/widgets`. |

Provider state that belongs to a Room is keyed by its Room ID and session token.
Disposal, leave, and switching stop the old Room resources and prevent late
responses from changing a newer session.

### Session lifecycle

Users are anonymous. The nickname belongs to the temporary backend session and
is not stored as a profile. Joining or switching requires a valid temporary QR
code.

On startup, the client reads the securely stored token and validates it with
`GET /api/v1/sessions/me`. A valid session restores the Room. A documented
`401 UNAUTHORIZED` clears the matching local session and returns to Join.
Transport errors and temporary backend failures retain the token and offer a
retry. While a Room is active, a heartbeat runs every 45 seconds, within the
backend's documented 30-to-60-second recommendation.

Only one client session and Room are active at a time. Leave calls the backend
before clearing local state; authoritative invalidation also clears the local
token. Widgets never manipulate secure storage directly.

### Room synchronization

REST provides:

- initial Room metadata;
- the initial queue snapshot;
- pull-to-refresh;
- explicit queue resynchronization.

After initial REST data is available, the client connects to
`WS_BASE_URL?room_id=<room-id>` with the current bearer token. WebSocket events
provide live synchronization. `sync_required` triggers a fresh queue request,
and `queue_updated` replaces the displayed queue with its complete
authoritative snapshot. Reconnect uses bounded exponential backoff and retains
the last valid queue while live updates are unavailable.

When REST and WebSocket snapshots both contain comparable `updated_at` values,
an older snapshot cannot replace a newer one. The protocol has no event replay;
reconnection resynchronizes through REST.

### Search, proposal, and voting

Spotify search always uses `GET /api/v1/spotify/search` on the Crowd Beats
backend. The Flutter app contains no Spotify SDK, credentials, or direct
Spotify API integration. A proposal sends only the selected backend Spotify
track identifier. The backend decides whether the track is valid, duplicated,
or blocked by queue capacity.

A successful proposal confirms the action but does not insert a track locally.
When the backend reports an existing active Room track, the UI offers the same
vote action used in the Room.

Votes target `room_track_id`. The backend enforces track eligibility, one vote
per session and track, and the Room vote limit. The client only records a
confirmed response and any returned `votes_remaining`. It does not
optimistically change vote counts, scores, positions, or ordering. Subsequent
REST or `queue_updated` snapshots update the shared queue.

## Backend authority

The Flutter client does not calculate or independently validate:

- queue ranking or FIFO tie-breaking;
- scores, vote counts, or queue capacity;
- proposal duplication or acceptance;
- vote eligibility or limits;
- Room, QR, or session validity.

REST action responses answer whether a user action succeeded. REST queue
snapshots and complete WebSocket `queue_updated` events define the shared queue
and its order.

## Non-goals

The customer MVP does not implement:

- user accounts, profiles, customer history, or analytics;
- XP, badges, rankings, gamification, or super-votes;
- AI recommendations or automatic playlist generation;
- automatic playback or playback controls;
- direct Spotify API access or Spotify credentials in Flutter;
- Apple Music or Deezer;
- venue or geolocation discovery;
- payments;
- manager dashboards, moderation, establishment setup, or manager analytics.

## Requirements

- Flutter **3.41.9**. CI installs this exact stable release.
- Dart SDK **`^3.11.5`**, as declared in `pubspec.yaml`.
- A running Crowd Beats backend that implements the frozen API and WebSocket
  contracts.
- For Android development: Android SDK with command-line tools, accepted SDK
  licenses, and JDK 17.
- A camera-equipped mobile target for real QR scanning.

## Configuration

`lib/core/config/app_config.dart` reads two compile-time values. They are not
secrets.

| Dart define | Default | Accepted format | Purpose |
| --- | --- | --- | --- |
| `API_BASE_URL` | `http://localhost:8080` | Absolute `http` or `https` URL with a host and without user info, query, or fragment | Origin to which the client appends REST paths such as `/api/v1/...`. |
| `WS_BASE_URL` | `ws://localhost:8080/ws` | Absolute `ws` or `wss` URL with a host and without user info, query, or fragment | Full WebSocket endpoint path; the client adds `room_id` as a query parameter. |

Configuration is validated before `runApp`; an invalid URL stops startup with a
configuration error.

The defaults work when the target resolves `localhost` to the backend host. The
standard Android emulator reaches the development machine through `10.0.2.2`:

```bash
flutter run \
  --dart-define=API_BASE_URL=http://10.0.2.2:8080 \
  --dart-define=WS_BASE_URL=ws://10.0.2.2:8080/ws
```

For a physical device, use a reachable LAN address instead. The Android debug
manifest permits cleartext HTTP for local development. Use `https` and `wss`
for a deployed backend.

Spotify provider credentials belong only to the backend and must never be
passed as Flutter configuration.

## Running

From the repository root:

```bash
flutter --no-version-check pub get

flutter --no-version-check run \
  --dart-define=API_BASE_URL=http://localhost:8080 \
  --dart-define=WS_BASE_URL=ws://localhost:8080/ws
```

Replace the URLs for the selected device as described above. The backend must
provide an active Room and a non-expired QR code before a new user can join.

## Validation

Run the same checks used by CI:

```bash
flutter --no-version-check pub get
dart format --output=none --set-exit-if-changed .
flutter --no-version-check analyze --no-pub
flutter --no-version-check test --no-pub
git diff --check
```

The Prompt 10 baseline for the current repository state is **79 executed test
cases, 79 passing**. This records a verified revision; it is not a fixed target
for future suite changes.

The suite contains API and DTO contract tests, session/controller tests,
Room/WebSocket lifecycle tests, search/proposal tests, voting tests, and focused
widget/responsive tests. It uses controlled HTTP and WebSocket fakes. It is not
a physical-device, live-backend, live-Spotify, or physical-camera end-to-end
suite.

## Android setup

1. Install Flutter 3.41.9 and an Android SDK supported by that Flutter release.
2. Install the Android SDK command-line tools and required platform/build tools.
3. Use JDK 17; the Android module compiles Java and Kotlin to Java 17.
4. Accept licenses with `flutter doctor --android-licenses`.
5. Confirm the toolchain with `flutter doctor -v`.
6. Start an emulator or connect an Android device with USB debugging enabled.

Build a development APK with:

```bash
flutter --no-version-check build apk --debug --no-pub
```

The repository does not define release signing or deployment automation for a
production store release.

## CI

`.github/workflows/flutter.yml` runs one Linux validation job on every push and
pull request. It installs Flutter 3.41.9 stable, resolves dependencies, checks
formatting, runs static analysis, and executes the full test suite. It does not
build or publish an APK.

## Project structure

```text
lib/
  core/
    api/          HTTP transport, failures, paths, and typed API
    config/       compile-time configuration and dependency providers
    storage/      secure session-token storage
    theme/        application theme and design tokens
    websocket/    socket transport and event parsing
    widgets/      shared presentation widgets
  features/
    session/      bootstrap, join, scanner, heartbeat, switch, and leave
    room/         Room REST state, live synchronization, and Room UI
    search/       Spotify search and proposal state/UI
    vote/         shared voting state and controls
  models/         strict backend request/response DTOs
  main.dart       application bootstrap and session gateway
test/             API, model, controller, protocol, and widget tests
android/          Android runner and Gradle configuration
ios/              iOS runner configuration
```

## Backend contract

The authoritative backend documentation lives in the expected sibling backend
checkout:

- [`../crowd-beats-api/docs/api.md`](../crowd-beats-api/docs/api.md) — REST
  endpoints, DTOs, errors, session rules, and Flutter flow.
- [`../crowd-beats-api/docs/websocket.md`](../crowd-beats-api/docs/websocket.md)
  — authentication, events, snapshots, and reconnection.
- [`../crowd-beats-api/docs/architecture.md`](../crowd-beats-api/docs/architecture.md)
  — backend authority, persistence, queue calculation, and scheduler behavior.

The backend uses `data/error/meta` REST envelopes and `snake_case` JSON. Do not
change client DTOs or behavior based on assumptions that conflict with these
frozen contracts.

## MVP limitations

- Joining or switching Rooms requires a valid temporary QR code.
- Live WebSocket events have no replay; recovery uses an authoritative REST
  queue snapshot.
- The UI only knows the personal remaining-vote count after the backend returns
  it in a successful vote response.
- Music playback and all manager workflows remain outside the customer app.
