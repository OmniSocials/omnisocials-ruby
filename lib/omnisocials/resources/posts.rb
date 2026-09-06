# frozen_string_literal: true

module OmniSocials
  module Resources
    # Posts resource: create, schedule, publish, update, and list posts.
    #
    # `content` is a plain String, or a per-platform Hash with a "default" key.
    # `media_ids` / `media_urls` are a flat Array, or a per-platform Hash.
    # Each entry is a plain String, or a Hash with an "alt" accessibility
    # description (max 1500 chars): `{ "url" => "https://...", "alt" => "..." }`
    # for media_urls, `{ "id" => "...", "alt" => "..." }` for media_ids. Alt
    # text is delivered to Mastodon (media description), Bluesky (embed alt),
    # X (photos/GIFs), Pinterest (pin alt text), Instagram (images), and
    # LinkedIn (images); the same entry shape works inside
    # x/bluesky/mastodon/threads `thread_parts` media.
    class Posts
      def initialize(client)
        @client = client
      end

      # GET /posts - list posts (status: draft, in_approval, scheduled, posting,
      # posted, failed, warning; in_approval = waiting for a reviewer in an
      # approval workflow).
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
      #
      # approval_workflow_id (a workflow id from client.approval_workflows.list)
      # routes the post through a saved approval workflow: it is created as
      # in_approval (approval_status "pending") instead of scheduled, the
      # approvers are notified, and it publishes at scheduled_at once the last
      # step approves. Requires scheduled_at; not allowed with publish_now.
      # Errors: 404 workflow_not_found, 400 validation_error.
      #
      # hashtag_set (set name, case-insensitive) or hashtag_set_id applies a
      # saved hashtag set once at create time; tags already in a caption are
      # skipped; Instagram's 30-hashtag cap returns error code
      # hashtag_limit_exceeded. hashtag_placement is "caption_append"
      # (default) or "first_comment"; hashtag_platforms restricts the tags to
      # a subset of channels.
      #
      # When the post targets X and its text (or any thread part) contains a
      # URL, the response includes a top-level "warnings" array (sibling of
      # "data") with a "x_url_post_credits" entry carrying credits_required
      # and credits_balance: X's link-post fee is passed through as prepaid
      # credits, debited at publish time (from 2026-08-14). Credits are
      # managed in the dashboard, not the API.
      #
      # Separately, from 2026-08-14 this call (and #update / #publish) can
      # refuse an X link post up front with a 402 and error code
      # "x_credits_insufficient" (details: credits_required, credits_balance,
      # credits_reserved) when reserving this post's cost would push the
      # company's total reserved credits past its balance. Drafts are never
      # gated, and posts scheduled to publish before 2026-08-14 are never
      # gated either.
      #
      # Threads posts can carry a location tag: pass
      # threads: { "location_id" => "..." } (an id from locations.search with
      # platform: "threads"), or threads: { "location" => { "id" => "...",
      # "name" => "..." } } to store display fields along with the id
      # (location_id wins when both are given). On a multi-post thread
      # (thread_parts) the tag is applied to part 1, and the Post's "threads"
      # block echoes a "location" object when set. Threads location tagging
      # is currently rolling out: until Meta approves the permissions it is
      # disabled on production and create/update/publish return a 400 (also a
      # 400 validation_error asking you to reconnect Threads when the
      # connection lacks the threads_location_tagging permission).
      def create(content:, channels: nil, scheduled_at: nil, media_ids: nil,
                 media_urls: nil, type: nil, source: nil, link_url: nil,
                 link_title: nil, link_description: nil, link_thumbnail_url: nil,
                 location_id: nil, collaborators: nil, user_tags: nil,
                 hashtag_set: nil, hashtag_set_id: nil, hashtag_placement: nil,
                 hashtag_platforms: nil, pinterest: nil, youtube: nil,
                 instagram: nil, facebook: nil, linkedin: nil,
                 linkedin_page: nil, tiktok: nil, x: nil, bluesky: nil,
                 mastodon: nil, threads: nil, google_business: nil,
                 linkedin_poll: nil, approval_workflow_id: nil)
        body = create_body(
          content: content, channels: channels, scheduled_at: scheduled_at,
          media_ids: media_ids, media_urls: media_urls, type: type,
          source: source, link_url: link_url, link_title: link_title,
          link_description: link_description, link_thumbnail_url: link_thumbnail_url,
          location_id: location_id, collaborators: collaborators,
          user_tags: user_tags, hashtag_set: hashtag_set,
          hashtag_set_id: hashtag_set_id, hashtag_placement: hashtag_placement,
          hashtag_platforms: hashtag_platforms, pinterest: pinterest,
          youtube: youtube, instagram: instagram, facebook: facebook,
          linkedin: linkedin, linkedin_page: linkedin_page, tiktok: tiktok,
          x: x, bluesky: bluesky, mastodon: mastodon, threads: threads,
          google_business: google_business, linkedin_poll: linkedin_poll,
          approval_workflow_id: approval_workflow_id
        )
        @client.request("POST", "/posts/create", json: body)
      end

      # POST /posts/create-and-publish - create and publish immediately.
      # See #create for the "warnings" array and the 402
      # "x_credits_insufficient" credit gate on X link posts.
      def create_and_publish(content:, channels: nil, media_ids: nil,
                             media_urls: nil, type: nil, source: nil,
                             link_url: nil, link_title: nil, link_description: nil,
                             link_thumbnail_url: nil, location_id: nil,
                             collaborators: nil, user_tags: nil,
                             hashtag_set: nil, hashtag_set_id: nil,
                             hashtag_placement: nil, hashtag_platforms: nil,
                             pinterest: nil, youtube: nil, instagram: nil,
                             facebook: nil, linkedin: nil, linkedin_page: nil,
                             tiktok: nil, x: nil, bluesky: nil, mastodon: nil,
                             threads: nil, google_business: nil,
                             linkedin_poll: nil)
        body = create_body(
          content: content, channels: channels, scheduled_at: nil,
          media_ids: media_ids, media_urls: media_urls, type: type,
          source: source, link_url: link_url, link_title: link_title,
          link_description: link_description, link_thumbnail_url: link_thumbnail_url,
          location_id: location_id, collaborators: collaborators,
          user_tags: user_tags, hashtag_set: hashtag_set,
          hashtag_set_id: hashtag_set_id, hashtag_placement: hashtag_placement,
          hashtag_platforms: hashtag_platforms, pinterest: pinterest,
          youtube: youtube, instagram: instagram, facebook: facebook,
          linkedin: linkedin, linkedin_page: linkedin_page, tiktok: tiktok,
          x: x, bluesky: bluesky, mastodon: mastodon, threads: threads,
          google_business: google_business, linkedin_poll: linkedin_poll
        )
        @client.request("POST", "/posts/create-and-publish", json: body)
      end

      # PATCH /posts/{id} - update a draft or scheduled post.
      #
      # Only top-level nils are dropped from the body, so passing e.g.
      # x: { "thread_parts" => nil } still clears an X thread (reverts the
      # post to single-tweet mode). The same applies to bluesky, mastodon
      # and threads thread parts, and to a Threads location tag:
      # threads: { "location_id" => nil } (or "location" => nil) clears it.
      #
      # See #create for the 402 "x_credits_insufficient" credit gate that
      # can also refuse an update to a scheduled X link post.
      def update(post_id, content: nil, scheduled_at: nil, channels: nil,
                 media_ids: nil, media_urls: nil, type: nil, location_id: nil,
                 collaborators: nil, user_tags: nil, pinterest: nil,
                 youtube: nil, instagram: nil, facebook: nil, linkedin: nil,
                 linkedin_page: nil, tiktok: nil, x: nil, bluesky: nil,
                 mastodon: nil, threads: nil, google_business: nil,
                 linkedin_poll: nil)
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
            "threads" => threads,
            "google_business" => google_business,
            "linkedin_poll" => linkedin_poll
          }
        )
        @client.request("PATCH", "/posts/#{post_id}", json: body)
      end

      # DELETE /posts/{id} - delete a post. Returns nil (204).
      def delete(post_id)
        @client.request("DELETE", "/posts/#{post_id}")
      end

      # POST /posts/{id}/publish - publish a draft or scheduled post now.
      # See #create for the 402 "x_credits_insufficient" credit gate that
      # can also refuse publishing a scheduled X link post.
      def publish(post_id)
        @client.request("POST", "/posts/#{post_id}/publish")
      end

      # POST /posts/{id}/retry - retry the failed platforms of a "failed" or
      # "warning" (partially failed) post, on the same post.
      #
      # Only the platforms that failed are re-published; platforms that
      # already succeeded are never posted again. Asynchronous: a 200 means
      # the retry is queued - poll `get` for the outcome. Max 3 retries per
      # platform.
      def retry(post_id)
        @client.request("POST", "/posts/#{post_id}/retry")
      end

      # POST /posts/{id}/approve - approve the current step of a post's
      # approval workflow, on behalf of the user who owns this API key. That
      # user must be a listed approver for the workflow's CURRENT step -
      # steps approve in order, so an approver on a later step gets a 403
      # "forbidden" error until earlier steps clear. Only works on a post
      # with approval_status "pending". If this is the last step, the post
      # finalizes immediately ("scheduled" or "posting"); otherwise it stays
      # "in_approval" and the next step's approvers are notified.
      def approve(post_id)
        @client.request("POST", "/posts/#{post_id}/approve")
      end

      # POST /posts/{id}/reject - reject a post's approval workflow, on
      # behalf of the user who owns this API key. Same approver requirement
      # as #approve. Unlike approval, a rejection stops the WHOLE workflow
      # immediately (not just the current step) - the post's status becomes
      # "rejected". `comment` is optional and, when given, is shown to the
      # requester and other approvers in the post's review thread.
      def reject(post_id, comment: nil)
        body = comment ? { comment: comment } : nil
        @client.request("POST", "/posts/#{post_id}/reject", json: body)
      end

      private

      def create_body(content:, channels:, scheduled_at:, media_ids:,
                      media_urls:, type:, source:, link_url:, link_title:,
                      link_description:, link_thumbnail_url:, location_id:,
                      collaborators:, user_tags:, hashtag_set:,
                      hashtag_set_id:, hashtag_placement:, hashtag_platforms:,
                      pinterest:, youtube:, instagram:, facebook:, linkedin:,
                      linkedin_page:, tiktok:, x:, bluesky:, mastodon:,
                      threads:, google_business:, linkedin_poll:,
                      approval_workflow_id: nil)
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
            "hashtag_set" => hashtag_set,
            "hashtag_set_id" => hashtag_set_id,
            "hashtag_placement" => hashtag_placement,
            "hashtag_platforms" => hashtag_platforms,
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
            "threads" => threads,
            "google_business" => google_business,
            "linkedin_poll" => linkedin_poll,
            "approval_workflow_id" => approval_workflow_id
          }
        )
      end
    end
  end
end
