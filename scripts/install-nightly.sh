#!/bin/zsh
# Installs (or with --uninstall removes) the nightly self-test as a LaunchAgent: tests/nightly.sh every night at 04:00, as you, with your
# login session (it needs the GUI session for the sandboxed test build). Nothing else on the system changes.
emulate -L zsh
REPO="${0:A:h:h}"; LABEL="local.cosmopolitan.selftest"; PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
launchctl bootout "gui/$(id -u)/$LABEL" >/dev/null 2>&1
if [[ "${1:-}" == --uninstall ]]; then rm -f "$PLIST"; print "nightly self-test removed"; exit 0; fi
mkdir -p "${PLIST:h}"
cat > "$PLIST" <<P
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>$LABEL</string>
  <key>ProgramArguments</key><array><string>/bin/zsh</string><string>$REPO/tests/nightly.sh</string></array>
  <key>StartCalendarInterval</key><dict><key>Hour</key><integer>4</integer><key>Minute</key><integer>0</integer></dict>
  <key>StandardOutPath</key><string>/dev/null</string><key>StandardErrorPath</key><string>/dev/null</string>
  <key>ProcessType</key><string>Background</string><key>LowPriorityIO</key><true/><key>Nice</key><integer>10</integer>
</dict></plist>
P
plutil -lint "$PLIST" >/dev/null && launchctl bootstrap "gui/$(id -u)" "$PLIST" && print "nightly self-test installed: $PLIST (04:00 every night; remove with $0 --uninstall)"
