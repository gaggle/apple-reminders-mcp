#!/usr/bin/env bash
# Builds the MCP server and installs it as
# ~/Library/Application Support/apple-reminders-mcp/Reminders MCP.
#
# macOS names the file, not the Info.plist inside it, when asking for
# Reminders access and in Privacy & Security, hence the spelled-out name.
# Only MCP clients run it, by full path, so it stays off PATH.
#
# Its Info.plist, embedded in the binary (see Package.swift), gives the
# reason macOS shows when asking. Signed with an Apple Development identity
# when one is valid: the permission is then tied to the identifier and
# certificate, so reinstalls keep it. Otherwise ad-hoc, tied to these exact
# bytes, so every reinstall asks again.
# APPLE_REMINDERS_MCP_SIGN_IDENTITY overrides the choice ("-" for ad-hoc).
#
# An argument installs under another name instead, with an identifier of
# its own; scripts/test.sh uses that for a copy whose Reminders access is
# granted separately. (macOS silently denies a second copy that shares the
# identifier.)
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release --product apple-reminders-mcp
dest="$HOME/Library/Application Support/apple-reminders-mcp/${1:-Reminders MCP}"
mkdir -p "$(dirname "$dest")"
cp "$(swift build -c release --show-bin-path)/apple-reminders-mcp" "$dest"

# find-identity -v can list a revoked certificate as valid, so ask Gatekeeper.
# By fingerprint: a renewed certificate keeps the revoked one's name.
pick_identity() {
    security find-identity -v -p codesigning | awk '/"Apple Development: /{print $2}' | while read -r hash; do
        probe="$(mktemp -d)/probe"; cp /usr/bin/true "$probe"
        codesign -s "$hash" --force "$probe" 2>/dev/null && codesign --verify --strict "$probe" 2>/dev/null \
            && ! spctl -a -t exec "$probe" 2>&1 | grep -q REVOKED && { echo "$hash"; break; }
    done
}
id="${APPLE_REMINDERS_MCP_SIGN_IDENTITY:-$(pick_identity || true)}"
identifier=com.jonlauridsen.apple-reminders-mcp
[ $# -gt 0 ] && identifier="$identifier.$(echo "$1" | tr -cs 'A-Za-z0-9' '-' | tr 'A-Z' 'a-z' | sed 's/-$//')"
codesign -s "${id:--}" --force --identifier "$identifier" "$dest"
signer="$(codesign -dvv "$dest" 2>&1 | awk -F= '/^Authority=/ && !s {s = $2} END {print s}')"
echo "installed $dest (signed: ${signer:-ad-hoc})"
