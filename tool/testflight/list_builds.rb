# Meshurement - maps LoRa mesh radio coverage.
# Copyright (C) 2026 Andy Brunker (Plateau Nerd)
# SPDX-License-Identifier: GPL-3.0-or-later
# Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.
require "spaceship"
Spaceship::ConnectAPI.token = Spaceship::ConnectAPI::Token.create(
  key_id: ENV.fetch("ASC_KEY_ID"), issuer_id: ENV.fetch("ASC_ISSUER_ID"),
  filepath: File.expand_path(ENV.fetch("ASC_KEY_PATH")))
app = Spaceship::ConnectAPI::App.find("com.andybrunker.meshAnalyzer")
Spaceship::ConnectAPI::Build.all(app_id: app.id, sort: "-uploadedDate", includes: "preReleaseVersion,buildBetaDetail", limit: 4).each do |b|
  d = b.build_beta_detail
  puts "build #{b.version} v#{b.pre_release_version&.version} #{b.processing_state} uploaded #{b.uploaded_date} ext=#{d&.external_build_state} int=#{d&.internal_build_state}"
end
Spaceship::ConnectAPI.get_beta_groups(filter: {app: app.id}).each { |g| puts "group #{g.name} internal=#{g.is_internal_group}" }
