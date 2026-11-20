#!/bin/zsh
# Builds Lookdown.app with its Quick Look extension. Needs only the Command Line Tools (no Xcode).
#
#   ./build.sh               build for this Mac, install to ~/Applications, register
#   ./build.sh --no-install  build only, into build/Lookdown.app
#   ./build.sh --package     build for Apple silicon and Intel, then pack the app with install
#                            instructions into dist/Lookdown <version>.dmg to send to someone
#
# --package signs with a "Developer ID Application" certificate when the keychain has one, and
# then notarizes with the notarytool keychain profile named by NOTARY_PROFILE (default "notary").
# Create the profile once, in the login keychain file:
#   xcrun notarytool store-credentials notary --apple-id <Apple ID> --team-id <Team ID> \
#     --keychain ~/Library/Keychains/login.keychain-db
# Without a Developer ID certificate the package is signed ad hoc, and recipients must approve
# the app under Privacy & Security.
set -e
cd "${0:A:h}"
mkdir -p build

MODE=install
case "$1" in
  "") ;;
  --no-install) MODE=build ;;
  --package) MODE=package ;;
  *) echo "usage: $0 [--no-install | --package]" >&2; exit 2 ;;
esac

APP=build/Lookdown.app
EXT=$APP/Contents/PlugIns/LookdownPreview.appex
LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
SHORT_VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" Info/App-Info.plist)
VERSION=$(date +%Y%m%d.%H%M%S)
FLAGS=(-O -swift-version 5 -parse-as-library)
ARCHS=(arm64)
[[ $MODE == package ]] && ARCHS=(arm64 x86_64)

rm -rf $APP build/obj
mkdir -p build/obj $APP/Contents/MacOS $APP/Contents/Resources $EXT/Contents/MacOS $EXT/Contents/Resources

# compile <output> <swiftc args…>: builds each architecture, then merges them with lipo.
compile() {
  local out=$1; shift
  local slices=()
  for arch in $ARCHS; do
    swiftc $FLAGS -target $arch-apple-macos14 "$@" -o build/obj/${out:t}-$arch
    slices+=(build/obj/${out:t}-$arch)
  done
  lipo -create $slices -output $out
}

copy_resources() {
  cp Resources/lookdown.js Resources/lookdown.css Resources/themes.css "$1/"
  rsync -a --exclude licenses Resources/vendor/ "$1/vendor/"
}

# The Quick Look extension. Its entry point is NSExtensionMain, so no main.swift.
compile $EXT/Contents/MacOS/LookdownPreview -application-extension -module-name LookdownPreview \
  Sources/Shared/*.swift Sources/Preview/*.swift -Xlinker -e -Xlinker _NSExtensionMain
cp Info/Preview-Info.plist $EXT/Contents/Info.plist
copy_resources $EXT/Contents/Resources

# The app (settings window with a live preview, plus --render/--snapshot for testing).
compile $APP/Contents/MacOS/Lookdown -module-name Lookdown Sources/Shared/*.swift Sources/App/*.swift
cp Info/App-Info.plist $APP/Contents/Info.plist
copy_resources $APP/Contents/Resources
cp Resources/sample.md $APP/Contents/Resources/
cp -R Resources/vendor/licenses $APP/Contents/Resources/licenses
cp LICENSE $APP/Contents/Resources/LICENSE   # Lookdown's own license (GPL v3 or later)

if [[ ! -f build/AppIcon.icns || Tools/make_icon.swift -nt build/AppIcon.icns ]]; then
  ICONSET=build/AppIcon.iconset
  rm -rf $ICONSET && mkdir -p $ICONSET
  swift Tools/make_icon.swift build/icon.png
  for s in 16 32 128 256 512; do
    sips -z $s $s build/icon.png --out $ICONSET/icon_${s}x${s}.png >/dev/null
    sips -z $((s*2)) $((s*2)) build/icon.png --out $ICONSET/icon_${s}x${s}@2x.png >/dev/null
  done
  iconutil -c icns $ICONSET -o build/AppIcon.icns
fi
cp build/AppIcon.icns $APP/Contents/Resources/AppIcon.icns

for plist in $APP/Contents/Info.plist $EXT/Contents/Info.plist; do
  /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $VERSION" $plist
done

# Sign the extension (sandboxed) first, then the app.
# - Developer ID whenever the keychain has it, for local builds too. macOS ties the extension's
#   sandbox container (~/Library/Containers/com.zachburkhart.Lookdown.Preview) to the signer that
#   created it and won't let a differently signed extension in: it launches but never renders.
#   One signer everywhere keeps local and notarized builds interchangeable.
# - Packages get a secure timestamp and notarization on top. Without Developer ID, local builds
#   use the Apple Development certificate and packages are signed ad hoc (macOS asks recipients to
#   approve the app either way, and an ad-hoc signature doesn't carry the account's email).
IDENTITIES=$(security find-identity -v -p codesigning)
DEVELOPER_ID=$(print -r -- "$IDENTITIES" | sed -n 's/.*"\(Developer ID Application: .*\)"$/\1/p' | head -1)
NOTARY_PROFILE=${NOTARY_PROFILE:-notary}
# The profile lives in the login keychain file. Without --keychain, notarytool keeps profiles in
# the data protection keychain, where a saved one once vanished within minutes.
NOTARY_KEYCHAIN=${NOTARY_KEYCHAIN:-$HOME/Library/Keychains/login.keychain-db}
NOTARY_ARGS=(--keychain-profile "$NOTARY_PROFILE" --keychain "$NOTARY_KEYCHAIN")
IDENTITY=-
SIGN_FLAGS=(--options runtime --timestamp=none)   # hardened runtime everywhere, so local builds behave like notarized ones
if [[ -n $DEVELOPER_ID ]]; then
  IDENTITY=$DEVELOPER_ID
  [[ $MODE == package ]] && SIGN_FLAGS=(--options runtime --timestamp)
elif [[ $MODE != package ]] && print -r -- "$IDENTITIES" | grep -q "Apple Development"; then
  IDENTITY="Apple Development"
fi
codesign --force --sign "$IDENTITY" $SIGN_FLAGS --entitlements Info/Preview.entitlements $EXT
codesign --force --sign "$IDENTITY" $SIGN_FLAGS --entitlements Info/App.entitlements $APP
codesign --verify --strict $APP

# notarize <file>: submits to Apple's notary service and waits; prints the log and stops on failure.
notarize() {
  echo "Notarizing ${1:t} (usually a few minutes)…"
  local out id
  out=$(xcrun notarytool submit "$1" $NOTARY_ARGS --wait 2>&1) || true
  id=$(print -r -- "$out" | sed -n 's/^ *id: //p' | head -1)
  if ! print -r -- "$out" | grep -q "status: Accepted"; then
    print -r -- "$out" >&2
    [[ -n $id ]] && xcrun notarytool log "$id" $NOTARY_ARGS >&2
    echo "Notarization of ${1:t} failed." >&2
    exit 1
  fi
  echo "Accepted ($id)"
}

case $MODE in
build)
  echo "Built $APP ($VERSION)"
  ;;

package)
  NOTARIZE=0
  README="Packaging/Read Me (not notarized).md"
  if [[ -n $DEVELOPER_ID ]]; then
    # A brand-new account answers "No submission history.", so look for an error rather than
    # trusting the exit code.
    if ! xcrun notarytool history $NOTARY_ARGS 2>&1 | grep -q "^Error"; then
      NOTARIZE=1
      README="Packaging/Read Me.md"
    else
      echo "warning: no working notarytool profile \"$NOTARY_PROFILE\" in $NOTARY_KEYCHAIN, so the app is signed but not notarized" >&2
    fi
  fi

  if (( NOTARIZE )); then
    ditto -c -k --keepParent $APP build/Lookdown-notarize.zip
    notarize build/Lookdown-notarize.zip
    rm -f build/Lookdown-notarize.zip
    xcrun stapler staple -q $APP
  fi

  STAGE=build/dmg
  DMG="dist/Lookdown $SHORT_VERSION.dmg"
  rm -rf $STAGE && mkdir -p $STAGE dist
  ditto $APP $STAGE/Lookdown.app
  ln -s /Applications $STAGE/Applications
  cp "$README" "$STAGE/Read Me.md"
  rm -f "$DMG"
  hdiutil create -volname "Lookdown" -srcfolder $STAGE -fs HFS+ -format UDZO -ov "$DMG" >/dev/null
  # Drop the build copies so this Mac keeps using the installed app's extension.
  $LSREGISTER -u $APP >/dev/null 2>&1 || true
  $LSREGISTER -u $STAGE/Lookdown.app >/dev/null 2>&1 || true
  rm -rf $APP $STAGE

  if [[ -n $DEVELOPER_ID ]]; then
    codesign --sign "$DEVELOPER_ID" --timestamp "$DMG"
  fi
  if (( NOTARIZE )); then
    notarize "$DMG"
    xcrun stapler staple -q "$DMG"
    spctl --assess --type open --context context:primary-signature -v "$DMG"
    echo "Packaged $DMG: signed with $DEVELOPER_ID, notarized and stapled ($VERSION)"
  else
    echo "Packaged $DMG: NOT notarized; recipients approve it under Privacy & Security ($VERSION)"
  fi
  ;;

install)
  DEST=~/Applications/Lookdown.app
  mkdir -p ~/Applications
  pkill -x LookdownPreview 2>/dev/null || true
  rm -rf $DEST
  ditto $APP $DEST
  # Keep a single copy registered, so Quick Look can't pick up a stale build.
  $LSREGISTER -u $APP >/dev/null 2>&1 || true
  rm -rf $APP
  $LSREGISTER -f -R -trusted $DEST
  pluginkit -a $DEST/Contents/PlugIns/LookdownPreview.appex
  qlmanage -r >/dev/null 2>&1 || true
  echo "Installed $DEST ($VERSION)"
  ;;
esac
