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
      # draft: true with scheduled_at stores a planned draft: the post is
      # "draft" and keeps that time, shows on the dashboard calendar at that
      # slot with a dashed outline, and the scheduler never publishes it. A
      # person schedules it from the composer, or you do with #update and
      # draft: false. Use it when an agent proposes a slot that a human
      # should confirm. Not allowed with publish_now or approval_workflow_id
      # (400 validation_error). Without scheduled_at it changes nothing.
      #
      # media_fit is the image fit per channel for feed images whose ratio is
      # outside what a channel shows uncropped: a Hash of platform id
      # ("instagram", "pinterest", ...) to "auto", "crop" or "keep". auto
      # (default): Instagram crops a tall or wide image to 4:5 / 1.91:1 around
      # the subject (Instagram cuts it to that window anyway and Meta cannot
      # boost a feed post outside it); Pinterest keeps a Pin taller than 2:3
      # and reports it. crop / keep force it per channel. Every decision comes
      # back in the same "warnings" array with code "image_fit" (action is
      # "cropped", "kept" or "crop_failed", with platform, media_url, ratio,
      # target and crop_url).
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
      #
      # Threads posts can carry a topic: threads: { "topic_tag" => "Build in
      # public" } (1 to 50 characters, no period and no ampersand; a topic can
      # hold spaces). On a multi-post thread it goes on part 1; on update
      # "topic_tag" => nil removes it.
      #
      # Pinterest posts can tag products: pass
      # pinterest: { "board_id" => "...", "product_tags" => [...] } with up
      # to 24 product Pins of the connected Pinterest account, each as a Pin
      # id String (see pinterest.list_products) or a Pin link. Products of
      # other merchants cannot be tagged. The tags are added right after the
      # Pin is published; a product Pinterest refuses never fails the post,
      # and the Post's "pinterest" block then carries "product_tags_result"
      # (requested, tagged, skipped, error). More than 24 entries or an
      # invalid entry raises a 400 validation_error.
      #
      # telegram holds the Telegram options (the connected channel or group,
      # posted by the OmniSocials bot): "silent", "link_preview", "pin",
      # "protect_content", "spoiler", "caption_above_media" (booleans), up to
      # 3 "buttons" ({ "text" => ..., "url" => ... }, not on an album or a
      # poll), a native "poll" ({ "options" => 2 to 12 of up to 100
      # characters, "open_period" => 5 to 2628000 seconds, "multiple" => true
      # }; the post text is the question, max 300 characters, no media) and
      # "first_comment" (a reply under the post). Text up to 4,096
      # characters; with media, text over 1,024 characters is sent as a reply
      # under the media. No Stories. On #update every key merges into the
      # stored options. Once sent, the Post's "telegram" block carries
      # "result" (message ids and links).
      #
      # discord holds the Discord options (one Discord channel, posted
      # through its incoming webhook with the webhook's name and picture):
      # "silent", "link_preview" (default on), "allow_mentions" (default off:
      # @everyone, @here, role and user mentions show as text and ping
      # nobody), "spoiler" (booleans), "thread_name" (the post title in a
      # forum or media channel, 1 to 100 characters; on a text channel the
      # post goes out without it), up to 5 "buttons" ({ "text" => 1 to 80 characters, "url" =>
      # https:// or http:// }, one row, not with a poll) and a native "poll"
      # ({ "options" => 2 to 10 of up to 55 characters, "duration_hours" =>
      # 1 to 768 (default 24), "multiple" => true }; the post text is the
      # question, max 300 characters, no media and no buttons). Text up to
      # 2,000 characters; up to 10 images, GIFs and videos per message, a
      # video or GIF over 20 MB is sent as a link in the text. No Stories.
      # On #update every key merges into the stored options, a key set to
      # nil removes it and discord: nil removes every option. Once sent, the
      # Post's "discord" block carries "result" (message id and link).
      #
      # comment_dm_automation binds a comment-to-DM automation to the post
      # (Instagram or Facebook must be in channels): a keyword in a comment
      # is answered with a DM, once per person, with an optional public
      # reply under the comment. Shape: { "trigger" => { "keywords" =>
      # ["guide"], "match" => "word" }, "actions" => { "dm" => { "text" =>
      # "..." }, "public_reply" => { "enabled" => true, "variations" =>
      # [...] } }, "limits" => { "max_sends" => 500 }, "platforms" =>
      # ["instagram", "facebook"] } (see automations.create for the
      # fields). "platforms" makes one automation per listed channel; each
      # must be a channel of the post. Without it: Instagram when the post
      # goes there, else Facebook. Needs the automations:write scope on the
      # key (403 insufficient_scope, checked before anything else); a bad
      # Hash is a 400 validation_error whose message starts with
      # "comment_dm_automation: ". The response then carries
      # data["comment_dm_automation"] (the first automation, with "post"
      # nil, plus "platforms" and "automations", one { "id", "platform",
      # "status" } per channel); each starts listening once the post is
      # live on its channel.
      def create(content:, channels: nil, scheduled_at: nil, media_ids: nil,
                 media_urls: nil, type: nil, source: nil, link_url: nil,
                 link_title: nil, link_description: nil, link_thumbnail_url: nil,
                 location_id: nil, collaborators: nil, user_tags: nil,
                 hashtag_set: nil, hashtag_set_id: nil, hashtag_placement: nil,
                 hashtag_platforms: nil, pinterest: nil, youtube: nil,
                 instagram: nil, facebook: nil, linkedin: nil,
                 linkedin_page: nil, tiktok: nil, x: nil, bluesky: nil,
                 mastodon: nil, threads: nil, google_business: nil,
                 telegram: nil, discord: nil, linkedin_poll: nil,
                 approval_workflow_id: nil, draft: nil, media_fit: nil,
                 comment_dm_automation: nil)
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
          google_business: google_business, telegram: telegram,
          discord: discord, linkedin_poll: linkedin_poll,
          approval_workflow_id: approval_workflow_id, draft: draft,
          media_fit: media_fit, comment_dm_automation: comment_dm_automation
        )
        @client.request("POST", "/posts/create", json: body)
      end

      # POST /posts/create-and-publish - create and publish immediately.
      # See #create for the "warnings" array (X link posts, and the
      # "image_fit" entries steered by media_fit), the 402
      # "x_credits_insufficient" credit gate on X link posts and
      # comment_dm_automation.
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
                             telegram: nil, discord: nil, linkedin_poll: nil,
                             media_fit: nil,
                             comment_dm_automation: nil)
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
          google_business: google_business, telegram: telegram,
          discord: discord, linkedin_poll: linkedin_poll,
          media_fit: media_fit, comment_dm_automation: comment_dm_automation
        )
        @client.request("POST", "/posts/create-and-publish", json: body)
      end

      # PATCH /posts/{id} - update a draft or scheduled post.
      #
      # draft: false without scheduled_at schedules a planned draft at the
      # scheduled_at it already carries (400 validation_error when it has
      # none or it is in the past). draft: true without scheduled_at
      # unschedules a scheduled post: it keeps its time and stays on the
      # calendar as a dashed draft, nothing publishes; a post waiting for
      # approval leaves its workflow. draft: true with scheduled_at moves the
      # time and keeps (or makes) the post a draft.
      #
      # media_fit (same shape as on #create) alone re-decides the stored
      # images: "keep" gives the original back, "crop" crops an image that
      # was kept. Like #create, the response can carry a top-level "warnings"
      # array with "image_fit" entries when the update changes the images or
      # media_fit.
      #
      # Only top-level nils are dropped from the body, so passing e.g.
      # x: { "thread_parts" => nil } still clears an X thread (reverts the
      # post to single-tweet mode). The same applies to bluesky, mastodon
      # and threads thread parts, and to a Threads location tag:
      # threads: { "location_id" => nil } (or "location" => nil) clears it.
      #
      # pinterest replaces the stored Pinterest options wholesale, so leave
      # "product_tags" out (or send []) to remove the product tags.
      #
      # See #create for the 402 "x_credits_insufficient" credit gate that
      # can also refuse an update to a scheduled X link post.
      #
      # comment_dm_automation (same shape as on #create) as a Hash replaces
      # the post's comment-to-DM automations (a channel no longer in
      # "platforms" loses its automation), an explicit nil removes them all,
      # and leaving it out keeps them. Needs the automations:write scope.
      #
      # discord merges into the stored Discord options: a key set to nil
      # removes that option (e.g. discord: { "poll" => nil }), an explicit
      # discord: nil removes every option, and leaving it out keeps them.
      def update(post_id, content: nil, scheduled_at: nil, channels: nil,
                 media_ids: nil, media_urls: nil, type: nil, location_id: nil,
                 collaborators: nil, user_tags: nil, pinterest: nil,
                 youtube: nil, instagram: nil, facebook: nil, linkedin: nil,
                 linkedin_page: nil, tiktok: nil, x: nil, bluesky: nil,
                 mastodon: nil, threads: nil, google_business: nil,
                 telegram: nil, discord: OmniSocials::NOT_GIVEN,
                 linkedin_poll: nil, draft: nil, media_fit: nil,
                 comment_dm_automation: OmniSocials::NOT_GIVEN)
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
            "telegram" => telegram,
            "linkedin_poll" => linkedin_poll,
            "draft" => draft,
            "media_fit" => media_fit
          }
        )
        # An explicit nil removes the post's automation, so it must survive
        # drop_nil; NOT_GIVEN (the default) leaves it untouched.
        body["comment_dm_automation"] = comment_dm_automation unless comment_dm_automation.is_a?(NotGiven)
        # Same for discord: an explicit nil removes every Discord option.
        body["discord"] = discord unless discord.is_a?(NotGiven)
        @client.request("PATCH", "/posts/#{post_id}", json: body)
      end

      # DELETE /posts/{id} - remove a post from OmniSocials (the live post stays on the platform). Returns nil (204).
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

      # GET /posts/{id}/approval - the approval review of a post: every step
      # with its approvers and their decisions, the rejection with its
      # reason, and the comment thread. Use it when approval_status is
      # "rejected" to learn who rejected the post and why, or while it is
      # "pending" to see who the post waits for.
      #
      # `data` carries post_id, status ("none", "pending", "approved",
      # "rejected"), workflow, requested_by, requested_at, current_step,
      # steps, rejection and comments (oldest first). A post without an
      # approval workflow returns status "none" with the object fields nil
      # and empty steps and comments. Read-only; requires the posts:read
      # scope.
      def get_approval(post_id)
        @client.request("GET", "/posts/#{post_id}/approval")
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
                      telegram: nil, discord: nil, approval_workflow_id: nil,
                      draft: nil,
                      media_fit: nil, comment_dm_automation: nil)
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
            "telegram" => telegram,
            "discord" => discord,
            "linkedin_poll" => linkedin_poll,
            "approval_workflow_id" => approval_workflow_id,
            "draft" => draft,
            "media_fit" => media_fit,
            "comment_dm_automation" => comment_dm_automation
          }
        )
      end
    end
  end
end
