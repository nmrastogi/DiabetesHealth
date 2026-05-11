# Diabeto

An AI-powered diabetes health companion for iPhone. Syncs blood glucose, sleep, and exercise data from Apple Health and uses Claude AI to generate personalised insights and answer questions about your health in plain English.

## Features

- **Glucose dashboard** — time-in-range tracking, trend chart, average mg/dL
- **AI Chat** — ask questions about your own health data ("How did my sleep affect my glucose last week?")
- **Automated insights** — weekly AI-generated summaries for glucose, sleep, exercise, and combined health
- **Pattern & correlation detection** — identifies hourly/weekly trends and correlations between metrics
- **Apple Health sync** — reads CGM readings, sleep stages, and workouts automatically
- **Account management** — change password, sign out, HealthKit sync status

## Tech Stack

**iOS App**
- SwiftUI, iOS 16+, MVVM
- HealthKit (blood glucose, sleep analysis, workouts)
- AWS Cognito (auth, JWT stored in Keychain)
- Swift Charts

**Backend** (AWS Lambda, Python 3.11)
- Flask + custom WSGI adapter
- Anthropic Claude Haiku — agentic loop with 5 read-only RDS tools
- AWS API Gateway, RDS MySQL
- SQLAlchemy ORM

## Project Structure

```
DiabetesHealth/
├── Sources/
│   ├── App/            — entry point, tab view, shared MarkdownText renderer
│   ├── Config/         — Config.swift (non-secret), Config.private.swift (gitignored)
│   ├── Models/         — Codable structs, 6-format date parser
│   ├── Services/       — AuthService, APIService, HealthKitService
│   └── Views/
│       ├── Auth/       — LoginView, SignUpView, ConfirmView
│       ├── Dashboard/  — DashboardView + glucose chart
│       ├── Insights/   — InsightsView, ChatView
│       └── Account/    — AccountView, ChangePasswordView
├── Backend/            — Python Lambda backend (see Backend/README.md)
├── docs/               — GitHub Pages (privacy policy)
├── project.yml         — XcodeGen source of truth
└── CLAUDE.md           — guidance for Claude Code
```

## iOS Setup

### Requirements
- Xcode 15+
- [XcodeGen](https://github.com/yonaskolb/XcodeGen): `brew install xcodegen`
- Apple Developer account (paid, for device builds and App Store)

### Steps

```bash
# 1. Clone the repo
git clone https://github.com/nmrastogi/DiabetesHealth.git
cd DiabetesHealth

# 2. Create your private config
cp Sources/Config/Config.private.swift.template Sources/Config/Config.private.swift
# Fill in apiBaseURL, cognitoUserPoolID, cognitoClientID

# 3. Add your Team ID to project.yml
#    DEVELOPMENT_TEAM: "YOUR_TEAM_ID"

# 4. Generate the Xcode project
xcodegen generate

# 5. Open in Xcode
open Diabeto.xcodeproj
```

Build & run on the iPhone 17 simulator:
```bash
xcodebuild -project Diabeto.xcodeproj \
  -scheme Diabeto \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  build
```

## Backend Setup

See `Backend/README.md` for full instructions. Quick start:

```bash
cd Backend
cp .env.example .env        # fill in RDS credentials and ANTHROPIC_API_KEY
pip install -r requirements.txt
python rest_api.py           # local dev server on :5001
```

Deploy to AWS Lambda:
```bash
cd Backend
./lambda_deploy.sh
```

## Architecture

```
iPhone (HealthKit)
  │
  ▼
HealthKitService ──POST /ingest──▶ AWS API Gateway
                                        │
AuthService (Cognito JWT) ─────────────▶ AWS Lambda (Flask)
                                        │
                                   health_agent.py
                                   (Claude Haiku + 5 tools)
                                        │
                                   RDS MySQL
                                   (glucose, sleep, exercise, insights)
```

### Claude Agent Tools

| Tool | Description |
|------|-------------|
| `get_glucose_data` | Blood glucose readings (timestamped mg/dL), max 200 records |
| `get_sleep_data` | Sleep records with duration and stages |
| `get_exercise_data` | Workout records with duration |
| `detect_patterns` | Hourly/weekly patterns in any metric |
| `find_correlations` | exercise↔glucose, sleep↔glucose, sleep↔exercise |

## App Store

- **Bundle ID**: `com.diabeto.app`
- **Deployment target**: iOS 16.0
- **Privacy policy**: `docs/privacy.html` (published via GitHub Pages)
- **HealthKit entitlement**: read-only (glucose, sleep, workouts)
- **Encryption**: none (`ITSAppUsesNonExemptEncryption: false`)

## License

Private — all rights reserved.
