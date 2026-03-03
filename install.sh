#!/bin/bash
set -e

APP_SRC="$(dirname "$0")/PRNotify.app"
APP_DEST="/Applications/PRNotify.app"
PLIST_SRC="$(dirname "$0")/PRNotify/LaunchAgent/com.prnotify.plist"
PLIST_DEST="$HOME/Library/LaunchAgents/com.prnotify.plist"
LABEL="com.prnotify"

case "${1:-install}" in

  install)
    # Build if app doesn't exist
    if [ ! -f "$APP_SRC/Contents/MacOS/PRNotify" ]; then
      echo "Building..."
      make -C "$(dirname "$0")" build
    fi

    echo "Installing app..."
    cp -r "$APP_SRC" "$APP_DEST"

    echo "Installing LaunchAgent..."
    cp "$PLIST_SRC" "$PLIST_DEST"
    launchctl bootstrap gui/$(id -u) "$PLIST_DEST" 2>/dev/null || \
      launchctl kickstart gui/$(id -u)/$LABEL

    echo "Done. PRNotify is running and will start on login."
    ;;

  uninstall)
    echo "Stopping daemon..."
    launchctl bootout gui/$(id -u) "$PLIST_DEST" 2>/dev/null || true

    echo "Removing files..."
    rm -f "$PLIST_DEST"
    rm -rf "$APP_DEST"

    echo "Done. PRNotify has been removed."
    ;;

  *)
    echo "Usage: $0 [install|uninstall]"
    exit 1
    ;;

esac
