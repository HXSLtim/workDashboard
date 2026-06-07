#!/bin/bash
# Removes WorkHub LaunchAgents and the installed app. Leaves ~/.workhub data.
LA="$HOME/Library/LaunchAgents"
for label in com.workhub.daemon com.workhub.notch; do
  launchctl unload "$LA/$label.plist" 2>/dev/null || true
  rm -f "$LA/$label.plist"
done
pkill -f NotchApp 2>/dev/null || true
rm -rf /Applications/NotchApp.app
echo "✅ Uninstalled (kept ~/.workhub data). Re-run ./install.sh to reinstall."
