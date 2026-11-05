# frozen_string_literal: true

module OmniSocials
  module Resources
    # Ads resource: boosts, campaigns and "Create an ad" drafts on Meta,
    # Pinterest, TikTok, LinkedIn, X and Google.
    #
    # Ads spend real money once a campaign starts. Boosts, campaigns and
    # drafts are created as drafts (no spend); activate, activate_multi,
    # drafts.launch, resume and a budget raise through update start or raise
    # spend, and each needs the amount again as a confirmation. These calls
    # are never retried after a 5xx, a timeout or a lost connection (only a
    # 429), because the first attempt may have started the ad. Budgets are in
    # major currency units (10 = 10 EUR) in the ad account's currency. Ad
    # accounts are connected and picked in the OmniSocials dashboard. The
    # scopes ads:read and ads:write are opt-in on the API key (the Ads
    # switch).
    class Ads
      # "Create an ad" drafts (an OmniSocials::Resources::AdDrafts).
      attr_reader :drafts

      def initialize(client)
        @client = client
        @drafts = AdDrafts.new(client)
      end

      # GET /ads/accounts - the connected ad accounts, as { "data" => [...],
      # "platforms_available" => [...] }. Accounts are connected and picked in
      # the dashboard; only is_selected accounts can run campaigns. Requires
      # ads:read (opt-in on the API key).
      def list_accounts
        @client.request("GET", "/ads/accounts")
      end

      # GET /ads/capabilities - what each network accepts for a new ad
      # (goals, media, text limits, buttons, minimum daily budget),
      # create_networks and network_states ("live", "preview" or
      # "coming_soon"). Requires ads:read.
      def capabilities
        @client.request("GET", "/ads/capabilities")
      end

      # GET /ads/campaigns - list campaigns and boosts, optionally by status,
      # platform or campaign_type ("campaign" or "boost"); limit is 1..100
      # (default 25). Requires ads:read.
      def list(status: nil, platform: nil, campaign_type: nil, limit: nil, offset: nil)
        @client.request(
          "GET", "/ads/campaigns",
          query: {
            "status" => status, "platform" => platform, "campaign_type" => campaign_type,
            "limit" => limit, "offset" => offset
          }
        )
      end

      # GET /ads/campaigns/{id} - one campaign with its latest numbers.
      # Requires ads:read.
      def get(campaign_id)
        @client.request("GET", "/ads/campaigns/#{Internal.path_segment(campaign_id)}")
      end

      # POST /ads/boost - boost a published post. Creates a DRAFT boost: no
      # spend until activate. budget is { "type" => "daily", "amount" => 5,
      # "currency" => "EUR" } in the ad account's currency. TikTok needs
      # creative "spark_auth_code", Google needs "headlines", "descriptions"
      # and "logo_url". Requires ads:write.
      def boost(post_id:, ad_account_id:, budget:, objective: nil, targeting: nil,
                schedule: nil, creative: nil, name: nil)
        body = Internal.drop_nil(
          {
            "post_id" => post_id, "ad_account_id" => ad_account_id, "budget" => budget,
            "objective" => objective, "targeting" => targeting, "schedule" => schedule,
            "creative" => creative, "name" => name
          }
        )
        @client.request("POST", "/ads/boost", json: body)
      end

      # POST /ads/boost-multi - one DRAFT boost per ad account (up to 10),
      # each with the same budget, so the total is amount x accounts. Answers
      # { "results" => [...] }; one failed account never stops the others.
      # Requires ads:write.
      def boost_multi(post_id:, ad_account_ids:, budget:, objective: nil, targeting: nil,
                      schedule: nil, creative: nil, name: nil)
        body = Internal.drop_nil(
          {
            "post_id" => post_id, "ad_account_ids" => ad_account_ids.to_a, "budget" => budget,
            "objective" => objective, "targeting" => targeting, "schedule" => schedule,
            "creative" => creative, "name" => name
          }
        )
        @client.request("POST", "/ads/boost-multi", json: body)
      end

      # POST /ads/campaigns - a DRAFT campaign without ads. It cannot start
      # (campaign_has_no_ads): use ads.drafts.create for a new ad. Requires
      # ads:write.
      def create(ad_account_id:, name:, budget:, objective: nil, targeting: nil, schedule: nil)
        body = Internal.drop_nil(
          {
            "ad_account_id" => ad_account_id,
            "name" => name,
            "budget" => budget,
            "objective" => objective,
            "targeting" => targeting,
            "schedule" => schedule
          }
        )
        @client.request("POST", "/ads/campaigns", json: body)
      end

      # PATCH /ads/campaigns/{id} - change the name, budget, targeting or
      # schedule.
      #
      # A higher budget on a running campaign RAISES REAL AD SPEND: show the
      # person the new amount and get their yes first, then pass it again as
      # confirm_budget_amount. Not retried after a 5xx, a timeout or a lost
      # connection: read the campaign with get to see what happened. Requires
      # ads:write.
      def update(campaign_id, name: nil, budget: nil, confirm_budget_amount: nil,
                 targeting: nil, schedule: nil)
        body = Internal.drop_nil(
          {
            "name" => name,
            "budget" => budget,
            "confirm_budget_amount" => confirm_budget_amount,
            "targeting" => targeting,
            "schedule" => schedule
          }
        )
        @client.request(
          "PATCH", "/ads/campaigns/#{Internal.path_segment(campaign_id)}",
          json: body, retry_on: :rate_limit
        )
      end

      # POST /ads/campaigns/{id}/activate - START REAL AD SPEND.
      #
      # Show the person the budget (amount, currency, daily or lifetime) and
      # get their yes first; confirm_budget_amount must equal the campaign's
      # budget amount. A campaign of a draft group answers 409
      # use_draft_launch: use ads.drafts.launch. Not retried after a 5xx, a
      # timeout or a lost connection: read the campaign with get to see what
      # happened. Requires ads:write.
      def activate(campaign_id, confirm_budget_amount)
        @client.request(
          "POST", "/ads/campaigns/#{Internal.path_segment(campaign_id)}/activate",
          json: { "confirm_budget_amount" => confirm_budget_amount }, retry_on: :rate_limit
        )
      end

      # POST /ads/campaigns/activate-multi - START REAL AD SPEND on up to 10
      # campaigns.
      #
      # Every campaign's budget must equal confirm_budget_amount; show the
      # person the total (amount x campaigns) and get their yes first.
      # Answers { "results" => [...] }. Not retried after a 5xx, a timeout or
      # a lost connection: read the campaigns with get to see what happened.
      # Requires ads:write.
      def activate_multi(campaign_ids, confirm_budget_amount)
        @client.request(
          "POST", "/ads/campaigns/activate-multi",
          json: {
            "campaign_ids" => campaign_ids.to_a,
            "confirm_budget_amount" => confirm_budget_amount
          },
          retry_on: :rate_limit
        )
      end

      # POST /ads/campaigns/{id}/pause - pause a campaign (also while in
      # review). Requires ads:write.
      def pause(campaign_id)
        @client.request("POST", "/ads/campaigns/#{Internal.path_segment(campaign_id)}/pause")
      end

      # POST /ads/campaigns/{id}/resume - resume a paused campaign: it STARTS
      # REAL AD SPEND again. Show the person the budget and get their yes
      # first. Not retried after a 5xx, a timeout or a lost connection: read
      # the campaign with get to see what happened. Requires ads:write.
      def resume(campaign_id)
        @client.request(
          "POST", "/ads/campaigns/#{Internal.path_segment(campaign_id)}/resume",
          retry_on: :rate_limit
        )
      end

      # DELETE /ads/campaigns/{id} - delete a campaign on the network too. A
      # campaign that spent is archived: its spend stays in the totals.
      # Requires ads:write.
      def delete(campaign_id)
        @client.request("DELETE", "/ads/campaigns/#{Internal.path_segment(campaign_id)}")
      end

      # GET /ads/overview - accounts, campaigns per status and total spend.
      # Requires ads:read.
      def overview
        @client.request("GET", "/ads/overview")
      end

      # GET /ads/suggestions - organic posts that do better than the
      # workspace median: boost candidates. Read-only. Requires ads:read.
      def suggestions
        @client.request("GET", "/ads/suggestions")
      end

      # POST /ads/research/keywords - keyword ideas from seed keywords (up to
      # 20), a url or both, through the connected Google Ads account. country
      # defaults to "US", language to "en", limit is 1..500 (default 100);
      # ad_account_id only when the workspace has more than one Google Ads
      # account. Read-only and free. Requires ads:read.
      def research_keywords(keywords: nil, url: nil, country: nil, language: nil, limit: nil,
                            ad_account_id: nil)
        body = Internal.drop_nil(
          {
            "keywords" => keywords&.to_a,
            "url" => url,
            "country" => country,
            "language" => language,
            "limit" => limit,
            "ad_account_id" => ad_account_id
          }
        )
        @client.request("POST", "/ads/research/keywords", json: body)
      end

      # POST /ads/research/keywords/metrics - search numbers for an exact
      # keyword list. Read-only. Requires ads:read.
      def keyword_metrics(keywords:, country: nil, language: nil, ad_account_id: nil)
        body = Internal.drop_nil(
          {
            "keywords" => keywords.to_a,
            "country" => country,
            "language" => language,
            "ad_account_id" => ad_account_id
          }
        )
        @client.request("POST", "/ads/research/keywords/metrics", json: body)
      end
    end

    # "Create an ad" drafts: one campaign per network in platforms, each with
    # the same ads. A draft never spends; launch starts it.
    class AdDrafts
      def initialize(client)
        @client = client
      end

      # GET /ads/drafts/defaults - suggested countries (where the Instagram
      # followers are), the currency and the workspace's ad account per
      # network. Requires ads:read.
      def defaults
        @client.request("GET", "/ads/drafts/defaults")
      end

      # POST /ads/drafts - save a new ad as a draft group. It needs no ad
      # account and spends nothing.
      #
      # objective is "traffic", "engagement", "awareness" or "video_views".
      # platforms lists network keys ("meta", "pinterest", "tiktok",
      # "linkedin", "x", "google") or { "platform" => ..., "budget_amount" =>
      # ..., "ad_account_id" => ... } per network. budget is the daily amount
      # per network, { "amount" => 10, "currency" => "EUR" }. schedule is
      # { "duration_days" => 7 } (nil runs until it is stopped). targeting
      # needs "countries"; "automatic_audience" => true lets the network find
      # the audience. Each of ads has "media", "primary_text", "link" and
      # optionally "headline", "description", "cta", "primary_text_b" (an A/B
      # test) and, on Meta, "placement_media" => { "stories_reels" => {...} }
      # (an upright 9:16 file for Stories and Reels).
      #
      # Read ads.capabilities first for what each network accepts. The answer
      # carries review_url (the builder in the dashboard) and per network
      # readiness. Requires ads:write.
      def create(objective:, platforms:, budget:, targeting:, ads:, name: nil, schedule: nil)
        body = draft_body(
          objective: objective, platforms: platforms, budget: budget,
          targeting: targeting, ads: ads, name: name, schedule: schedule
        )
        @client.request("POST", "/ads/drafts", json: body)
      end

      # GET /ads/drafts/{group_id} - one draft group. Requires ads:read.
      def get(group_id)
        @client.request("GET", "/ads/drafts/#{Internal.path_segment(group_id)}")
      end

      # PUT /ads/drafts/{group_id} - replace the draft with the full body
      # (the same fields as create). Networks that already started are left
      # alone (campaigns[].editable). Requires ads:write.
      def update(group_id, objective:, platforms:, budget:, targeting:, ads:, name: nil,
                 schedule: nil)
        body = draft_body(
          objective: objective, platforms: platforms, budget: budget,
          targeting: targeting, ads: ads, name: name, schedule: schedule
        )
        @client.request("PUT", "/ads/drafts/#{Internal.path_segment(group_id)}", json: body)
      end

      # DELETE /ads/drafts/{group_id} - delete a draft group that never
      # started. Requires ads:write.
      def delete(group_id)
        @client.request("DELETE", "/ads/drafts/#{Internal.path_segment(group_id)}")
      end

      # POST /ads/drafts/{group_id}/account - set the ad account of one
      # network in the draft (from ads.list_accounts, same network). Requires
      # ads:write.
      def attach_account(group_id, platform:, ad_account_id:)
        @client.request(
          "POST", "/ads/drafts/#{Internal.path_segment(group_id)}/account",
          json: { "platform" => platform, "ad_account_id" => ad_account_id }
        )
      end

      # POST /ads/drafts/{group_id}/launch - START REAL AD SPEND for every
      # network of the draft that never started.
      #
      # Show the person the daily amount per network and get their yes first,
      # then pass it as confirm_budget_amount (or per campaign id as
      # confirm_budget_amounts). A wrong or missing amount answers 400
      # budget_confirmation_required and writes nothing. The answer is
      # { "data" => { "group" => ..., "results" => [...] } } with a result per
      # network; one failed network never stops the others. Not retried after
      # a 5xx, a timeout or a lost connection: read the draft with get to see
      # what started. Requires ads:write.
      def launch(group_id, confirm_budget_amount: nil, confirm_budget_amounts: nil)
        body = Internal.drop_nil(
          {
            "confirm_budget_amount" => confirm_budget_amount,
            "confirm_budget_amounts" => confirm_budget_amounts
          }
        )
        @client.request(
          "POST", "/ads/drafts/#{Internal.path_segment(group_id)}/launch",
          json: body, retry_on: :rate_limit
        )
      end

      private

      def draft_body(objective:, platforms:, budget:, targeting:, ads:, name:, schedule:)
        Internal.drop_nil(
          {
            "name" => name,
            "objective" => objective,
            "platforms" => platforms.to_a,
            "budget" => budget,
            "schedule" => schedule,
            "targeting" => targeting,
            "ads" => ads.to_a
          }
        )
      end
    end
  end
end
