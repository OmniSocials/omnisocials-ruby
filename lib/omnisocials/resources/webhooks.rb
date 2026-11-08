# frozen_string_literal: true

module OmniSocials
  module Resources
    # Webhooks resource: manage event subscriptions (post.scheduled,
    # post.published, post.failed, post.approved, post.rejected, and for ads
    # ad.status_changed, ad.created, ad.updated, ad.review,
    # ad.delivery_issue, campaign.created, campaign.updated,
    # campaign.budget, lead.received, ads.sync_failed, ads.sync_recovered,
    # ads.initial_sync_completed and ad_rule.triggered, and for X
    # statistics x_statistics.paused and x_statistics.resumed).
    #
    # For verifying incoming deliveries, see OmniSocials::Webhooks.verify.
    class Webhooks
      def initialize(client)
        @client = client
      end

      # GET /webhooks - list the webhooks of the key's workspace and the
      # organisation-wide webhooks of its organisation.
      #
      # Every webhook carries "workspace_id": nil for an organisation-wide
      # webhook (made in the OmniSocials dashboard), which receives the
      # events of every workspace of the organisation. A webhook whose
      # creator lost access to the organisation or workspace is switched off
      # automatically: "is_active" is false and "last_failure"["error"] says
      # why.
      def list
        @client.request("GET", "/webhooks")
      end

      # GET /webhooks/{id} - fetch a webhook of the key's workspace, or an
      # organisation-wide webhook of its organisation ("workspace_id" nil).
      def get(webhook_id)
        @client.request("GET", "/webhooks/#{Internal.path_segment(webhook_id)}")
      end

      # POST /webhooks - create a webhook subscription.
      #
      # `url` must be HTTPS. `events` is a non-empty subset of
      # post.scheduled, post.published, post.failed, post.approved,
      # post.rejected and the ads events ad.status_changed, ad.created,
      # ad.updated, ad.review, ad.delivery_issue, campaign.created,
      # campaign.updated, campaign.budget, lead.received, ads.sync_failed,
      # ads.sync_recovered, ads.initial_sync_completed and
      # ad_rule.triggered, and x_statistics.paused / x_statistics.resumed
      # (the organisation's X statistics stopped at 0 credits or started
      # again after a top-up, one delivery per workspace with X; `data` is
      # { workspace_id, account_id, reason }, reason insufficient_credits or
      # credits_added). The `data` of an ad.status_changed delivery is
      # the campaign, not a post: campaign_id, workspace_id, name, platform,
      # campaign_type, status, previous_status, external_campaign_id and
      # budget; the other ads events carry the campaign (plus "details") or
      # their own data (a lead, a rule run, an ad account). Any Ads event
      # (ad.*, campaign.*, lead.*, ads.*, ad_rule.*) needs the ads:read scope
      # on the key and access_ads for its person (403 insufficient_scope /
      # 403 insufficient_permission). The signing
      # `secret` is only returned once, in this response - store it.
      def create(url:, events:)
        @client.request(
          "POST", "/webhooks",
          json: { "url" => url, "events" => Array(events) }
        )
      end

      # PATCH /webhooks/{id} - update url, events, or active state. Ads
      # events need the same ads:read scope and access_ads as on create.
      # Works on organisation-wide webhooks too. is_active: true switches on
      # a webhook that was switched off (also an automatic switch-off);
      # setting url, events or switching it on makes the key's creator the
      # person behind the webhook. Setting url on an organisation-wide
      # webhook (even its current one) moves it to the key's workspace: from
      # then on it gets only that workspace's events, and the answer shows
      # the new workspace_id. When the webhook has Ads events after the
      # change, setting url or events or switching it on needs ads:read and
      # access_ads (403 otherwise, nothing changed).
      def update(webhook_id, url: nil, events: nil, is_active: nil)
        body = Internal.drop_nil(
          {
            "url" => url,
            "events" => events.nil? ? nil : Array(events),
            "is_active" => is_active
          }
        )
        @client.request("PATCH", "/webhooks/#{Internal.path_segment(webhook_id)}", json: body)
      end

      # DELETE /webhooks/{id} - delete a webhook of the key's workspace or
      # an organisation-wide webhook of its organisation. Returns nil (204).
      def delete(webhook_id)
        @client.request("DELETE", "/webhooks/#{Internal.path_segment(webhook_id)}")
      end

      # POST /webhooks/{id}/rotate-secret - rotate the signing secret.
      #
      # The new secret is only returned once, in this response. The old
      # secret keeps signing for 24 hours: every delivery then carries
      # X-OmniSocials-Signature (new secret) and
      # X-OmniSocials-Signature-Previous (old secret, same format, same
      # timestamp and body). Verify the first with the new secret and, when
      # that fails, the second with the old one (see
      # OmniSocials::Webhooks.verify). Rotating again within the 24 hours
      # replaces the previous secret with the one just rotated out. Works on
      # organisation-wide webhooks too.
      def rotate_secret(webhook_id)
        @client.request("POST", "/webhooks/#{Internal.path_segment(webhook_id)}/rotate-secret")
      end
    end
  end
end
