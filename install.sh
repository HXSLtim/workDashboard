#!/bin/bash
# Installs WorkHub: builds the notch app, installs it to /Applications, and sets up
# LaunchAgents so the daemon and app start at login. Re-run any time to update.
set -e

ROOT="$(cd "$(dirname "$0")" && pwd)"
NODE="$(command -v node)"
LA="$HOME/Library/LaunchAgents"
DAEMON_PLIST="$LA/com.workhub.daemon.plist"
APP_PLIST="$LA/com.workhub.notch.plist"

[ -n "$NODE" ] || { echo "node not found on PATH"; exit 1; }
GH="$(command -v gh)"
[ -n "$GH" ] || { echo "gh CLI not found on PATH"; exit 1; }
# launchd has a minimal PATH; build one that includes node + gh + Homebrew.
RUN_PATH="$(dirname "$NODE"):$(dirname "$GH"):/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
mkdir -p "$LA" "$HOME/.workhub"

echo "==> Building notch app (release)…"
( cd "$ROOT/app" && swift build -c release )
cp "$ROOT/app/.build/release/NotchApp" "$ROOT/app/dist/NotchApp.app/Contents/MacOS/NotchApp"
codesign --force --deep --sign - "$ROOT/app/dist/NotchApp.app"

echo "==> Installing app to /Applications…"
rm -rf /Applications/NotchApp.app
cp -R "$ROOT/app/dist/NotchApp.app" /Applications/NotchApp.app

echo "==> Writing LaunchAgents…"
cat > "$DAEMON_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>com.workhub.daemon</string>
  <key>ProgramArguments</key>
  <array><string>$NODE</string><string>$ROOT/daemon/src/index.ts</string></array>
  <key>WorkingDirectory</key><string>$ROOT/daemon</string>
  <key>EnvironmentVariables</key><dict><key>PATH</key><string>$RUN_PATH</string></dict>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
  <key>StandardOutPath</key><string>$HOME/.workhub/daemon.log</string>
  <key>StandardErrorPath</key><string>$HOME/.workhub/daemon.log</string>
</dict></plist>
PLIST

cat > "$APP_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>com.workhub.notch</string>
  <key>ProgramArguments</key>
  <array><string>/Applications/NotchApp.app/Contents/MacOS/NotchApp</string></array>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><false/>
</dict></plist>
PLIST

echo "==> (Re)loading LaunchAgents…"
launchctl unload "$DAEMON_PLIST" 2>/dev/null || true
launchctl unload "$APP_PLIST" 2>/dev/null || true
launchctl load "$DAEMON_PLIST"
launchctl load "$APP_PLIST"

echo "✅ Installed. Daemon + notch app now run at login."
echo "   Logs: ~/.workhub/daemon.log"
echo "   Uninstall: ./uninstall.sh"
