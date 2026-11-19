# frozen_string_literal: true

module OmniSocials
  module Resources
    # Automations resource: comment-to-DM automations (list, get, create,
    # update, delete, events). An automation answers a keyword in an
    # Instagram comment (or a DM, or a story reply) with a DM, once per
    # person, with an optional public reply under the comment. With
    # platform: "facebook" it runs on a Facebook Page instead, and the DM
    # lands in Messenger (a Page has no story replies). With platform: "x"
    # it answers a keyword in a DM to the X account ("dm" kind only, no
    # post, no public reply) while X DMs are on for the workspace; every X
    # answer ends with "Reply STOP to stop automatic messages." and a
    # person who replies STOP gets no automatic DM again. The scopes are
    # opt-in on the API key: automations:read for list / get / list_events,
    # automations:write for create / update / delete (and for
    # comment_dm_automation on posts).
    class Automations
      def initialize(client)
        @client = client
      end

      # GET /automations - list the workspace's comment-to-DM automations,
      # optionally by status ("active", "paused", "completed"), by platform
      # ("instagram", "facebook", "x") or by the OmniSocials post_id they are
      # bound to. Requires the automations:read scope (opt-in on the API
      # key).
      def list(status: nil, post_id: nil, platform: nil)
        @client.request(
          "GET", "/automations",
          query: { "status" => status, "platform" => platform, "post_id" => post_id }
        )
      end

      # GET /automations/{id} - fetch a single automation. Requires the
      # automations:read scope (opt-in on the API key).
      def get(automation_id)
        @client.request("GET", "/automations/#{Internal.path_segment(automation_id)}")
      end

      # POST /automations - create a comment-to-DM automation.
      #
      # A keyword in an Instagram comment (or a DM, or a story reply) is
      # answered with a DM, once per person, with an optional public reply
      # under the comment. platform is "instagram" (default) or "facebook":
      # on a Facebook Page a keyword in a comment (or a Messenger message to
      # the Page) is answered in Messenger, and a Page has no story replies.
      # platform: "x" answers a keyword in a DM to the X account: trigger
      # kinds must be ["dm"] (X allows an automated DM only after the person
      # wrote first), with no post and no public reply; an active X
      # automation needs X DMs on for the workspace (409 x_dms_off; status
      # "paused" always saves), and every X answer ends with "Reply STOP to
      # stop automatic messages.". Bind it to one post with post_id (an OmniSocials post that goes to
      # the channel, scheduled or live; one automation per post and
      # platform), instagram_media_id (an Instagram post published outside
      # OmniSocials) or facebook_post_id (a Page post published outside
      # OmniSocials, as "{page-id}_{post-id}" or the post id alone; implies
      # "facebook"), at most one; a trigger scope of "next_post" or "any"
      # needs none.
      #
      # `actions` is required: { "dm" => { "text" => "..." } } (max 1000
      # characters) plus an optional "public_reply" => { "enabled" => true,
      # "variations" => [...] } (comment kind only, up to 10 of 300
      # characters). `trigger` is { "kinds" => ["comment"], "scope" =>
      # "post", "keywords" => [...], "match" => "word" }: kinds one or more
      # of "comment", "dm", "story_reply"; keywords up to 20 of 60
      # characters, required unless match is "any"; match is "word",
      # "contains" or "any". `limits` is { "max_sends" => 500, "stop_at" =>
      # "2026-12-31T00:00:00Z" } (both optional). `status` is "active"
      # (default) or "paused". Meta rules, the same on Instagram and
      # Facebook: one private reply per comment, within 7 days; OmniSocials
      # caps sends at 700 DMs an hour per account and platform, and on X at
      # 15 per 15 minutes and 450 a day; an answer over a cap waits in a
      # queue ("queued") for up to about a day on Instagram and Facebook
      # (an hour on X).
      #
      # Follow first (Instagram only): actions "follow_gate" => { "enabled"
      # => true, "first_message" => { "text", "button" }, "not_following" =>
      # { "text", "button" } } sends the link (the "dm" text) only to people
      # who follow the account. A comment gets the first message as the
      # private reply, with one button; a tap makes OmniSocials ask
      # Instagram whether the person follows. A follower gets the link,
      # anyone else gets the not_following message with its button, and
      # every later tap checks again. A DM or a story reply is checked at
      # once. When Instagram gives no answer the link goes out anyway.
      # Texts hold 640 characters, buttons 20; a text or button left out is
      # the default. nil or false turns it off. The response carries the
      # gate with its texts (nil on Facebook and X) and stats "followed".
      #
      # Follow-up (Instagram and Facebook): actions "follow_up" => {
      # "enabled" => true, "text" => "...", "delay_hours" => 23, "button" =>
      # { "title", "url" }, "tap" => { "text", "button" } } sends one more DM
      # delay_hours (1 to 23, default 23) after the answer (the "dm" text)
      # went out. "text" is required when it is on (max 1000 characters,
      # 640 with a "button"); "button" is an optional link button ("title"
      # 1 to 20 characters, "url" an https:// or http:// address of up to
      # 2000). Meta allows an automatic message only within 24 hours after
      # the person's last DM, button tap or quick reply; the comment and the
      # private reply do not open that window. So on an Instagram comment
      # with Follow first off the first DM becomes a tap step, a short text
      # with one button ("tap", Instagram only, "text" max 640 and "button"
      # max 20 characters; default "Tap the button and I'll send you the
      # link 👇" / "Send me the link"): the tap sends the link, and until
      # then the event is "waiting" with follow_gate "mode" "tap". People
      # who never tap get no link and no follow-up. With Follow first on,
      # its own tap is the tap; DM and story reply triggers need none. A
      # Facebook comment answer has no button: only people who answer the
      # DM in Messenger get the follow-up. nil, false or { "enabled" =>
      # false } turns it off and keeps the texts. The response carries
      # actions "follow_up" ({ "enabled", "text", "delay_hours", "button" =>
      # {...} | nil, "tap" => {...} | nil }, "tap" filled in on Instagram
      # and nil on Facebook; the whole follow-up is nil on X) and stats
      # "follow_ups_sent" / "follow_ups_skipped".
      #
      # Requires the automations:write scope (opt-in on the API key).
      # Errors: 400 validation_error, 400 follow_gate_instagram_only, 400
      # follow_up_not_supported (a follow-up switched on on X), 400
      # post_not_instagram, 400 post_not_facebook, 400 post_required, 404 post_not_found, 404
      # instagram_media_not_found, 404 facebook_post_not_found, 409
      # instagram_not_connected, 409 instagram_needs_reauth, 409
      # facebook_not_connected, 409 facebook_needs_reauth, 409
      # x_not_connected, 409 x_dms_off, 409 automation_exists (the error
      # body also carries automation_id).
      def create(actions:, trigger: nil, limits: nil, name: nil, post_id: nil,
                 instagram_media_id: nil, status: nil, platform: nil,
                 facebook_post_id: nil)
        body = automation_body(
          name: name, post_id: post_id, instagram_media_id: instagram_media_id,
          trigger: trigger, actions: actions, limits: limits, status: status,
          platform: platform, facebook_post_id: facebook_post_id
        )
        @client.request("POST", "/automations", json: body)
      end

      # PATCH /automations/{id} - partial update.
      #
      # Each section (trigger, actions, limits) is merged into the stored
      # one; keys you omit keep their value: new trigger "keywords" keep the
      # kinds, the scope and the match; a new actions "dm" "text" keeps the
      # public reply; limits: { "stop_at" => ... } keeps max_sends.
      # "public_reply" => { "enabled" => false } or { "variations" => [] }
      # turns the public reply off; "follow_gate" => { "enabled" => false }
      # turns Follow first off and keeps its texts, new texts keep the
      # switch, and "follow_gate" => nil turns it off; "follow_up" merges
      # the same way ("tap" key by key, "button" => nil removes the button,
      # nil, false or { "enabled" => false } turns it off and keeps the
      # texts); limits: { "max_sends" => nil } removes that limit. status: "paused" pauses and "active" resumes; another
      # post_id / instagram_media_id / facebook_post_id moves the automation
      # to that post. The platform cannot change: a platform other than the
      # automation's is a 400 platform_immutable. status: "active" on an X
      # automation needs X DMs on for the workspace (409 x_dms_off). A
      # "completed" automation starts again when its limits or trigger
      # change. Requires the
      # automations:write scope. 400 no_fields when nothing is passed; 400
      # follow_up_not_supported for a follow-up switched on on X.
      def update(automation_id, name: nil, post_id: nil, instagram_media_id: nil,
                 trigger: nil, actions: nil, limits: nil, status: nil,
                 platform: nil, facebook_post_id: nil)
        body = automation_body(
          name: name, post_id: post_id, instagram_media_id: instagram_media_id,
          trigger: trigger, actions: actions, limits: limits, status: status,
          platform: platform, facebook_post_id: facebook_post_id
        )
        @client.request("PATCH", "/automations/#{Internal.path_segment(automation_id)}", json: body)
      end

      # DELETE /automations/{id} - delete an automation. Returns nil (204).
      # Requires the automations:write scope.
      def delete(automation_id)
        @client.request("DELETE", "/automations/#{Internal.path_segment(automation_id)}")
      end

      # GET /automations/{id}/events - the automation's activity: one event
      # per person it answered, skipped or failed on. outcome filters on
      # "sent", "skipped", "failed", "pending", "queued" (waits for a free
      # slot under the send cap, out as soon as there is room), "opted_out" (the
      # person replied STOP on X) or "waiting" (Follow first: asked to
      # follow, the link goes out after the follow; or the tap step of a
      # follow-up: the link goes out after the tap); limit is 1..100
      # (default 25), offset skips. Requires the automations:read scope.
      #
      # The response is not the plain list envelope: { "data" => [...],
      # "counts" => { "sent" => 12, "skipped" => 3 }, "pagination" => {...} },
      # where counts is the number of events per outcome (an outcome with no
      # events is left out). Each event carries kind ("comment", "dm",
      # "story_reply"), outcome, reason / reason_label (X adds the skip
      # reasons "dms_closed", "no_credits", "opted_out" and
      # "automation_off"; Follow first adds "already_waiting";
      # "plan_inactive" = the organisation had no active plan or trial, so
      # nothing was sent), person (id,
      # username; on Facebook the person's name, since Facebook has no
      # @handle), trigger_id, trigger_text, message (the DM sent),
      # public_reply, platform_message_id, follow_gate (Follow first:
      # { "state" => "waiting" | "done", "asked_at", "taps", "followed",
      # "checked", "after_ask", "mode" }, else nil; "mode" is "follow", or
      # "tap" for the tap step of a follow-up, which checks no follow:
      # "checked" stays false and "followed" is nil after the tap),
      # follow_up (the follow-up of this answer: { "state" => "scheduled" |
      # "sending" | "sent" | "skipped" | "failed", "due_at", "sent_at",
      # "reason", "reason_label", "platform_message_id" }, else nil;
      # "reason" only on skipped and failed: "automation_off",
      # "follow_up_off", "plan_inactive", "opted_out", "team_answered",
      # "window_closed" (the person's last tap or message is older than 24
      # hours minus 15 minutes) or "cannot_message" for a skip, the
      # platform's error text or "interrupted" (a send that died midway,
      # never sent again) for a failure; "reason_label" = the skip in plain
      # words, or the error text), created_at and sent_at.
      def list_events(automation_id, outcome: nil, limit: nil, offset: nil)
        @client.request(
          "GET", "/automations/#{Internal.path_segment(automation_id)}/events",
          query: { "outcome" => outcome, "limit" => limit, "offset" => offset }
        )
      end

      private

      def automation_body(name:, post_id:, instagram_media_id:, trigger:,
                          actions:, limits:, status:, platform: nil,
                          facebook_post_id: nil)
        Internal.drop_nil(
          {
            "platform" => platform,
            "name" => name,
            "post_id" => post_id,
            "instagram_media_id" => instagram_media_id,
            "facebook_post_id" => facebook_post_id,
            "trigger" => trigger,
            "actions" => actions,
            "limits" => limits,
            "status" => status
          }
        )
      end
    end
  end
end
