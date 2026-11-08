# frozen_string_literal: true

module OmniSocials
  module Resources
    # Credits resource: the organisation's credit balance and what X
    # statistics cost. Top-ups are made in the OmniSocials app (Settings ->
    # Organisation -> Billing -> Credits).
    class Credits
      def initialize(client)
        @client = client
      end

      # GET /credits - the balance and the X statistics overview.
      #
      # Returns { "data" => { "balance", "auto_refill" => { "enabled" },
      # "this_month" => { reason => credits }, "x_statistics" => { "state",
      # "paused_at", "charging" => { "active", "from" }, "prices" =>
      # { "post_read", "media_read", "follower_read" },
      # "total_credits_month", "this_month" => { "post_reads",
      # "media_reads", "follower_reads", "refreshes", "credits" },
      # "accounts" => [{ "account_id", "workspace_id", "handle", "posts",
      # "followers", "tweets_30d", "credits_month" }] } } }. 1 credit = EUR
      # 0.01. Needs the opt-in scope credits:read and billing rights
      # (manage_billing) for the key's creator; OmniSocials Connect keys get
      # 403 not_available_for_connect.
      def get
        @client.request("GET", "/credits")
      end
    end
  end
end
