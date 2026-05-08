# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build & Run

This project uses [XcodeGen](https://github.com/yonaskolb/XcodeGen) — `project.yml` is the source of truth for the Xcode project. After changing `project.yml`, regenerate with:

```bash
xcodegen generate
```

Build from the command line (simulator):
```bash
xcodebuild -project DiabetesHealth.xcodeproj \
  -scheme DiabetesHealth \
  -destination 'platform=iOS Simulator,name=iPhone 15' \
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

The backend lives in a separate repo at `/Users/namanrastogi/Documents/MCP_diabetes/`.

### iOS app layers

**Services** (`Sources/Services/`) — singletons accessed via `.shared`:
- `AuthService` — Cognito auth over raw REST (no Amplify). Stores ID/refresh tokens in Keychain. On a 401, `APIService` automatically calls `refreshTokens()` and retries once before signing the user out.
- `APIService` — all network calls, typed with `Codable` generics (`ListResponse<T>`, `SingleResponse<T>`, `IngestResponse`). Always attaches the Cognito ID token as a Bearer header.
- `HealthKitService` — reads blood glucose, sleep analysis, and workouts; POSTs them to the backend. Has a 30-minute cooldown on automatic syncs; `forceSyncAll()` bypasses it.

**Views + ViewModels** — MVVM, all `@MainActor`. Each screen owns a `@StateObject` ViewModel. Auth state flows down from `DiabetesHealthApp` as an `@EnvironmentObject`.

**Models** (`Sources/Models/HealthData.swift`) — all `Codable` structs. `parseHealthDate()` tries six date formats in sequence (ISO8601 with/without fractional seconds, MySQL DATETIME with/without fractional seconds) to handle varying backend output.

### Data flow for a user action

**Chat:** User sends message → `ChatViewModel.send()` builds history array from prior messages → `APIService.sendChat()` POSTs to `/chat` with question + history → Lambda runs Claude agent loop → response includes `tools_used` array → `ToolChip` badges rendered below the assistant bubble.

**Insights:** Tap Generate → `InsightsViewModel.generate()` → `APIService.generateInsights()` POSTs to `/insights/generate` → Lambda asks Claude to produce 4 typed insights → returned and displayed as `InsightRow` cards.

**Dashboard:** On appear → `HealthKitService.syncAll()` (skipped if synced < 30 min ago) → `DashboardViewModel.loadAll()` fetches dashboard summary + glucose + sleep concurrently.

### Key conventions

- **Guest mode**: `auth.isGuest == true` shows `SignInPromptView` instead of gated content (Insights, Chat). Dashboard loads but skips HealthKit sync.
- **Markdown rendering**: `MarkdownText` (in `ContentView.swift`) is a shared view used by both `ChatView` and `InsightsView`. It handles `##`, `###`, `- `/`* ` bullets, and inline bold/italic via `AttributedString`.
- **Sleep aggregation**: `DashboardViewModel.dailySleepHours` keeps only the best (highest, capped at 14h) record per calendar date to de-duplicate overlapping HK samples. Glucose chart is sampled to ≤500 points to avoid UI hangs on large datasets.
- **iOS 16 target**: All APIs must be iOS 16-compatible. Use single-parameter `onChange(of:)`. `ContentUnavailableView` is not available — use a custom `VStack` fallback instead.
- **500 on ingest is non-fatal**: The backend returns HTTP 500 on MySQL `IntegrityError` when records already exist. `APIService.ingestGlucose/Sleep/Exercise` silently swallow `serverError(500, _)`.
