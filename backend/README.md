# Color Clash Backend

Firebase integration lives here conceptually; no secrets or project-specific credentials belong in Git.

## Planned services

- Firebase Authentication
- Cloud Firestore
- Cloud Functions
- Remote Config
- Analytics
- Crashlytics
- App Check

## Setup

Create a dedicated Firebase project for Color Clash and keep its project-specific identifiers in local/CI configuration. Do not commit service-account keys, API secrets, signing keys, or production credentials.

Cloud Functions will be added once the Firebase project ID and deployment environment are established.
