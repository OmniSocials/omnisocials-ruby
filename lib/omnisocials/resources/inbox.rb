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
      # "linkedin", "x"), type ("dm", "comment", "mention"), unread (only
      # conversations with unread messages), limit (1-100), and cursor (an
      # opaque cursor from a previous response's pagination["next_cursor"]).
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
      # `text` is required. Optionally attach a single media asset by public
      # URL with `attachment_url` plus `attachment_type` ("image", "video",
      # "audio", or "file"). Returns the created outgoing message.
      #
      # Replying to an X DM costs 2 prepaid credits, debited from the
      # company balance before the send and automatically refunded if the
      # send fails. Two 402 error codes are specific to this call:
      # "insufficient_credits" when the balance can't cover the 2 credits,
      # and "x_inbox_suspended" when the workspace's X inbox was
      # auto-suspended after the balance hit zero (top up and re-enable it
      # in the dashboard to resume; DMs that arrived while suspended are
      # not recovered).
      def reply(conversation_id, text:, attachment_url: nil, attachment_type: nil)
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

      private

      # URL-encode a conversation id for use in a path segment. LinkedIn ids
      # contain ":" and "()", so they must be escaped; spaces become %20
      # (a path segment treats "+" literally, unlike a query string).
      def encode_id(conversation_id)
        CGI.escape(conversation_id.to_s).gsub("+", "%20")
      end
    end
  end
end
