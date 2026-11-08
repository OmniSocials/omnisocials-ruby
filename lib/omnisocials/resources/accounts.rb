# frozen_string_literal: true

module OmniSocials
  module Resources
    # Accounts resource: connected social accounts for the API key's workspace.
    class Accounts
      def initialize(client)
        @client = client
      end

      # GET /accounts - list connected social accounts.
      #
      # The response also carries workspace_id and workspace_name for the
      # workspace the API key belongs to.
      def list
        @client.request("GET", "/accounts")
      end

      # GET /accounts/{id} - fetch a single connected account.
      #
      # An X account also carries "x_statistics": posts, followers,
      # post_schedule, source, billing, state and paused_reason (nil when it
      # could not be read).
      def get(account_id)
        @client.request("GET", "/accounts/#{Internal.path_segment(account_id)}")
      end

      # PATCH /accounts/{id} - change how often the X statistics of an X
      # account are read.
      #
      # `x_statistics` is a Hash with one key or more of posts, followers and
      # post_schedule; only the keys you give are sent. posts is "full" (5
      # checks), "light" (2 checks) or "off"; followers is "daily", "weekly"
      # or "off". X bills every read and OmniSocials passes X's price on as
      # credits (half a credit per post check, plus half for a video or GIF,
      # 1 credit per follower count). Needs the opt-in scope accounts:write
      # and billing rights (manage_billing) for the key's creator.
      # OmniSocials Connect keys (the partner's own X app pays) also take
      # posts: "custom" with post_schedule ({ at: ["1h", "1d"],
      # then_every: "7d", until: "90d" }), followers "hourly" / "6h", and
      # x_statistics: nil, which is sent as null: follow the customer's
      # setting again.
      #
      # Returns { "data" => account } with the new "x_statistics". Errors:
      # 400 validation_error / schedule_invalid / not_supported (not an X
      # account), 403 forbidden, 404 not_found.
      def update(account_id, x_statistics:)
        @client.request(
          "PATCH", "/accounts/#{Internal.path_segment(account_id)}",
          json: { "x_statistics" => x_statistics.nil? ? nil : x_statistics.to_h }
        )
      end
    end
  end
end
