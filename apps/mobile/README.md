# Home Services Mobile App

A Flutter mobile application for the Home Services Platform.

## Getting Started

### Running the app

By default, running the app connects to the live production backend:

`ash
cd apps/mobile
flutter pub get
flutter run
`

This will connect to: https://api-production-abe8e.up.railway.app

### Optional overrides

Development mode:
`ash
flutter run --dart-define=ENVIRONMENT=development --dart-define=API_BASE_URL=http://10.0.2.2:8000
`

Production (explicit):
`ash
flutter run --dart-define=ENVIRONMENT=production --dart-define=API_BASE_URL=https://api-production-abe8e.up.railway.app
`
