# frozen_string_literal: true

module OmniSocials
  module Resources
    # Analytics resource: post stats, account stats, overview, and best times.
    class Analytics
      def initialize(client)
        @client = client
      end

      # GET /analytics/posts/{id} - latest per-platform metrics for one post.
      def post(post_id)
        @client.request("GET", "/analytics/posts/#{post_id}")
      end

      # GET /analytics/posts?ids=a,b,c - bulk metrics for up to 100 posts in
      # one request. `ids` is an Array of post ids (or an already-joined
      # comma-separated String).
      def posts(ids)
        @client.request(
          "GET", "/analytics/posts",
          query: { "ids" => Internal.join_list(ids) }
        )
      end

      # GET /analytics/overview - workspace-wide analytics overview.
      def overview(period: nil, start_date: nil, end_date: nil)
        @client.request(
          "GET", "/analytics/overview",
          query: { "period" => period, "start_date" => start_date, "end_date" => end_date }
        )
      end

      # GET /analytics/accounts - account-level stats (followers etc.).
      def accounts(platform: nil, date: nil)
        @client.request(
          "GET", "/analytics/accounts",
          query: { "platform" => platform, "date" => date }
        )
      end

      # GET /analytics/best-times - best times to post for a platform,
      # derived from the workspace's own engagement history.
      def best_times(platform:, timezone: nil)
        @client.request(
          "GET", "/analytics/best-times",
          query: { "platform" => platform, "timezone" => timezone }
        )
      end
    end
  end
end
