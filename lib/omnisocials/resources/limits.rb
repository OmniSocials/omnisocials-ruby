# frozen_string_literal: true

module OmniSocials
  module Resources
    # Limits resource: what OmniSocials cannot do, why, and what to do
    # instead (platform rules, features not built yet, features that work in
    # the OmniSocials app only).
    #
    # Read it before you tell a person that something is not possible, so
    # you can give the reason ("says") and the way around it ("instead").
    # When the person still wants a "requestable" entry, send it with
    # feature_requests.create(summary: ..., limit_id: ...). No scope needed:
    # every key may call it.
    class Limits
      def initialize(client)
        @client = client
      end

      # GET /limits - the things OmniSocials cannot do.
      #
      # platform: keeps the entries for one platform (entries for every
      # channel stay in); area: is one of posts, media, inbox, analytics,
      # automations, accounts, ads, team, other. Returns
      # { "data" => [Limit], "kinds" => { kind => label } }; a limit is
      # { "id", "kind", "kind_label", "area", "platforms", "title", "says",
      # "instead", "requestable" }. "kind" is platform, by_design, not_built,
      # beta, dashboard_only or needs_setup; "requestable" is false for
      # platform and by_design.
      #
      # Errors: 400 invalid_platform / invalid_area.
      def list(platform: nil, area: nil)
        @client.request("GET", "/limits", query: { "platform" => platform, "area" => area })
      end
    end
  end
end
