# frozen_string_literal: true

module OmniSocials
  module Resources
    # Posts resource: create, schedule, publish, update, and list posts.
    #
    # `content` is a plain String, or a per-platform Hash with a "default" key.
    # `media_ids` / `media_urls` are a flat Array, or a per-platform Hash.
    class Posts
      def initialize(client)
        @client = client
      end

      # GET /posts - list posts (status: draft, scheduled, posted, failed).
      def list(status: nil, limit: nil, offset: nil)
        @client.request(
          "GET", "/posts",
          query: { "status" => status, "limit" => limit, "offset" => offset }
        )
      end

      # GET /posts/{id} - fetch a single post.
      def get(post_id)
        @client.request("GET", "/posts/#{post_id}")
      end

      # GET /posts/recent-platform - recent posts fetched live from the
      # connected platform APIs (including content published outside
      # OmniSocials). Requires the analytics:read scope.
      def recent_platform(limit: nil, platforms: nil)
        @client.request(
          "GET", "/posts/recent-platform",
          query: { "limit" => limit, "platforms" => Internal.join_list(platforms) }
        )
      end

      # POST /posts/create - create a post (draft, or scheduled when
      # scheduled_at is set).
      def create(content:, channels: nil, scheduled_at: nil, media_ids: nil,
                 media_urls: nil, type: nil, source: nil, link_url: nil,
                 link_title: nil, link_description: nil, link_thumbnail_url: nil,
                 location_id: nil, collaborators: nil, user_tags: nil,
                 pinterest: nil, youtube: nil, instagram: nil, facebook: nil,
                 linkedin: nil, linkedin_page: nil, tiktok: nil, x: nil,
                 bluesky: nil, mastodon: nil, google_business: nil)
        body = create_body(
          content: content, channels: channels, scheduled_at: scheduled_at,
          media_ids: media_ids, media_urls: media_urls, type: type,
          source: source, link_url: link_url, link_title: link_title,
          link_description: link_description, link_thumbnail_url: link_thumbnail_url,
          location_id: location_id, collaborators: collaborators,
          user_tags: user_tags, pinterest: pinterest, youtube: youtube,
          instagram: instagram, facebook: facebook, linkedin: linkedin,
          linkedin_page: linkedin_page, tiktok: tiktok, x: x, bluesky: bluesky,
          mastodon: mastodon, google_business: google_business
        )
        @client.request("POST", "/posts/create", json: body)
      end

      # POST /posts/create-and-publish - create and publish immediately.
      def create_and_publish(content:, channels: nil, media_ids: nil,
                             media_urls: nil, type: nil, source: nil,
                             link_url: nil, link_title: nil, link_description: nil,
                             link_thumbnail_url: nil, location_id: nil,
                             collaborators: nil, user_tags: nil, pinterest: nil,
                             youtube: nil, instagram: nil, facebook: nil,
                             linkedin: nil, linkedin_page: nil, tiktok: nil,
                             x: nil, bluesky: nil, mastodon: nil,
                             google_business: nil)
        body = create_body(
          content: content, channels: channels, scheduled_at: nil,
          media_ids: media_ids, media_urls: media_urls, type: type,
          source: source, link_url: link_url, link_title: link_title,
          link_description: link_description, link_thumbnail_url: link_thumbnail_url,
          location_id: location_id, collaborators: collaborators,
          user_tags: user_tags, pinterest: pinterest, youtube: youtube,
          instagram: instagram, facebook: facebook, linkedin: linkedin,
          linkedin_page: linkedin_page, tiktok: tiktok, x: x, bluesky: bluesky,
          mastodon: mastodon, google_business: google_business
        )
        @client.request("POST", "/posts/create-and-publish", json: body)
      end

      # PATCH /posts/{id} - update a draft or scheduled post.
      #
      # Only top-level nils are dropped from the body, so passing e.g.
      # x: { "thread_parts" => nil } still clears an X thread (reverts the
      # post to single-tweet mode). The same applies to bluesky and mastodon
      # thread parts.
      def update(post_id, content: nil, scheduled_at: nil, channels: nil,
                 media_ids: nil, media_urls: nil, type: nil, location_id: nil,
                 collaborators: nil, user_tags: nil, pinterest: nil,
                 youtube: nil, instagram: nil, facebook: nil, linkedin: nil,
                 linkedin_page: nil, tiktok: nil, x: nil, bluesky: nil,
                 mastodon: nil, google_business: nil)
        body = Internal.drop_nil(
          {
            "content" => content,
            "scheduled_at" => scheduled_at,
            "channels" => channels,
            "media_ids" => media_ids,
            "media_urls" => media_urls,
            "type" => type,
            "location_id" => location_id,
            "collaborators" => collaborators,
            "user_tags" => user_tags,
            "pinterest" => pinterest,
            "youtube" => youtube,
            "instagram" => instagram,
            "facebook" => facebook,
            "linkedin" => linkedin,
            "linkedin_page" => linkedin_page,
            "tiktok" => tiktok,
            "x" => x,
            "bluesky" => bluesky,
            "mastodon" => mastodon,
            "google_business" => google_business
          }
        )
        @client.request("PATCH", "/posts/#{post_id}", json: body)
      end

      # DELETE /posts/{id} - delete a post. Returns nil (204).
      def delete(post_id)
        @client.request("DELETE", "/posts/#{post_id}")
      end

      # POST /posts/{id}/publish - publish a draft or scheduled post now.
      def publish(post_id)
        @client.request("POST", "/posts/#{post_id}/publish")
      end

      private

      def create_body(content:, channels:, scheduled_at:, media_ids:,
                      media_urls:, type:, source:, link_url:, link_title:,
                      link_description:, link_thumbnail_url:, location_id:,
                      collaborators:, user_tags:, pinterest:, youtube:,
                      instagram:, facebook:, linkedin:, linkedin_page:,
                      tiktok:, x:, bluesky:, mastodon:, google_business:)
        Internal.drop_nil(
          {
            "content" => content,
            "channels" => channels,
            "scheduled_at" => scheduled_at,
            "media_ids" => media_ids,
            "media_urls" => media_urls,
            "type" => type,
            "source" => source,
            "link_url" => link_url,
            "link_title" => link_title,
            "link_description" => link_description,
            "link_thumbnail_url" => link_thumbnail_url,
            "location_id" => location_id,
            "collaborators" => collaborators,
            "user_tags" => user_tags,
            "pinterest" => pinterest,
            "youtube" => youtube,
            "instagram" => instagram,
            "facebook" => facebook,
            "linkedin" => linkedin,
            "linkedin_page" => linkedin_page,
            "tiktok" => tiktok,
            "x" => x,
            "bluesky" => bluesky,
            "mastodon" => mastodon,
            "google_business" => google_business
          }
        )
      end
    end
  end
end
