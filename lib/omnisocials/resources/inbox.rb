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
      # "mention"), unread (only conversations with unread messages), limit
      # (1-100), and cursor (an opaque cursor from a previous response's
      # pagination["next_cursor"]).
      #
      # Threads conversations are type "comment" (replies people leave on the
      # user's Threads posts; conversation ids look like
      # "threads_comment_<rootPostId>") and "mention"
      # ("threads_mention_<postId>"); there are no Threads DMs. Threads inbox
      # is currently rolling out: until Meta approves the permissions it is
      # disabled on production and calls return a clear error, and it needs a
      # Threads connection with the reply permission.
      def list_conversations(platform: nil, type: nil, unread: nil, limit: nil, cursor: nil)
        @client.request(
          "GET", "/inbox/conversations",
          query: {
            "platform" => platform,
            "type" => type,
            "unread" => unread,
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
      def reply(conversation_id, text: nil, attachment_url: nil, attachment_type: nil)
        body = Internal.drop_nil(
          {
            "text" => text,
            "attachment_url" => attachment_url,
            "attachment_type" => attachment_type
          }
        )
        @client.request(
          "POST", "/inbox/conversations/#{encode_id(conversation_id)}/reply",
          json: body
        )
      end

      # POST /inbox/messages/{id}/hide - hide or unhide a reply someone left
      # on one of the user's Threads posts, as the post owner (Threads only
      # for now). Pass hide: false to unhide. Only incoming top-level replies
      # can be hidden (Threads does not allow hiding nested replies); the
      # message keeps its place in the conversation. Returns the updated
      # message with its "hidden" flag flipped.
      #
      # Errors: 400 "unsupported_platform" (not an incoming Threads reply, or
      # Threads inbox not available yet), 400 "not_hideable" (nested reply or
      # Threads refused), 401 "reauth_required" (connection lacks the reply
      # permission; reconnect Threads), 404 "not_found" (message not in this
      # workspace) or "account_not_connected" (no Threads account).
      def hide(message_id, hide: true)
        @client.request(
          "POST", "/inbox/messages/#{encode_id(message_id)}/hide",
          json: { "hide" => hide }
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
