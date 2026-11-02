#!/bin/zsh
set -euo pipefail

if [[ $# -ne 1 || ! -d "$1" ]]; then
  print -u2 'Usage: scripts/verify-public-release.sh /path/to/Clear\ Stuff.app'
  exit 2
fi

app_path=$1
if ! signature_details=$(codesign -dv --verbose=4 "$app_path" 2>&1); then
  print -u2 'Release gate failed: app has no valid code signature.'
  exit 1
fi
if [[ "$signature_details" != *'Authority=Developer ID Application:'* ]]; then
  print -u2 'Release gate failed: app is not signed with Developer ID Application.'
  exit 1
fi
if [[ ! "$signature_details" =~ 'flags=.*runtime' ]]; then
  print -u2 'Release gate failed: hardened runtime is missing.'
  exit 1
fi

codesign --verify --deep --strict --verbose=2 "$app_path"
xcrun stapler validate "$app_path"
spctl --assess --type execute --verbose=4 "$app_path"
print 'Developer ID signature, hardened runtime, stapled notarization, and Gatekeeper assessment passed.'
