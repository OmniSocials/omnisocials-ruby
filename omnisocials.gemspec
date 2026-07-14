# frozen_string_literal: true

require_relative "lib/omnisocials/version"

Gem::Specification.new do |spec|
  spec.name = "omnisocials"
  spec.version = OmniSocials::VERSION
  spec.authors = ["OmniSocials"]
  spec.email = ["hello@omnisocials.com"]

  spec.summary = "Official Ruby SDK for the OmniSocials Public API"
  spec.description = "Schedule and publish social media posts, upload media, " \
                     "and read analytics across Instagram, Facebook, LinkedIn, " \
                     "YouTube, TikTok, X, Pinterest, Bluesky, Threads, Mastodon, " \
                     "and Google Business via the OmniSocials Public API. " \
                     "Zero runtime dependencies (Net::HTTP, OpenSSL, JSON)."
  spec.homepage = "https://omnisocials.com"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.0"

  spec.metadata = {
    "homepage_uri" => spec.homepage,
    "documentation_uri" => "https://docs.omnisocials.com",
    "source_code_uri" => "https://github.com/OmniSocials/omnisocials-ruby",
    "bug_tracker_uri" => "https://github.com/OmniSocials/omnisocials-ruby/issues",
    "rubygems_mfa_required" => "true"
  }

  spec.files = Dir["lib/**/*.rb"] + %w[README.md]
  spec.require_paths = ["lib"]
end
