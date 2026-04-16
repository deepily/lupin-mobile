#!/bin/bash
# Convenience script to use local Flutter installation
# Usage: ./flutter.sh [flutter commands]
# Example: ./flutter.sh doctor
# Example: ./flutter.sh pub get
# Example: ./flutter.sh run

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FLUTTER_BIN="$SCRIPT_DIR/flutter/bin/flutter"

if [ ! -f "$FLUTTER_BIN" ]; then
    echo "Error: Flutter not found at $FLUTTER_BIN"
    echo "Please run the setup script to install Flutter locally"
    exit 1
fi

# Pass all arguments to Flutter
"$FLUTTER_BIN" "$@"