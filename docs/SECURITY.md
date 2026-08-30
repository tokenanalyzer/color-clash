# Color Clash — Security Rules

- Never commit secrets, API keys intended to be private, service-account credentials, signing keys, or Play purchase credentials.
- Treat the client as untrusted for premium entitlements and sensitive economy operations.
- Validate purchases through a trusted backend path.
- Keep coin/booster mutation rules explicit and auditable.
- Use Firebase App Check where supported.
- Rate-limit trusted callable operations where appropriate.
- Keep analytics free of unnecessary personal data.
- Do not store payment card information.
- Never add real-money redemption or cash-out mechanics to the virtual currency.
