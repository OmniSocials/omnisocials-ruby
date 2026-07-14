# frozen_string_literal: true

module OmniSocials
  module Resources
    # Webhooks resource: manage event subscriptions (post.scheduled,
    # post.published, post.failed).
    #
    # For verifying incoming deliveries, see OmniSocials::Webhooks.verify.
    class Webhooks
      def initialize(client)
        @client = client
      end

      # GET /webhooks - list webhook subscriptions.
      def list
        @client.request("GET", "/webhooks")
      end

      # GET /webhooks/{id} - fetch a single webhook subscription.
      def get(webhook_id)
        @client.request("GET", "/webhooks/#{webhook_id}")
      end

      # POST /webhooks - create a webhook subscription.
      #
      # `url` must be HTTPS. `events` is a non-empty subset of
      # post.scheduled, post.published, post.failed. The signing `secret` is
      # only returned once, in this response - store it.
      def create(url:, events:)
        @client.request(
          "POST", "/webhooks",
          json: { "url" => url, "events" => Array(events) }
        )
      end

      # PATCH /webhooks/{id} - update url, events, or active state.
      def update(webhook_id, url: nil, events: nil, is_active: nil)
        body = Internal.drop_nil(
          {
            "url" => url,
            "events" => events.nil? ? nil : Array(events),
            "is_active" => is_active
          }
        )
        @client.request("PATCH", "/webhooks/#{webhook_id}", json: body)
      end

      # DELETE /webhooks/{id} - delete a webhook. Returns nil (204).
      def delete(webhook_id)
        @client.request("DELETE", "/webhooks/#{webhook_id}")
      end

      # POST /webhooks/{id}/rotate-secret - rotate the signing secret.
      #
      # The new secret is only returned once, in this response.
      def rotate_secret(webhook_id)
        @client.request("POST", "/webhooks/#{webhook_id}/rotate-secret")
      end
    end
  end
end
