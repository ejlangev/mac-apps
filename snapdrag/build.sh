#!/bin/zsh
# Build Snapdrag.
#   ./build.sh           build the development version only
#   ./build.sh run       build the development version, quit any running copy, launch it
#   ./build.sh install   build the release version, put it in /Applications,
#                        set it to open at login, and launch it
set -e
cd "$(dirname "$0")"

# The project file holds no Apple developer team ID, so it can live in a public repository.
# Use $DEVELOPMENT_TEAM if set; otherwise read the team from the "Apple Development"
# signing certificate in the keychain.
TEAM="${DEVELOPMENT_TEAM:-$(security find-certificate -c "Apple Development" -p 2>/dev/null \
  | openssl x509 -noout -subject -nameopt multiline 2>/dev/null \
  | awk -F'= ' '/organizationalUnitName/ {print $2; exit}')}"
if [[ -z "$TEAM" ]]; then
  echo "No Apple Development certificate found. Add your Apple ID in Xcode > Settings > Accounts," >&2
  echo "create an Apple Development certificate, or set DEVELOPMENT_TEAM yourself." >&2
  exit 1
fi

if [[ "$1" == "install" ]]; then
  xcodebuild -project Snapdrag.xcodeproj -scheme Snapdrag -configuration Release \
    -derivedDataPath build -quiet build DEVELOPMENT_TEAM="$TEAM"
  pkill -x Snapdrag 2>/dev/null || true
  sleep 0.5
  rm -rf "/Applications/Snapdrag.app"
  ditto "build/Build/Products/Release/Snapdrag.app" "/Applications/Snapdrag.app"
  echo "Installed /Applications/Snapdrag.app"
  "/Applications/Snapdrag.app/Contents/MacOS/Snapdrag" --register-login-item
  open "/Applications/Snapdrag.app"
  echo "Launched"
  exit 0
fi

xcodebuild -project Snapdrag.xcodeproj -scheme Snapdrag -configuration Debug \
  -derivedDataPath build -quiet build DEVELOPMENT_TEAM="$TEAM"

APP="build/Build/Products/Debug/Snapdrag.app"
echo "Built $APP"

if [[ "$1" == "run" ]]; then
  pkill -x Snapdrag 2>/dev/null || true
  sleep 0.3
  open "$APP"
  echo "Launched"
fi
