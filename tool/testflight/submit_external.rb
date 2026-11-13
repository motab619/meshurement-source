# Meshurement - maps LoRa mesh radio coverage.
# Copyright (C) 2026 Andy Brunker (Plateau Nerd)
# SPDX-License-Identifier: GPL-3.0-or-later
# Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.
# Usage: ruby submit_external.rb <build_number>
# Submits the build for Beta App Review and adds it to the external
# "Beta Testers" group (internal testers already have it).
require "spaceship"
build_number = ARGV[0] or abort "usage: submit_external.rb <build_number>"
Spaceship::ConnectAPI.token = Spaceship::ConnectAPI::Token.create(
  key_id: ENV.fetch("ASC_KEY_ID"), issuer_id: ENV.fetch("ASC_ISSUER_ID"),
  filepath: File.expand_path(ENV.fetch("ASC_KEY_PATH")))
app = Spaceship::ConnectAPI::App.find("com.andybrunker.meshAnalyzer")
build = Spaceship::ConnectAPI::Build.all(app_id: app.id, sort: "-uploadedDate",
  includes: "preReleaseVersion,buildBetaDetail", limit: 10).find { |b| b.version.to_s == build_number }
abort "build #{build_number} not found" unless build
abort "build #{build_number} is #{build.processing_state}, not VALID" unless build.processing_state == "VALID"
state = build.build_beta_detail&.external_build_state
puts "build #{build.version}: external state #{state}"
if state == "READY_FOR_BETA_SUBMISSION"
  Spaceship::ConnectAPI.post_beta_app_review_submissions(build_id: build.id)
  puts "submitted for Beta App Review"
else
  puts "not submitting (state #{state})"
end
group = Spaceship::ConnectAPI.get_beta_groups(filter: {app: app.id}).find { |g| g.name == "Beta Testers" }
abort "no Beta Testers group" unless group
build.add_beta_groups(beta_groups: [group])
puts "added to group #{group.name}"
