# Meshurement - maps LoRa mesh radio coverage.
# Copyright (C) 2026 Andy Brunker (Plateau Nerd)
# SPDX-License-Identifier: GPL-3.0-or-later
# Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.
# Usage: ruby build_notes.rb <build_number> "<what to test>"
# Waits for the build to finish processing, then sets its TestFlight
# "What to Test" notes (en-US). Read-only apart from that one localization.
require "spaceship"
build_number, notes = ARGV[0], ARGV[1]
abort "usage: build_notes.rb <build_number> <notes>" unless build_number && notes
Spaceship::ConnectAPI.token = Spaceship::ConnectAPI::Token.create(
  key_id: ENV.fetch("ASC_KEY_ID"), issuer_id: ENV.fetch("ASC_ISSUER_ID"),
  filepath: File.expand_path(ENV.fetch("ASC_KEY_PATH")))
app = Spaceship::ConnectAPI::App.find("com.andybrunker.meshAnalyzer")
build = nil
60.times do
  builds = Spaceship::ConnectAPI::Build.all(app_id: app.id, sort: "-uploadedDate",
    includes: "preReleaseVersion,buildBetaDetail", limit: 10)
  build = builds.find { |b| b.version.to_s == build_number.to_s }
  if build && build.processing_state == "VALID"
    break
  end
  puts "build #{build_number}: #{build ? build.processing_state : 'not uploaded yet'}; waiting 30 s"
  sleep 30
end
abort "build #{build_number} never became VALID" unless build && build.processing_state == "VALID"
puts "build #{build.version} (#{build.pre_release_version.version}) uploaded #{build.uploaded_date} #{build.processing_state}"
existing = Spaceship::ConnectAPI.get_beta_build_localizations(filter: {build: build.id}).first
if existing
  Spaceship::ConnectAPI.patch_beta_build_localizations(localization_id: existing.id, attributes: {whatsNew: notes})
  puts "notes updated: #{notes}"
else
  Spaceship::ConnectAPI.post_beta_build_localizations(build_id: build.id, attributes: {whatsNew: notes, locale: "en-US"})
  puts "notes set: #{notes}"
end
ext = build.build_beta_detail
puts "external state: #{ext&.external_build_state}  internal state: #{ext&.internal_build_state}"
