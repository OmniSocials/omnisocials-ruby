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
        @client.request("GET", "/analytics/posts/#{Internal.path_segment(post_id)}")
      end

      # POST /analytics/posts/{id}/refresh - "Update now": read the X numbers
      # of one published post now, outside its check schedule.
      #
      # X bills every read, so it costs half a credit per tweet (each part
      # of a thread counts, plus half a credit for a video or GIF), and
      # nothing when the post was already read today (UTC). OmniSocials
      # Connect accounts pay on the partner's own X app. At most 5 reads of
      # a post a UTC day. Needs analytics:read. Returns { "data" =>
      # { "post_id", "tweets" => [{ "id", "metrics", "read_at" }],
      # "credits_used", "read_at" } }. Because it can cost credits it is
      # retried only after a 429, never after a 5xx, a timeout or a lost
      # connection. Errors: 402 insufficient_credits, 404 not_found, 409
      # refresh_not_available (no published X tweet), 429 refresh_limit,
      # 502 refresh_failed (nothing charged).
      def refresh_post(post_id)
        @client.request(
          "POST", "/analytics/posts/#{Internal.path_segment(post_id)}/refresh",
          retry_on: :rate_limit
        )
      end

      # GET /analytics/posts?ids=a,b,c - bulk metrics for up to 100 posts in
      # one request. `ids` is an Array of post ids (or an already-joined
      # comma-separated String). Each entry also carries "tags" (the post's
      # tags) and "trial_reel" ({ "strategy" => "MANUAL" | "SS_PERFORMANCE" }
      # for an Instagram Trial Reel, else nil).
      def posts(ids)
        @client.request(
          "GET", "/analytics/posts",
          query: { "ids" => Internal.join_list(ids) }
        )
      end

      # GET /analytics/overview - workspace-wide analytics overview.
      #
      # tag (a tag id or name, or an Array of them: any of them) keeps the
      # post numbers of the posts with that tag; account numbers stay those
      # of the whole account. An unknown tag is a 404 tag_not_found.
      def overview(period: nil, start_date: nil, end_date: nil, tag: nil)
        @client.request(
          "GET", "/analytics/overview",
          query: {
            "period" => period, "start_date" => start_date, "end_date" => end_date,
            "tag" => Tags.tag_query(tag)
          }
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
      # derived from the workspace's own engagement history. The response has
      # no "data" wrapper: "platform", "timezone", "basis", "grid" and
      # "recommendations" sit at the top level.
      def best_times(platform:, timezone: nil)
        @client.request(
          "GET", "/analytics/best-times",
          query: { "platform" => platform, "timezone" => timezone }
        )
      end

      # GET /analytics/tags - how each tag did against your normal, for the
      # published posts in a period (default the last 90 days).
      #
      # Returns { "data" => { "period", "platform", "min_posts", "tags",
      # "untagged", "normals" } }. Each entry of "tags" is { "tag", "posts",
      # "measured", "median_impressions", "engagement_rate" (percent),
      # "vs_normal" (fraction: 0.38 = 38% above your normal), "best_channel",
      # "enough_posts" }, comparable tags first, best first; "untagged" has
      # the same numbers for the posts without a tag, "normals" the median
      # impressions per channel. platform keeps one channel's numbers;
      # min_posts (1 to 50, default 5) is the measured posts a tag needs
      # before "enough_posts" is true.
      def tags(start_date: nil, end_date: nil, platform: nil, min_posts: nil)
        @client.request(
          "GET", "/analytics/tags",
          query: {
            "start_date" => start_date, "end_date" => end_date,
            "platform" => platform, "min_posts" => min_posts
          }
        )
      end
    end
  end
end
