#!/usr/bin/env bash
# Meshurement - maps LoRa mesh radio coverage.
# Copyright (C) 2026 Andy Brunker (Plateau Nerd)
# SPDX-License-Identifier: GPL-3.0-or-later
# Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.
#
# Prints (does not run) the commands that create Meshurement's Play UPLOAD
# key and the android/key.properties that Gradle signs release builds with.
# Nothing secret is written by this script: you run keytool yourself and
# type the passwords at its prompts.
#
# Play App Signing (mandatory for new apps): Google generates and keeps the
# APP SIGNING key that signs what users install. You keep only the UPLOAD
# key; it signs the bundles you upload so Play knows they are yours. If the
# upload key is lost or leaked, Play Console → Test and release → App
# integrity → "Request upload key reset" replaces it; the app's identity
# does not change. Still: back the .jks and its passwords up (password
# manager + an offline copy), and never commit them.
#
#   tool/android/make_keystore.sh [keystore-path]
set -euo pipefail

KEYSTORE="${1:-$HOME/.android-keys/meshurement-upload.jks}"
ALIAS="upload"
JDK_KEYTOOL="/opt/homebrew/opt/openjdk@21/bin/keytool"
KEYTOOL="keytool"
[ -x "$JDK_KEYTOOL" ] && KEYTOOL="$JDK_KEYTOOL"
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"

cat <<TXT
1. Create the upload key (asks for a keystore password and your name /
   organisation; use one password for store and key, PKCS12 has one):

   mkdir -p "$(dirname "$KEYSTORE")" && chmod 700 "$(dirname "$KEYSTORE")"
   "$KEYTOOL" -genkeypair -v \\
     -keystore "$KEYSTORE" -storetype PKCS12 \\
     -alias $ALIAS -keyalg RSA -keysize 2048 -validity 10000 \\
     -dname "CN=Andy Brunker, O=Plateau Nerd, C=US"

   (10000 days is about 27 years; Play requires validity past 2033-10-22.)

2. Write $ROOT/android/key.properties (git-ignored by android/.gitignore):

   storeFile=$KEYSTORE
   storePassword=<the password>
   keyAlias=$ALIAS
   keyPassword=<the same password>

   chmod 600 "$ROOT/android/key.properties"

3. Note the certificate fingerprint (not secret) for
   android/fastlane/.env UPLOAD_CERT_SHA256 and to compare with Play Console
   → App integrity → Upload key certificate after the first upload:

   "$KEYTOOL" -list -v -keystore "$KEYSTORE" -alias $ALIAS | grep SHA256

4. Back up $KEYSTORE and the password now (password manager + offline copy).
TXT
