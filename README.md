# devialet-expert-remote-app

Flutter remote-control app for the Devialet Expert Pro amplifier series,
targeting Android and iOS. A port of an earlier Android-only Kotlin app
([devialet-expert-remote](https://github.com/ekmanch/devialet-expert-remote)).

See `CLAUDE.md` for project background, architecture decisions, and working
conventions.

## Getting started

```
flutter pub get
flutter test
flutter run
```

To preview the iOS UI variant while running on an Android device (no
physical iOS device required for quick iteration), pass:

```
flutter run --dart-define=UI_VARIANT=ios
```

See `CLAUDE.md`, "Runtime UI variant switching", for the Android Studio
run-configuration setup.
