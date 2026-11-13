# TestFlight helpers

`cd ios && fastlane beta` uploads a build and stops: only the internal
"Friends" group gets it, and it has no "What to Test" notes. These scripts
finish the job over the App Store Connect API (spaceship, bundled with
Homebrew fastlane). Run them from `ios/` with the key in `fastlane/.env`:

```
cd ios && set -a && source fastlane/.env && set +a
RUBY="GEM_HOME=$HOME/.local/share/fastlane/4.0.0 GEM_PATH=$HOME/.local/share/fastlane/4.0.0:/opt/homebrew/Cellar/fastlane/2.241.0/libexec /opt/homebrew/opt/ruby/bin/ruby"
```

- `list_builds.rb` — the newest builds with their internal/external state, and the groups. Read-only.
- `build_notes.rb <build> "<notes>"` — waits for processing, then sets the build's What to Test text.
- `submit_external.rb <build>` — submits for Beta App Review and adds the build to the external "Beta Testers" group. Ask Andy before running: he decides per build.

Build 10 (2026-11-01) went through all three.
