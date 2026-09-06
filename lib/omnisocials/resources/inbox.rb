# frozen_string_literal: true

require "cgi"

module OmniSocials
  module Resources
    # Inbox resource: social inbox conversations (DMs, comments, mentions)
    # across connected platforms, plus reading and replying to them.
    #
    # The list endpoints use CURSOR pagination (unlike the offset pagination
    # elsewhere): each response carries pagination["next_cursor"],
    # pagination["has_more"], and pagination["limit"]. Page on by passing the
    # previous response's next_cursor as `cursor` while has_more is true.
    #
    # Conversation ids are URL-encoded for you, so pass them exactly as
    # returned - LinkedIn ids contain ":" and "()" (e.g.
    # "linkedin_comment_urn:li:activity:123").
    class Inbox
      def initialize(client)
        @client = client
      end

      # GET /inbox/conversations - list conversations, newest activity first.
      #
      # All filters are optional: platform ("instagram", "facebook",
      # "linkedin", "tiktok", "youtube", "x", "threads"), type ("dm", "comment",
      # "mention"), unread (only conversations with unread messages),
      # unanswered (only conversations that still need an answer: the
      # customer's latest DM has no reply after it, for Instagram/Facebook DMs
      # within the 24-hour messaging window only, or a comment/mention that
      # has not been replied to and is not hidden; replies typed in the native
      # apps count as answers, and read state is ignored, so use `next` for a
      # work queue), limit (1-100), and cursor (an opaque cursor from a
      # previous response's pagination["next_cursor"]).
      #
      # Threads conversations are type "comment" (replies people leave on the
      # user's Threads posts; conversation ids look like
      # "threads_comment_<rootPostId>") and "mention"
      # ("threads_mention_<postId>"); there are no Threads DMs. Threads inbox
      # is currently rolling out: until Meta approves the permissions it is
      # disabled on production and calls return a clear error, and it needs a
      # Threads connection with the reply permission.
      def list_conversations(platform: nil, type: nil, unread: nil, unanswered: nil, limit: nil, cursor: nil)
        @client.request(
          "GET", "/inbox/conversations",
          query: {
            "platform" => platform,
            "type" => type,
            "unread" => unread,
            "unanswered" => unanswered,
            "limit" => limit,
            "cursor" => cursor
          }
        )
      end

      # GET /inbox/conversations/{id}/messages - full message thread for one
      # conversation, newest first. Cursor-paginated via `limit` / `cursor`.
      def get_messages(conversation_id, limit: nil, cursor: nil)
        @client.request(
          "GET", "/inbox/conversations/#{encode_id(conversation_id)}/messages",
          query: { "limit" => limit, "cursor" => cursor }
        )
      end

      # POST /inbox/conversations/{id}/read - mark every message in the
      # conversation as read. Returns the count of messages newly marked read.
      def mark_read(conversation_id)
        @client.request("POST", "/inbox/conversations/#{encode_id(conversation_id)}/read")
      end

      # POST /inbox/conversations/{id}/reply - send a reply into the
      # conversation (a DM message, or a reply to the comment/mention).
      #
      # On Facebook and Instagram DMs, optionally attach a single media asset
      # by public URL with `attachment_url` plus `attachment_type` ("image",
      # "video", "audio", or "file"); `text` is optional when `attachment_url`
      # is set (an attachment-only reply is allowed). Other platforms are
      # text-only. Returns the created outgoing message.
      #
      # On a Threads conversation the reply publishes as a native Threads
      # reply. Threads inbox is currently rolling out (disabled on production
      # until Meta App Review) and needs a Threads connection with the reply
      # permission: a 401 with code "reauth_required" means the connection
      # lacks that permission (reconnect Threads).
      #
      # Replying to an X DM costs 2 prepaid credits, debited from the
      # company balance before the send and automatically refunded if the
      # send fails. Two 402 error codes are specific to this call:
      # "insufficient_credits" when the balance can't cover the 2 credits,
      # and "x_inbox_suspended" when the workspace's X inbox was
      # auto-suspended after the balance hit zero (top up and re-enable it
      # in the dashboard to resume; DMs that arrived while suspended are
      # not recovered).
      #
      # Pass include_next: true to also get "next" (the next conversation
      # that needs an answer, the same object `next` returns under "data",
      # using its default queue order and filters; nil when nothing is
      # waiting) and "remaining" in the response. Saves the extra call when
      # working through the inbox.
      def reply(conversation_id, text: nil, attachment_url: nil, attachment_type: nil, include_next: nil)
        body = Internal.drop_nil(
          {
            "text" => text,
            "attachment_url" => attachment_url,
            "attachment_type" => attachment_type,
            "include_next" => include_next
          }
        )
        @client.request(
          "POST", "/inbox/conversations/#{encode_id(conversation_id)}/reply",
          json: body
        )
      end

      # POST /inbox/messages/{id}/hide - hide or unhide a comment someone
      # left on one of the user's posts, on the platform, as the post owner.
      # Facebook, Instagram, TikTok, YouTube and Threads comments (Threads:
      # incoming top-level replies only; Threads does not allow hiding nested
      # replies). Pass hide: false to unhide. On YouTube, hide sets the
      # comment's moderation status to rejected, which removes it and its
      # replies from public view; unhide publishes it again. Returns the
      # updated message with its "hidden" flag flipped; the message keeps its
      # place in the conversation, and a hidden comment no longer counts as
      # unanswered. The account must have been connected with the moderation
      # permission (Facebook pages_manage_engagement, Instagram
      # instagram_business_manage_comments).
      #
      # Errors: 400 "unsupported_platform" (not an incoming comment on a
      # supported platform), 400 "not_hideable" (Threads nested reply, or
      # Threads refused), 401 "reauth_required" (the Threads reply permission
      # or the TikTok comments authorization is missing or expired), 403
      # "reconnect_required" (the account was connected without the
      # comment-moderation permission; reconnect it in the dashboard), 404
      # "not_found" (message not in this workspace) or
      # "account_not_connected", 429 "quota_exceeded" (YouTube's daily API
      # quota is used up; retry after midnight Pacific), 502 "platform_error"
      # (the platform rejected the call). Threads inbox is currently rolling
      # out; until Meta approves the permissions it is disabled on production
      # and Threads calls return a clear error.
      def hide(message_id, hide: true)
        @client.request(
          "POST", "/inbox/messages/#{encode_id(message_id)}/hide",
          json: { "hide" => hide }
        )
      end

      # DELETE /inbox/messages/{id} - delete a comment someone left on one of
      # the user's posts, on the platform and from the inbox. Facebook,
      # Instagram and TikTok comments only: YouTube's API does not let a
      # channel delete other people's comments, hide those instead (`hide`).
      # Replies under the deleted comment go with it (the platforms cascade
      # the delete and the inbox mirrors that); their inbox ids come back as
      # "removed_reply_ids". A comment that is already gone on the platform
      # is still removed from the inbox. This cannot be undone. Returns
      # { "data" => { "id", "conversation_id", "removed_reply_ids" } }.
      #
      # Errors: 400 "unsupported_platform" (not an incoming Facebook,
      # Instagram or TikTok comment), 401 "reauth_required" (the TikTok
      # comments authorization expired), 403 "reconnect_required" (the
      # account was connected without the comment-moderation permission;
      # reconnect it in the dashboard), 404 "not_found" (message not in this
      # workspace) or "account_not_connected", 502 "platform_error" (the
      # platform rejected the call).
      def delete_message(message_id)
        @client.request("DELETE", "/inbox/messages/#{encode_id(message_id)}")
      end

      # GET /inbox/next - the next conversation that needs an answer: a work
      # queue for answering the inbox. Returns the oldest (by default) item
      # that still needs a reply, together with its conversation so far and
      # the post it belongs to, so a reply can be drafted from one call. An
      # item needs an answer when it is the customer's latest DM with no
      # reply after it (Instagram/Facebook DMs within the 24-hour messaging
      # window only, since Meta refuses replies outside it), or a
      # comment/mention that has not been replied to and is not hidden.
      # Replies typed in the native apps count as answers (they are mirrored
      # into the inbox), so a thread a colleague answered on their phone is
      # not served again. Instagram mentions are skipped (no reply path).
      # Looks at the last 30 days of activity. Requires the inbox:read scope.
      #
      # Only unread items are served by default: marking a conversation read
      # (`mark_read`) is how to skip one for good; pass include_read: true to
      # include read-but-unanswered items. exclude is a session-local skip:
      # conversation ids (an Array, or a comma-separated String) to leave out
      # of this call, up to 100. order is "oldest" (default: the item that
      # has waited longest first) or "newest". platform and type ("dm",
      # "comment", "mention") narrow the queue.
      #
      # Returns { "data" => ..., "remaining" => Integer }. "data" is
      # { "conversation", "message", "messages" }, or nil when nothing is
      # waiting. "message" is the unanswered incoming item itself (the
      # customer's latest DM, or the specific comment): its "id" is what
      # `hide` and `delete_message` take, its "conversation_id" is what
      # `reply` takes. "messages" is the conversation so far, oldest first
      # (the most recent 50 messages for long DM threads). "remaining" is the
      # number of unanswered items still waiting after this one (capped at
      # 500), 0 when "data" is nil. To chain the queue, pass
      # include_next: true to `reply` and it returns the next item in the
      # same response. Errors: 400 "validation_error" (unknown platform, type
      # or order).
      def next(platform: nil, type: nil, order: nil, include_read: nil, exclude: nil)
        exclude = exclude.join(",") if exclude.is_a?(Array)
        exclude = nil if exclude == ""
        @client.request(
          "GET", "/inbox/next",
          query: {
            "platform" => platform,
            "type" => type,
            "order" => order,
            "include_read" => include_read,
            "exclude" => exclude
          }
        )
      end

      private

      # URL-encode a conversation or message id for use in a path segment.
      # LinkedIn conversation ids contain ":" and "()", so they must be
      # escaped; spaces become %20 (a path segment treats "+" literally,
      # unlike a query string).
      def encode_id(conversation_id)
        CGI.escape(conversation_id.to_s).gsub("+", "%20")
      end
    end
  end
end
