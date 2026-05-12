# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build & Run

This project uses [XcodeGen](https://github.com/yonaskolb/XcodeGen) — `project.yml` is the source of truth for the Xcode project. After changing `project.yml`, regenerate with:

```bash
xcodegen generate
```

Build from the command line (simulator):
```bash
xcodebuild -project Diabetico.xcodeproj \
  -scheme Diabetico \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  build
```

There are no automated tests and no linting tool configured.

## Secrets Setup

`Config.private.swift` is gitignored. Before building, copy the template and fill in real values:

```bash
cp Sources/Config/Config.private.swift.template Sources/Config/Config.private.swift
```

Then set `apiBaseURL`, `cognitoUserPoolID`, and `cognitoClientID` in the copy. The non-secret values (`cognitoRegion`, `healthSyncDays`) live in `Sources/Config/Config.swift`.

## Architecture

### System overview

```
iPhone App (iOS 16+, SwiftUI)
  ├── HealthKit  →  HealthKitService  →  POST /glucose|sleep|exercise/ingest
  └── HTTPS + Cognito JWT  →  AWS API Gateway
                                  ↓
                             Lambda (Python 3.11, Flask)
                               ├── health_agent.py — Claude API (urllib, no SDK)
                               │     └── 5 tools: get_glucose_data, get_sleep_data,
                               │                  get_exercise_data, detect_patterns,
                               │                  find_correlations
                               └── RDS MySQL (health_data database)
```

The backend lives in `Backend/` in this repo. Deploy via `Backend/lambda_deploy.sh`.

### iOS app layers

**Services** (`Sources/Services/`) — singletons accessed via `.shared`:
- `AuthService` — Cognito auth over raw REST (no Amplify). Stores ID token, refresh token, and access token in Keychain. On a 401, `APIService` automatically calls `refreshTokens()` and retries once before signing the user out. Provides `userEmail` (decoded from the JWT payload — no extra API call). `changePassword(current:new:)` uses the Cognito `ChangePassword` API with the stored access token.
- `APIService` — all network calls, typed with `Codable` generics (`ListResponse<T>`, `SingleResponse<T>`, `IngestResponse`). Always attaches the Cognito ID token as a Bearer header. Uses a custom `URLSession` with 15s request / 60s resource timeout.
- `HealthKitService` — reads blood glucose, sleep analysis, and workouts; POSTs them to the backend. Has a 30-minute cooldown on automatic syncs; `forceSyncAll()` bypasses it. Publishes `healthKitDenied` when the user has denied HealthKit access.

**Views + ViewModels** — MVVM, all `@MainActor`. Each screen owns a `@StateObject` ViewModel. Auth state flows down from `DiabetesHealthApp` as an `@EnvironmentObject`.

**Models** (`Sources/Models/HealthData.swift`) — all `Codable` structs. `parseHealthDate()` tries six date formats in sequence (ISO8601 with/without fractional seconds, MySQL DATETIME with/without fractional seconds) to handle varying backend output.

### Screens (4 tabs)

| Tab | View | Notes |
|-----|------|-------|
| Chat | `ChatView` | AI chat with tool-use badges. `/sync` command triggers HealthKit sync. |
| Dashboard | `DashboardView` | Glucose chart (≤500 sampled points), summary cards, pull-to-refresh. |
| Insights | `InsightsView` | AI-generated weekly insights (glucose, sleep, exercise, combined). |
| Account | `AccountView` | Email display, change password sheet, sign-out confirmation. |

### Data flow for a user action

**Chat:** User sends message → `ChatViewModel.send()` builds history array → `APIService.sendChat()` POSTs to `/chat` → Lambda runs Claude agent loop → response includes `tools_used` array → `ToolChip` badges rendered below the assistant bubble.

**Insights:** Tap Generate → `InsightsViewModel.generate()` → `APIService.generateInsights()` POSTs to `/insights/generate` → Lambda runs 4 separate agentic loops (glucose, sleep, exercise, combined) → returned and displayed as `InsightRow` cards.

**Dashboard:** On appear → `HealthKitService.syncAll()` (skipped if synced < 30 min ago) → `DashboardViewModel.loadAll()` fetches dashboard summary + glucose + sleep concurrently. 5-minute time-gate on `loadAll`; `force: true` bypasses it.

**Account / Change Password:** User enters current + new password → `AuthService.changePassword(current:new:)` POSTs to Cognito `ChangePassword` API using the stored access token → success dismisses the sheet.

### Key conventions

- **Guest mode**: `auth.isGuest == true` shows `SignInPromptView` instead of gated content (Insights, Chat). Dashboard loads but skips HealthKit sync.
- **Markdown rendering**: `MarkdownText` (in `ContentView.swift`) is a shared view used by both `ChatView` and `InsightsView`. It handles `##`, `###`, `- `/`* ` bullets, and inline bold/italic via `AttributedString`.
- **Sleep aggregation**: `DashboardViewModel.dailySleepHours` keeps only the best (highest, capped at 14h) record per calendar date to de-duplicate overlapping HK samples.
- **Glucose chart sampling**: `sampledGlucoseRecords` strides to ≤500 points to avoid UI hangs on large CGM datasets. Cache is invalidated on `didSet`.
- **iOS 16 target**: All APIs must be iOS 16-compatible. Use single-parameter `onChange(of:)`. `ContentUnavailableView` is not available — use a custom `VStack` fallback instead.
- **500 on ingest is non-fatal**: The backend returns HTTP 500 on MySQL `IntegrityError` when records already exist. `APIService.ingestGlucose/Sleep/Exercise` silently swallow `serverError(500, _)`.
- **Cognito error mapping**: `AuthService.assertHTTP200` parses the `__type` field from Cognito error responses and maps 8 known error types to user-friendly strings. Add new mappings in `userFacingMessage(cognitoType:fallback:)`.
- **Access token**: Stored under `DiabetesHealth.accessToken` in Keychain. Required for `ChangePassword`. Refreshed on `refreshTokens()` only when Cognito returns a new one (refresh token flow may omit it).
- **HealthKit denied**: If the user denies HealthKit, `HealthKitService.shared.healthKitDenied` is set to `true`. `DashboardView` shows a banner with an "Open Settings" deep link. `resetAuthState()` clears this on sign-out.

## Backend (`Backend/`)

Python 3.11, Flask, deployed as AWS Lambda via a custom WSGI adapter (no Mangum).

```
Backend/
  health_agent.py   — Claude agentic loop (urllib, no SDK), 5 RDS tools
  tools.py          — get_glucose_data, get_sleep_data, get_exercise_data,
                      detect_patterns, find_correlations (all read-only RDS queries)
  rest_api.py       — Flask routes + Lambda WSGI handler
  models.py         — SQLAlchemy ORM (BloodGlucose, SleepData, ExerciseData, AIInsight)
  db_config.py      — RDS connection config (reads from .env)
  requirements.txt  — Python dependencies
  lambda_deploy.sh  — packages and uploads to Lambda
  tests/            — pytest test suite
  .env              — gitignored; contains RDS_PASSWORD, ANTHROPIC_API_KEY, etc.
```

To deploy backend changes:
```bash
cd Backend
./lambda_deploy.sh
```

Key backend limits: Claude tool calls cap at 200 records per query (prevents context overflow). Agent loop max 10 iterations. System prompt instructs 2-4 sentence responses.
