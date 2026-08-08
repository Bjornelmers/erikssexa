#!/bin/bash

# Exit immediately if any command fails
set -e

echo "=== STARTING ERIKSSEXA PWA BUILD ==="

# Check if Flutter SDK folder exists
if [ ! -d "flutter" ]; then
  echo "Cloning Flutter SDK (stable branch, shallow clone)..."
  git clone --depth 1 --branch stable https://github.com/flutter/flutter.git
else
  echo "Flutter SDK already exists, pulling updates..."
  cd flutter
  git pull
  cd ..
fi

# Export Flutter path
export PATH="$PATH:$(pwd)/flutter/bin"

# Print Flutter version info
flutter --version

# Enable Web support
flutter config --enable-web

# Build profile static files with readable unminified names & stack traces
echo "Building Flutter Web profile..."
flutter build web --profile

echo "=== BUILD COMPLETE! ==="
