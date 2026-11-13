#!/usr/bin/env bash
# Meshurement - maps LoRa mesh radio coverage.
# Copyright (C) 2026 Andy Brunker (Plateau Nerd)
# SPDX-License-Identifier: GPL-3.0-or-later
# Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.

# Publishes the GPL corresponding source to the public repo
# github.com/motab619/meshurement-source (the About screen's sourceCodeUrl).
# The development repo stays private: its history carries the author's
# personal email, so the public repo gets a snapshot per release, one commit
# each, authored with the GitHub no-reply address.
#
#   tool/publish_source.sh [ref] [--push]
#
# ref defaults to HEAD. Without --push it only builds and checks the
# snapshot in $PUBLIC_DIR (default ~/develop/meshurement-source) and shows
# the diff stat. Run it for the commit each App Store / Play build is made
# from.
#
# Checks (any hit stops it): gitleaks on the snapshot, every non-noreply
# author email of the private history, 12-digit AWS account ids, ARNs, AWS
# and Anthropic keys, private keys, .env / key files.
set -euo pipefail

REF=HEAD
PUSH=0
for a in "$@"; do
  case "$a" in
    --push) PUSH=1 ;;
    *) REF="$a" ;;
  esac
done

ROOT="$(git -C "$(dirname "$0")" rev-parse --show-toplevel)"
PUBLIC_DIR="${PUBLIC_DIR:-$HOME/develop/meshurement-source}"
PUBLIC_URL="https://github.com/motab619/meshurement-source.git"
NAME="Andy Brunker"
EMAIL="269048853+motab619@users.noreply.github.com"

SHA="$(git -C "$ROOT" rev-parse --short "$REF")"
VERSION="$(git -C "$ROOT" show "$REF:pubspec.yaml" | sed -n 's/^version: *//p')"
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT

echo "Exporting $REF ($SHA, version $VERSION)"
git -C "$ROOT" archive --format=tar "$REF" | tar -x -C "$STAGE"

# --- checks -------------------------------------------------------------
fail=0
hit() { echo "BLOCKED: $1"; fail=1; }

while IFS= read -r email; do
  [ -z "$email" ] && continue
  if grep -rIlF -- "$email" "$STAGE" >/dev/null; then
    hit "author email found in: $(grep -rIlF -- "$email" "$STAGE" | sed "s#$STAGE/##" | head -5 | tr '\n' ' ')"
  fi
done < <(git -C "$ROOT" log --all --format='%ae%n%ce' | sort -u | grep -viE 'noreply|^$')

patterns=(
  'arn:aws:[a-z0-9-]+:[a-z0-9-]*:[0-9]{12}'
  '(AKIA|ASIA)[A-Z0-9]{16}'
  '[Aa]ccount[^0-9]{0,20}[0-9]{12}([^0-9]|$)'
  'sk-ant-[A-Za-z0-9_-]{10,}'
  '-----BEGIN [A-Z ]*PRIVATE KEY-----'
)
for p in "${patterns[@]}"; do
  files="$(grep -rIlE --exclude-dir=proto -- "$p" "$STAGE" | sed "s#$STAGE/##" | head -5 | tr '\n' ' ')" || true
  [ -n "$files" ] && hit "pattern '$p' in: $files"
done

bad="$(cd "$STAGE" && find . -type f \( -name '.env' -o -name '*.p8' -o -name '*.p12' \
  -o -name '*.pem' -o -name '*.jks' -o -name '*.keystore' -o -name 'key.properties' \
  -o -name '*.mobileprovision' -o -name '*.sqlite' -o -name 'diag.log' \) | head -5 | tr '\n' ' ')"
[ -n "$bad" ] && hit "secret-looking files: $bad"

if command -v gitleaks >/dev/null; then
  gitleaks dir --no-banner --redact -l warn \
    --config <(printf '[extend]\nuseDefault = true\n[allowlist]\nregexTarget = "match"\nregexes = ['"'"'savedComparisonsKey'"'"', '"'"'test-app-token-0123456789'"'"']\n') \
    "$STAGE" || hit "gitleaks found something (above)"
else
  hit "gitleaks not installed (brew install gitleaks)"
fi

[ "$fail" = 0 ] || { echo "Nothing published."; exit 1; }
echo "Checks passed."

# --- snapshot commit -----------------------------------------------------
if [ ! -d "$PUBLIC_DIR/.git" ]; then
  mkdir -p "$PUBLIC_DIR"
  git -C "$PUBLIC_DIR" init -q -b main
  git -C "$PUBLIC_DIR" remote add origin "$PUBLIC_URL"
fi
git -C "$PUBLIC_DIR" config user.name "$NAME"
git -C "$PUBLIC_DIR" config user.email "$EMAIL"
rsync -a --delete --exclude .git "$STAGE/" "$PUBLIC_DIR/"
git -C "$PUBLIC_DIR" add -A
if git -C "$PUBLIC_DIR" diff --cached --quiet; then
  echo "No changes since the last snapshot."
else
  git -C "$PUBLIC_DIR" commit -q -m "Meshurement $VERSION source ($(date +%F))"
  git -C "$PUBLIC_DIR" show --stat --format='%h %s' HEAD | tail -3
fi

if [ "$PUSH" = 1 ]; then
  git -C "$PUBLIC_DIR" push -u origin main
else
  echo "Not pushed. Rerun with --push to publish $PUBLIC_DIR to $PUBLIC_URL."
fi
