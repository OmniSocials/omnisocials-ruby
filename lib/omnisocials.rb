# frozen_string_literal: true

# Official Ruby SDK for the OmniSocials Public API.
#
# Docs: https://docs.omnisocials.com
#
#   require "omnisocials"
#
#   client = OmniSocials::Client.new  # reads OMNISOCIALS_API_KEY from env
#   post = client.posts.create(
#     content: "Hello from Ruby",
#     channels: ["instagram", "linkedin"]
#   )

require_relative "omnisocials/version"
require_relative "omnisocials/errors"
require_relative "omnisocials/internal"
require_relative "omnisocials/webhooks"
require_relative "omnisocials/resources/posts"
require_relative "omnisocials/resources/media"
require_relative "omnisocials/resources/folders"
require_relative "omnisocials/resources/accounts"
require_relative "omnisocials/resources/analytics"
require_relative "omnisocials/resources/locations"
require_relative "omnisocials/resources/webhooks"
require_relative "omnisocials/client"

module OmniSocials
end
