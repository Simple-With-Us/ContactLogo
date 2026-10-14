# ContactLogo Android — official Sentry SDK

- **SDK:** `io.sentry:sentry-android:8.59.0` plus `io.sentry.android.gradle` 6.23.0 (ProGuard/R8 mapping + source context when `SENTRY_AUTH_TOKEN` is set).
- **Init:** `ContactLogoApp.onCreate` before UI.  `io.sentry.auto-init=false` in the manifest.
- **DSN:** `BuildConfig.SENTRY_DSN` from env `SENTRY_DSN` at compile time.  Unset/empty → SDK not initialized.
- **Privacy:** `sendDefaultPii=false`, no screenshots, no view hierarchy (contacts PII).
- **Sampling:** `tracesSampleRate=0.2`.  Crash + ANR enabled.
- **Gate:** `Apps/ContactLogoAndroid` `./gradlew test`.
