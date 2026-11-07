# frozen_string_literal: true

module OmniSocials
  module Resources
    # Ads resource: boosts, campaigns and "Create an ad" drafts on Meta,
    # Pinterest, TikTok, LinkedIn, X and Google.
    #
    # Ads spend real money once a campaign starts. Boosts and drafts are
    # created as drafts (no spend). Starting or raising spend needs a key with
    # the opt-in ads:spend scope ("Start ads", a second switch under "Ads";
    # its creator needs manage_ads): activate, activate_multi, resume, the
    # draft launch (drafts.launch), a budget raise or any change of a campaign
    # that reached the network through update, and the parity calls that
    # switch something on or raise a budget. Each repeats the amount. Without
    # ads:spend these calls answer 403 start_in_app with the page in the app
    # where a person does it; on Google (api_draft_only) they always do, also
    # with ads:spend. Pause and delete stay open, except on the networks in
    # api_stop_in_app (Google). The calls that start or raise spend are never
    # retried after a 5xx, a timeout or a lost connection (only a 429),
    # because the first attempt may have started the ad. Budgets are in major
    # currency units (10 = 10 EUR) in the ad account's currency. An Ads error
    # may carry "param" (the field at fault) in its body. Ad accounts are
    # connected and picked in the OmniSocials dashboard. The scopes ads:read
    # and ads:write are opt-in on the API key (the Ads switch).
    #
    # The Ads API parity sub-resources (objects, campaign_ads, comments,
    # targeting, audiences, lead_forms, leads, conversions, insights, reports,
    # rules, results, media, previews, partnership, accounts, reach_frequency,
    # studies, budget_schedules, google) are a thin passthrough. Every call
    # there that switches something on or can raise spend (objects.update,
    # objects.set_status, objects.duplicate, bulk_status, campaign_ads.add,
    # campaign_ads.set_status, rules.create, rules.update, rules.undo,
    # accounts.update_settings, reach_frequency.reserve, studies.create,
    # budget_schedules.create) needs a key with ads:spend (rules: else 403
    # rule_raises_spend), takes the person's own amount where it raises spend
    # (confirm_budget_amount, rules confirm_max_daily_budget) and follows the
    # same no-retry rule. Pausing, deleting and archiving stay open, except on
    # Google.
    class Ads
      # "Create an ad" drafts (an OmniSocials::Resources::AdDrafts).
      attr_reader :drafts
      # The Ads API parity sub-resource for campaigns, ad sets and ads of an ad account, also the ones made outside OmniSocials, and their import (an
      # OmniSocials::Resources::AdObjects).
      attr_reader :objects
      # The Ads API parity sub-resource for the ads of an OmniSocials campaign (an
      # OmniSocials::Resources::AdCampaignAds).
      attr_reader :campaign_ads
      # The Ads API parity sub-resource for comments on ads (an
      # OmniSocials::Resources::AdComments).
      attr_reader :comments
      # The Ads API parity sub-resource for targeting search, browse, reach estimate and bid suggestions (an
      # OmniSocials::Resources::AdTargeting).
      attr_reader :targeting
      # The Ads API parity sub-resource for custom audiences (an
      # OmniSocials::Resources::AdAudiences).
      attr_reader :audiences
      # The Ads API parity sub-resource for lead forms (an
      # OmniSocials::Resources::AdLeadForms).
      attr_reader :lead_forms
      # The Ads API parity sub-resource for leads copied from the lead forms (an
      # OmniSocials::Resources::AdLeads).
      attr_reader :leads
      # The Ads API parity sub-resource for pixels, conversion goals, custom conversions, server-side events (an
      # OmniSocials::Resources::AdConversions).
      attr_reader :conversions
      # The Ads API parity sub-resource for live numbers, analytics, timeline, ranking, alerts (an
      # OmniSocials::Resources::AdInsights).
      attr_reader :insights
      # The Ads API parity sub-resource for background reports (an
      # OmniSocials::Resources::AdReports).
      attr_reader :reports
      # The Ads API parity sub-resource for automated rules (an
      # OmniSocials::Resources::AdRules).
      attr_reader :rules
      # The Ads API parity sub-resource for your own numbers per campaign and day (an
      # OmniSocials::Resources::AdResults).
      attr_reader :results
      # The Ads API parity sub-resource for the network's own image and video library (an
      # OmniSocials::Resources::AdMedia).
      attr_reader :media
      # The Ads API parity sub-resource for previews drawn by the network (an
      # OmniSocials::Resources::AdPreviews).
      attr_reader :previews
      # The Ads API parity sub-resource for partnership ads (Meta) (an
      # OmniSocials::Resources::AdPartnership).
      attr_reader :partnership
      # The Ads API parity sub-resource for ad account admin (health, finance, settings, people, change log) (an
      # OmniSocials::Resources::AdAccountsAdmin).
      attr_reader :accounts
      # The Ads API parity sub-resource for Meta reach and frequency (an
      # OmniSocials::Resources::AdReachFrequency).
      attr_reader :reach_frequency
      # The Ads API parity sub-resource for A/B tests and lift studies (Meta) (an
      # OmniSocials::Resources::AdStudies).
      attr_reader :studies
      # The Ads API parity sub-resource for planned budget increases (Meta) (an
      # OmniSocials::Resources::AdBudgetSchedules).
      attr_reader :budget_schedules
      # The Ads API parity sub-resource for Google reports (an
      # OmniSocials::Resources::AdGoogle).
      attr_reader :google

      def initialize(client)
        @client = client
        @drafts = AdDrafts.new(client)
        @objects = AdObjects.new(client)
        @campaign_ads = AdCampaignAds.new(client)
        @comments = AdComments.new(client)
        @targeting = AdTargeting.new(client)
        @audiences = AdAudiences.new(client)
        @lead_forms = AdLeadForms.new(client)
        @leads = AdLeads.new(client)
        @conversions = AdConversions.new(client)
        @insights = AdInsights.new(client)
        @reports = AdReports.new(client)
        @rules = AdRules.new(client)
        @results = AdResults.new(client)
        @media = AdMedia.new(client)
        @previews = AdPreviews.new(client)
        @partnership = AdPartnership.new(client)
        @accounts = AdAccountsAdmin.new(client)
        @reach_frequency = AdReachFrequency.new(client)
        @studies = AdStudies.new(client)
        @budget_schedules = AdBudgetSchedules.new(client)
        @google = AdGoogle.new(client)
      end

      # GET /ads/accounts - the connected ad accounts, as { "data" => [...],
      # "platforms_available" => [...] }. Accounts are connected and picked in
      # the dashboard; only is_selected accounts can run campaigns. Requires
      # ads:read (opt-in on the API key).
      def list_accounts
        @client.request("GET", "/ads/accounts")
      end

      # GET /ads/capabilities - what each network accepts for a new ad (goals,
      # media, text limits, buttons, minimum daily budget), create_networks
      # and network_states ("live", "preview" or "coming_soon"), and per
      # network the "features" its API offers, "targeting_types",
      # "bid_strategies", "settings" and "ad_fields", plus "api_goals",
      # "api_draft_only" (networks where every API caller stops at the draft,
      # also a key with ads:spend: Google) and "api_stop_in_app" (networks
      # where the API may not even pause or delete a campaign that reached the
      # network: Google). Requires ads:read.
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

      # POST /ads/boost - boost a published post. Creates a DRAFT boost that
      # spends nothing; the person starts it in the app. budget is
      # { "type" => "daily", "amount" => 5, "currency" => "EUR" } in the ad
      # account's currency. TikTok needs creative "spark_auth_code", Google
      # needs "headlines", "descriptions" and "logo_url". Requires ads:write.
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

      # PATCH /ads/campaigns/{id} - change the name, budget, targeting or
      # schedule of a draft; objective and settings only while the campaign is
      # a draft (400 settings_locked after the start: duplicate it).
      #
      # A campaign that reached the network changes only with a key that has
      # ads:spend; without it, and on Google always, the call answers 403
      # start_in_app and a person changes it in the app. A higher budget on a
      # running campaign RAISES REAL AD SPEND: show the person the new amount
      # and get their yes first, then pass it again as confirm_budget_amount.
      # Not retried after a 5xx, a timeout or a lost connection: read the
      # campaign with get to see what happened. Requires ads:write.
      def update(campaign_id, name: nil, budget: nil, confirm_budget_amount: nil,
                 targeting: nil, schedule: nil, objective: nil, settings: nil)
        body = Internal.drop_nil(
          {
            "name" => name,
            "budget" => budget,
            "confirm_budget_amount" => confirm_budget_amount,
            "targeting" => targeting,
            "schedule" => schedule,
            "objective" => objective,
            "settings" => settings
          }
        )
        @client.request(
          "PATCH", "/ads/campaigns/#{Internal.path_segment(campaign_id)}",
          json: body, retry_on: :rate_limit
        )
      end

      # POST /ads/campaigns/{id}/activate - START REAL AD SPEND.
      #
      # Needs a key with the opt-in ads:spend scope ("Start ads"); without it,
      # and on Google (api_draft_only) always, the call answers 403
      # start_in_app with the page where a person does it in the app. Show the
      # person the budget (amount, currency, daily or lifetime) and get their
      # yes first; confirm_budget_amount must equal the campaign's budget
      # amount. A campaign of a draft group answers 409 use_draft_launch: use
      # ads.drafts.launch. Not retried after a 5xx, a timeout or a lost
      # connection: read the campaign with get to see what happened. Requires
      # ads:write.
      def activate(campaign_id, confirm_budget_amount)
        @client.request(
          "POST", "/ads/campaigns/#{Internal.path_segment(campaign_id)}/activate",
          json: { "confirm_budget_amount" => confirm_budget_amount }, retry_on: :rate_limit
        )
      end

      # POST /ads/campaigns/activate-multi - START REAL AD SPEND on up to 10
      # campaigns.
      #
      # Needs a key with ads:spend: without it, and on Google always, a result
      # answers "ok" => false with code start_in_app and the page where a
      # person starts it. Every campaign's budget must equal
      # confirm_budget_amount; show the person the total (amount x campaigns)
      # and get their yes first. Answers { "results" => [...] }. Not retried
      # after a 5xx, a timeout or a lost connection: read the campaigns with
      # get to see what happened. Requires ads:write.
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
      # review). Open with ads:write, except on the networks in
      # api_stop_in_app (Google): there a campaign that reached the network
      # answers 403 start_in_app. Requires ads:write.
      def pause(campaign_id)
        @client.request("POST", "/ads/campaigns/#{Internal.path_segment(campaign_id)}/pause")
      end

      # POST /ads/campaigns/{id}/resume - resume a paused campaign: it STARTS
      # REAL AD SPEND again. Needs a key with the opt-in ads:spend scope
      # ("Start ads"); without it, and on Google (api_draft_only) always, the
      # call answers 403 start_in_app with the page where a person does it in
      # the app. Only a paused campaign resumes (409 not_paused). Show the
      # person the budget and get their yes first. Not retried after a 5xx, a
      # timeout or a lost connection: read the campaign with get to see what
      # happened. Requires ads:write.
      def resume(campaign_id)
        @client.request(
          "POST", "/ads/campaigns/#{Internal.path_segment(campaign_id)}/resume",
          retry_on: :rate_limit
        )
      end

      # POST /ads/campaigns/bulk-status - pause or resume up to 50 campaigns
      # (status "paused" or "active").
      #
      # Resuming RESTARTS REAL AD SPEND: every campaign's budget must equal
      # confirm_budget_amount (one amount for all), checked before any change;
      # show the person the total and get their yes first. Resuming needs a
      # key with ads:spend: without it, and on Google always, a result answers
      # start_in_app. Pausing stays open (Google: start_in_app). Answers
      # { "data" => { "results" => [...] } }. Not retried after a 5xx, a
      # timeout or a lost connection. Requires ads:write.
      def bulk_status(campaign_ids:, status:, confirm_budget_amount: nil)
        @client.request(
          "POST", "/ads/campaigns/bulk-status",
          json: Internal.drop_nil(
            {
              "campaign_ids" => campaign_ids.to_a, "status" => status,
              "confirm_budget_amount" => confirm_budget_amount
            }
          ),
          retry_on: :rate_limit
        )
      end

      # POST /ads/campaigns/{id}/duplicate - copy a campaign as a new draft
      # (same ad account, goal, budget, targeting, settings and ads). A draft
      # never spends. Requires ads:write.
      def duplicate(campaign_id, name: nil)
        @client.request(
          "POST", "/ads/campaigns/#{Internal.path_segment(campaign_id)}/duplicate",
          json: Internal.drop_nil({ "name" => name })
        )
      end

      # DELETE /ads/campaigns/{id} - delete a campaign on the network too. A
      # campaign that spent is archived: its spend stays in the totals. Open
      # with ads:write, except on the networks in api_stop_in_app (Google):
      # there a campaign that reached the network answers 403 start_in_app.
      # Requires ads:write.
      def delete(campaign_id)
        @client.request("DELETE", "/ads/campaigns/#{Internal.path_segment(campaign_id)}")
      end

      # GET /ads/overview - accounts, campaigns per status and the totals.
      # totals["spend"] is nil when the campaigns use more than one currency
      # (totals["currency"] names the one currency): read totals_by_currency
      # then, one row per currency with "currency", "spend", "impressions" and
      # "clicks" (spend is never added across currencies). Requires ads:read.
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
    # the same ads. A draft never spends; launch starts it (a key with
    # ads:spend), or a person does in the app from its review_url.
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
      # objective is "traffic", "engagement", "awareness" or "video_views";
      # through the API also "lead_generation", "conversions", "messages" or
      # "calls" (each network's goal in ads.capabilities says what it
      # "needs"). platforms lists network keys ("meta", "pinterest",
      # "tiktok", "linkedin", "x", "google") or { "platform" => ...,
      # "budget_amount" => ..., "ad_account_id" => ..., "settings" => {...} }
      # per network (settings: bidding, conversion goal, lead form,
      # messaging). budget is the daily amount
      # per network, { "amount" => 10, "currency" => "EUR" }. schedule is
      # { "duration_days" => 7 } (nil runs until it is stopped). targeting
      # needs "countries"; "automatic_audience" => true lets the network find
      # the audience; "networks" => { "meta" => { "include" => {...},
      # "exclude" => {...}, "audiences" => {...} } } adds each network's own
      # targeting (ids from ads.targeting.search). Each of ads has "media",
      # "primary_text", "link" and optionally "headline", "description",
      # "cta", "primary_text_b" (an A/B test), "network" (per network extras
      # such as "lead_form_id", "media_ref", "spark_auth_code" or Google's
      # "responsive_search_ad") and, on Meta, "placement_media" => { "stories_reels" => {...} }
      # (an upright 9:16 file for Stories and Reels).
      #
      # Read ads.capabilities first for what each network accepts. The answer
      # carries review_url (the builder in the dashboard, where the person
      # checks and starts the ad: hand it over) and per network readiness. A
      # budget["currency"] other than the attached ad account's currency
      # answers 400 currency_mismatch with param "budget.currency". Requires
      # ads:write.
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

      # PUT /ads/drafts/{group_id} - replace the draft with the full body (the
      # same fields as create). Networks that already started are left alone
      # (campaigns[].editable). A budget["currency"] other than the attached
      # ad account's currency answers 400 currency_mismatch with param
      # "budget.currency". Requires ads:write.
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
      # Needs a key with the opt-in ads:spend scope ("Start ads"): without it
      # the call answers 403 start_in_app with the draft's page (its
      # review_url), and a network in api_draft_only (Google) is always
      # skipped with code start_in_app. Show the person the daily amount per
      # network and get their yes first, then pass it as confirm_budget_amount
      # (or per campaign id as confirm_budget_amounts). A wrong or missing
      # amount answers 400 budget_confirmation_required and writes nothing.
      # The answer is { "data" => { "group" => ..., "results" => [...] } }
      # with a result per network ("campaign_id" is a string); one failed
      # network never stops the others. Not retried after a 5xx, a timeout or
      # a lost connection: read the draft with get to see what started.
      # Requires ads:write.
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

    # -------------------------------------------------------------------------
    # Ads API parity (2026-11-05). Thin passthrough: the API checks every
    # field. A network without the feature answers 400
    # not_supported_on_network (ads.capabilities lists "features" per
    # network); a missing permission on the network side answers 403
    # network_permission_missing. Every call that switches something on or can
    # raise spend needs a key with ads:spend (without it, and on Google
    # always, 403 start_in_app; rules: 403 rule_raises_spend), takes the
    # person's own amount and is sent with retry_on: :rate_limit (never again
    # after a 5xx, a timeout or a lost connection). Pausing, deleting and
    # archiving stay open, except on Google.
    # -------------------------------------------------------------------------

    # Shared path helpers of the ads sub-resources.
    module AdPaths
      private

      def seg(value)
        Internal.path_segment(value)
      end

      def object_path(account_id, level, external_id)
        "/ads/accounts/#{seg(account_id)}/objects/#{seg(level)}/#{seg(external_id)}"
      end

      def ad_path(campaign_id, ad_id)
        "/ads/campaigns/#{seg(campaign_id)}/ads/#{seg(ad_id)}"
      end

      def account_path(account_id, rest)
        "/ads/accounts/#{seg(account_id)}/#{rest}"
      end

      def list_param(value)
        Internal.join_list(value)
      end
    end

    # Campaigns, ad sets and ads of an ad account as the network has them,
    # also the ones made outside OmniSocials, and the import of those
    # campaigns. level is "campaign", "ad_set" or "ad". Objects of OmniSocials
    # campaigns answer 409 use_campaign_routes: change those with the
    # campaign methods.
    class AdObjects
      include AdPaths

      def initialize(client)
        @client = client
      end

      # GET /ads/accounts/{accountId}/tree - campaigns, ad sets and ads with
      # the numbers of the date range (from / to, ISO dates; at most 90 days,
      # default the last 30). Each campaign says "source" ("omnisocials" or
      # "external"). status is an Array or a comma list. Requires ads:read.
      def tree(account_id, from: nil, to: nil, status: nil, limit: nil, cursor: nil)
        @client.request(
          "GET", account_path(account_id, "tree"),
          query: {
            "from" => from, "to" => to, "status" => list_param(status),
            "limit" => limit, "cursor" => cursor
          }
        )
      end

      # GET /ads/accounts/{accountId}/objects/{level}/{externalId} - live
      # details of one object. Requires ads:read.
      def get(account_id, level, external_id)
        @client.request("GET", object_path(account_id, level, external_id))
      end

      # PATCH /ads/accounts/{accountId}/objects/{level}/{externalId} - change
      # the name, budget or end date (end_at: nil removes it) of a campaign
      # or ad set made outside OmniSocials.
      #
      # A higher budget RAISES REAL AD SPEND: show the person the new amount
      # and get their yes first, then pass it as confirm_budget_amount. It
      # changes the campaign on the network: needs a key with the opt-in
      # ads:spend scope ("Start ads"); without it, and on Google
      # (api_draft_only) always, the call answers 403 start_in_app with the
      # page where a person does it in the app. Not retried after a 5xx, a
      # timeout or a lost connection: read the object with get. Requires
      # ads:write.
      def update(account_id, level, external_id, name: nil, budget: nil, end_at: OmniSocials::NOT_GIVEN,
                 confirm_budget_amount: nil)
        body = Internal.drop_nil(
          { "name" => name, "budget" => budget, "confirm_budget_amount" => confirm_budget_amount }
        )
        body["end_at"] = end_at unless end_at.is_a?(NotGiven)
        @client.request(
          "PATCH", object_path(account_id, level, external_id),
          json: body, retry_on: :rate_limit
        )
      end

      # PUT /ads/accounts/{accountId}/objects/{level}/{externalId}/status -
      # status is "paused" or "active".
      #
      # Switching on STARTS REAL AD SPEND: pass the budget that pays (the
      # object's own or its parent's) as confirm_budget_amount after the
      # person agreed. Switching on: needs a key with the opt-in ads:spend
      # scope ("Start ads"); without it, and on Google (api_draft_only)
      # always, the call answers 403 start_in_app with the page where a person
      # does it in the app. Pausing needs nothing and stays open (Google:
      # start_in_app). Not retried after a 5xx, a timeout or a lost
      # connection. Requires ads:write.
      def set_status(account_id, level, external_id, status:, confirm_budget_amount: nil)
        @client.request(
          "PUT", "#{object_path(account_id, level, external_id)}/status",
          json: Internal.drop_nil(
            { "status" => status, "confirm_budget_amount" => confirm_budget_amount }
          ),
          retry_on: :rate_limit
        )
      end

      # POST /ads/accounts/{accountId}/objects/{level}/{externalId}/duplicate -
      # copy an object made outside OmniSocials; the copy is paused (Meta
      # today). It changes the ad account on the network: needs a key with the
      # opt-in ads:spend scope ("Start ads"); without it, and on Google
      # (api_draft_only) always, the call answers 403 start_in_app with the
      # page where a person does it in the app. Requires ads:write.
      def duplicate(account_id, level, external_id, deep: nil, rename: nil)
        @client.request(
          "POST", "#{object_path(account_id, level, external_id)}/duplicate",
          json: Internal.drop_nil({ "deep" => deep, "rename" => rename })
        )
      end

      # GET /ads/accounts/{accountId}/import - the import state of the
      # campaigns made outside OmniSocials. Requires ads:read.
      def import_status(account_id)
        @client.request("GET", account_path(account_id, "import"))
      end

      # POST /ads/accounts/{accountId}/import - read the ad account again at
      # the next sync (within 15 minutes). The first import reads 90 days;
      # webhook ads.initial_sync_completed when it is done. Requires
      # ads:write.
      def start_import(account_id)
        @client.request("POST", account_path(account_id, "import"))
      end

      # GET /ads/external-campaigns - the imported campaigns (limit at most
      # 200). Requires ads:read.
      def list_external(ad_account_id: nil, platform: nil, status: nil, limit: nil, offset: nil)
        @client.request(
          "GET", "/ads/external-campaigns",
          query: {
            "ad_account_id" => ad_account_id, "platform" => platform, "status" => status,
            "limit" => limit, "offset" => offset
          }
        )
      end

      # GET /ads/external-campaigns/{id} - one imported campaign with its
      # daily numbers. Requires ads:read.
      def get_external(campaign_id, from: nil, to: nil)
        @client.request(
          "GET", "/ads/external-campaigns/#{seg(campaign_id)}",
          query: { "from" => from, "to" => to }
        )
      end
    end

    # The ads of an OmniSocials campaign.
    class AdCampaignAds
      include AdPaths

      def initialize(client)
        @client = client
      end

      # GET /ads/campaigns/{id}/ads - the ads with their status, review and
      # latest numbers. Requires ads:read.
      def list(campaign_id)
        @client.request("GET", "/ads/campaigns/#{seg(campaign_id)}/ads")
      end

      # POST /ads/campaigns/{id}/ads - add up to 6 ads (the shape of a draft
      # ad) to a campaign that runs. They are created PAUSED on the network;
      # switch each one on with set_status. Needs a key with the opt-in
      # ads:spend scope ("Start ads"); without it, and on Google
      # (api_draft_only) always, the call answers 403 start_in_app with the
      # page where a person does it in the app. Webhook ad.created. Requires
      # ads:write.
      def add(campaign_id, ads)
        @client.request("POST", "/ads/campaigns/#{seg(campaign_id)}/ads", json: { "ads" => ads.to_a })
      end

      # GET /ads/campaigns/{id}/ads/{adId} - one ad. Requires ads:read.
      def get(campaign_id, ad_id)
        @client.request("GET", ad_path(campaign_id, ad_id))
      end

      # PUT /ads/campaigns/{id}/ads/{adId}/status - "paused" or "active".
      #
      # Switching on STARTS REAL AD SPEND: pass the campaign budget as
      # confirm_budget_amount after the person agreed. Switching on: needs a
      # key with the opt-in ads:spend scope ("Start ads"); without it, and on
      # Google (api_draft_only) always, the call answers 403 start_in_app with
      # the page where a person does it in the app. Pausing stays open
      # (Google: start_in_app). Not retried after a 5xx, a timeout or a lost
      # connection. Webhook ad.updated. Requires ads:write.
      def set_status(campaign_id, ad_id, status:, confirm_budget_amount: nil)
        @client.request(
          "PUT", "#{ad_path(campaign_id, ad_id)}/status",
          json: Internal.drop_nil(
            { "status" => status, "confirm_budget_amount" => confirm_budget_amount }
          ),
          retry_on: :rate_limit
        )
      end

      # GET /ads/campaigns/{id}/ads/{adId}/review - the network's review
      # verdict ("in_review", "approved" or "rejected" with reasons).
      # Requires ads:read.
      def review(campaign_id, ad_id)
        @client.request("GET", "#{ad_path(campaign_id, ad_id)}/review")
      end
    end

    # Comments on an ad of an OmniSocials campaign.
    class AdComments
      include AdPaths

      def initialize(client)
        @client = client
      end

      # GET /ads/campaigns/{id}/ads/{adId}/comments. Requires ads:read.
      def list(campaign_id, ad_id, cursor: nil)
        @client.request("GET", "#{ad_path(campaign_id, ad_id)}/comments", query: { "cursor" => cursor })
      end

      # POST /ads/campaigns/{id}/ads/{adId}/comments/{commentId}/reply -
      # answer a comment. Requires ads:write.
      def reply(campaign_id, ad_id, comment_id, text)
        @client.request(
          "POST", "#{ad_path(campaign_id, ad_id)}/comments/#{seg(comment_id)}/reply",
          json: { "text" => text }
        )
      end

      # POST /ads/campaigns/{id}/ads/{adId}/comments/{commentId}/hide - hide
      # (default) or show a comment. Requires ads:write.
      def hide(campaign_id, ad_id, comment_id, hidden: true)
        @client.request(
          "POST", "#{ad_path(campaign_id, ad_id)}/comments/#{seg(comment_id)}/hide",
          json: { "hidden" => hidden }
        )
      end

      # DELETE /ads/campaigns/{id}/ads/{adId}/comments/{commentId}. Requires
      # ads:write.
      def delete(campaign_id, ad_id, comment_id)
        @client.request("DELETE", "#{ad_path(campaign_id, ad_id)}/comments/#{seg(comment_id)}")
      end
    end

    # Targeting options of a network. The ids go in
    # targeting["networks"][<network>]["include"] of a draft (or
    # targeting["network"] of a campaign); the types per network are
    # ads.capabilities "targeting_types".
    class AdTargeting
      def initialize(client)
        @client = client
      end

      # GET /ads/targeting/search - interests, places, languages, job titles
      # ... (limit at most 100). Requires ads:read.
      def search(ad_account_id:, type:, q:, limit: nil, country: nil)
        @client.request(
          "GET", "/ads/targeting/search",
          query: {
            "ad_account_id" => ad_account_id, "type" => type, "q" => q,
            "limit" => limit, "country" => country
          }
        )
      end

      # GET /ads/targeting/browse - the categories as a tree. Requires
      # ads:read.
      def browse(ad_account_id:, type:)
        @client.request(
          "GET", "/ads/targeting/browse", query: { "ad_account_id" => ad_account_id, "type" => type }
        )
      end

      # POST /ads/targeting/reach-estimate - the audience size of a targeting
      # ("countries", "age_min", "age_max", "genders", "network"). Read-only.
      # Requires ads:read.
      def reach_estimate(ad_account_id:, targeting:, objective: nil)
        @client.request(
          "POST", "/ads/targeting/reach-estimate",
          json: Internal.drop_nil(
            { "ad_account_id" => ad_account_id, "objective" => objective, "targeting" => targeting }
          )
        )
      end

      # POST /ads/targeting/bid-suggestions - a suggested bid and daily
      # budget. Read-only. Requires ads:read.
      def bid_suggestions(ad_account_id:, targeting:, objective: nil, budget: nil)
        @client.request(
          "POST", "/ads/targeting/bid-suggestions",
          json: Internal.drop_nil(
            {
              "ad_account_id" => ad_account_id, "objective" => objective,
              "targeting" => targeting, "budget" => budget
            }
          )
        )
      end
    end

    # Custom audiences of an ad account: customer lists, lookalikes and
    # company lists. audience_id is the network's audience id.
    class AdAudiences
      include AdPaths

      def initialize(client)
        @client = client
      end

      # GET /ads/audiences. Requires ads:read.
      def list(ad_account_id:, cursor: nil)
        @client.request(
          "GET", "/ads/audiences", query: { "ad_account_id" => ad_account_id, "cursor" => cursor }
        )
      end

      # POST /ads/audiences - kind is "customer_list", "lookalike" (lookalike:
      # { "source_audience_id", "country", "ratio" }, ratio 0.01 to 0.2) or
      # "company_list". customer_file_source (Meta: "user_provided",
      # "partner_provided" or "both") is what the person says. schema + rows
      # are optional first members of a customer list (Pinterest needs
      # them); raw values are hashed with SHA-256 before they leave.
      # Requires ads:write.
      def create(ad_account_id:, name:, description: nil, kind: nil, lookalike: nil,
                 customer_file_source: nil, schema: nil, rows: nil)
        @client.request(
          "POST", "/ads/audiences",
          json: Internal.drop_nil(
            {
              "ad_account_id" => ad_account_id, "name" => name, "description" => description,
              "kind" => kind, "lookalike" => lookalike,
              "customer_file_source" => customer_file_source,
              "schema" => schema&.to_a, "rows" => rows&.to_a
            }
          )
        )
      end

      # GET /ads/audiences/{audienceId}. Requires ads:read.
      def get(audience_id, ad_account_id:)
        @client.request(
          "GET", "/ads/audiences/#{seg(audience_id)}", query: { "ad_account_id" => ad_account_id }
        )
      end

      # PATCH /ads/audiences/{audienceId} - rename. Requires ads:write.
      def update(audience_id, ad_account_id:, name: nil, description: nil)
        @client.request(
          "PATCH", "/ads/audiences/#{seg(audience_id)}",
          json: Internal.drop_nil(
            { "ad_account_id" => ad_account_id, "name" => name, "description" => description }
          )
        )
      end

      # DELETE /ads/audiences/{audienceId}. Requires ads:write.
      def delete(audience_id, ad_account_id:)
        @client.request(
          "DELETE", "/ads/audiences/#{seg(audience_id)}", query: { "ad_account_id" => ad_account_id }
        )
      end

      # POST /ads/audiences/{audienceId}/members - add people to a customer
      # list. Send the raw values: OmniSocials normalizes them and hashes
      # them with SHA-256 before they leave and stores nothing. At most
      # 10,000 rows. schema keys: email, phone, first_name, last_name, city,
      # state, zip, country, external_id, dob_year, gender, maid. Requires
      # ads:write.
      def add_members(audience_id, ad_account_id:, schema:, rows:)
        @client.request(
          "POST", "/ads/audiences/#{seg(audience_id)}/members",
          json: { "ad_account_id" => ad_account_id, "schema" => schema.to_a, "rows" => rows.to_a }
        )
      end

      # DELETE /ads/audiences/{audienceId}/members - remove people (the same
      # body as add_members). Requires ads:write.
      def remove_members(audience_id, ad_account_id:, schema:, rows:)
        @client.request(
          "DELETE", "/ads/audiences/#{seg(audience_id)}/members",
          json: { "ad_account_id" => ad_account_id, "schema" => schema.to_a, "rows" => rows.to_a }
        )
      end

      # POST /ads/audiences/{audienceId}/companies - add companies ("name",
      # "domain", "linkedin_url") to a company list (LinkedIn). Requires
      # ads:write.
      def add_companies(audience_id, ad_account_id:, companies:)
        @client.request(
          "POST", "/ads/audiences/#{seg(audience_id)}/companies",
          json: { "ad_account_id" => ad_account_id, "companies" => companies.to_a }
        )
      end
    end

    # Lead forms (Meta: the workspace's Page). form_id is the OmniSocials
    # form id; a form's "external_id" goes in settings "lead_form_id".
    class AdLeadForms
      include AdPaths

      def initialize(client)
        @client = client
      end

      # GET /ads/lead-forms. Requires ads:read.
      def list(ad_account_id:)
        @client.request("GET", "/ads/lead-forms", query: { "ad_account_id" => ad_account_id })
      end

      # POST /ads/lead-forms. accept_terms: true says the person accepts the
      # network's lead ad terms (Pinterest refuses a form without it): only
      # send it after the person said yes. Requires ads:write.
      def create(ad_account_id:, name:, privacy_policy_url:, questions:, thank_you:, locale: nil,
                 headline: nil, description: nil, accept_terms: nil)
        @client.request(
          "POST", "/ads/lead-forms",
          json: Internal.drop_nil(
            {
              "ad_account_id" => ad_account_id, "name" => name,
              "privacy_policy_url" => privacy_policy_url, "locale" => locale,
              "headline" => headline, "description" => description,
              "questions" => questions.to_a, "thank_you" => thank_you,
              "accept_terms" => accept_terms
            }
          )
        )
      end

      # GET /ads/lead-forms/{formId}. Requires ads:read.
      def get(form_id)
        @client.request("GET", "/ads/lead-forms/#{seg(form_id)}")
      end

      # PATCH /ads/lead-forms/{formId} - archive or open a form (status
      # "archived" or "active"), or switch its lead sync. Requires ads:write.
      def update(form_id, status: nil, sync_enabled: nil)
        @client.request(
          "PATCH", "/ads/lead-forms/#{seg(form_id)}",
          json: Internal.drop_nil({ "status" => status, "sync_enabled" => sync_enabled })
        )
      end

      # DELETE /ads/lead-forms/{formId} - archive a form (the leads already
      # copied stay). Requires ads:write.
      def delete(form_id)
        @client.request("DELETE", "/ads/lead-forms/#{seg(form_id)}")
      end

      # POST /ads/lead-forms/{formId}/test-leads - a test lead (the next sync
      # copies it, marked is_test). Requires ads:write.
      def send_test_lead(form_id, fields: nil)
        @client.request(
          "POST", "/ads/lead-forms/#{seg(form_id)}/test-leads",
          json: Internal.drop_nil({ "fields" => fields })
        )
      end
    end

    # Leads of the workspace, copied from the networks every 15 minutes
    # (webhook lead.received). The answers are personal data.
    class AdLeads
      include AdPaths

      def initialize(client)
        @client = client
      end

      # GET /ads/leads - newest first (limit at most 200). Requires ads:read.
      def list(form_id: nil, status: nil, since: nil, until_time: nil, limit: nil, cursor: nil)
        @client.request(
          "GET", "/ads/leads",
          query: {
            "form_id" => form_id, "status" => status, "since" => since,
            "until" => until_time, "limit" => limit, "cursor" => cursor
          }
        )
      end

      # GET /ads/leads/counts - "total" and "by_status". Requires ads:read.
      def counts(form_id: nil)
        @client.request("GET", "/ads/leads/counts", query: { "form_id" => form_id })
      end

      # PATCH /ads/leads/{leadId} - status is "new", "contacted",
      # "qualified", "won", "lost" or "spam". Requires ads:write.
      def update(lead_id, status: nil, note: nil)
        @client.request(
          "PATCH", "/ads/leads/#{seg(lead_id)}",
          json: Internal.drop_nil({ "status" => status, "note" => note })
        )
      end
    end

    # Pixels, conversion goals, custom conversions and server-side
    # conversion events.
    class AdConversions
      def initialize(client)
        @client = client
      end

      # GET /ads/conversions/destinations - pixels, datasets, conversion tags
      # and conversion actions. Requires ads:read.
      def destinations(ad_account_id:)
        @client.request(
          "GET", "/ads/conversions/destinations", query: { "ad_account_id" => ad_account_id }
        )
      end

      # GET /ads/conversions/goals - the events a campaign can optimise for.
      # Requires ads:read.
      def goals(ad_account_id:)
        @client.request("GET", "/ads/conversions/goals", query: { "ad_account_id" => ad_account_id })
      end

      # POST /ads/conversions/custom - a custom conversion (a URL rule and/or
      # an event on a pixel). Requires ads:write.
      def create_custom(ad_account_id:, name:, destination_id:, event: nil, url_contains: nil)
        @client.request(
          "POST", "/ads/conversions/custom",
          json: Internal.drop_nil(
            {
              "ad_account_id" => ad_account_id, "name" => name,
              "destination_id" => destination_id, "event" => event,
              "url_contains" => url_contains
            }
          )
        )
      end

      # POST /ads/conversions/events - up to 1,000 conversion events from
      # your server. Send the raw email and phone: OmniSocials normalizes
      # and SHA-256 hashes them before they leave and stores nothing.
      # Requires ads:write.
      def send_events(ad_account_id:, destination_id:, events:)
        @client.request(
          "POST", "/ads/conversions/events",
          json: {
            "ad_account_id" => ad_account_id, "destination_id" => destination_id,
            "events" => events.to_a
          }
        )
      end
    end

    # Body of ads.insights.query and ads.reports.start.
    module AdInsightsBody
      private

      def insights_body(ad_account_id:, level:, ids:, metrics:, breakdowns:, from:, to:, time_increment:)
        Internal.drop_nil(
          {
            "ad_account_id" => ad_account_id, "level" => level, "ids" => ids&.to_a,
            "metrics" => metrics&.to_a, "breakdowns" => breakdowns&.to_a,
            "from" => from, "to" => to, "time_increment" => time_increment
          }
        )
      end
    end

    # Numbers: live from the network, per campaign or ad, over time, ranked,
    # and what needs attention.
    class AdInsights
      include AdPaths
      include AdInsightsBody

      def initialize(client)
        @client = client
      end

      # POST /ads/insights - live numbers from the network by day, ad,
      # country, age, gender, placement, device or platform (at most 2
      # breakdowns). Read-only. Requires ads:read.
      def query(ad_account_id:, level: nil, ids: nil, metrics: nil, breakdowns: nil, from: nil,
                to: nil, time_increment: nil)
        @client.request(
          "POST", "/ads/insights",
          json: insights_body(
            ad_account_id: ad_account_id, level: level, ids: ids, metrics: metrics,
            breakdowns: breakdowns, from: from, to: to, time_increment: time_increment
          )
        )
      end

      # GET /ads/campaigns/{id}/analytics - numbers of an OmniSocials campaign
      # (breakdown: "ad" gives one row per ad). Requires ads:read.
      def campaign(campaign_id, from: nil, to: nil, breakdown: nil, time_increment: nil, metrics: nil)
        @client.request(
          "GET", "/ads/campaigns/#{seg(campaign_id)}/analytics",
          query: {
            "from" => from, "to" => to, "breakdown" => breakdown,
            "time_increment" => time_increment, "metrics" => list_param(metrics)
          }
        )
      end

      # GET /ads/campaigns/{id}/ads/{adId}/analytics - numbers of one ad.
      # Requires ads:read.
      def ad(campaign_id, ad_id, from: nil, to: nil, breakdown: nil)
        @client.request(
          "GET", "#{ad_path(campaign_id, ad_id)}/analytics",
          query: { "from" => from, "to" => to, "breakdown" => breakdown }
        )
      end

      # GET /ads/timeline - daily totals of the workspace (source "all",
      # "omnisocials" or "external"). Requires ads:read.
      def timeline(from: nil, to: nil, platform: nil, source: nil)
        @client.request(
          "GET", "/ads/timeline",
          query: { "from" => from, "to" => to, "platform" => platform, "source" => source }
        )
      end

      # GET /ads/performance - campaigns or ads ranked by one metric.
      # Requires ads:read.
      def performance(level: nil, metric: nil, order: nil, limit: nil, min_impressions: nil,
                      from: nil, to: nil, platform: nil)
        @client.request(
          "GET", "/ads/performance",
          query: {
            "level" => level, "metric" => metric, "order" => order, "limit" => limit,
            "min_impressions" => min_impressions, "from" => from, "to" => to,
            "platform" => platform
          }
        )
      end

      # GET /ads/alerts - rejected ads, held campaigns, sign-in or payment
      # problems, no delivery. Requires ads:read.
      def alerts
        @client.request("GET", "/ads/alerts")
      end
    end

    # Long reports that run in the background (up to 730 days).
    class AdReports
      include AdPaths
      include AdInsightsBody

      def initialize(client)
        @client = client
      end

      # GET /ads/insights/reports. Requires ads:read.
      def list
        @client.request("GET", "/ads/insights/reports")
      end

      # POST /ads/insights/reports - start a report with the fields of
      # ads.insights.query; poll get. Requires ads:read.
      def start(ad_account_id:, level: nil, ids: nil, metrics: nil, breakdowns: nil, from: nil,
                to: nil, time_increment: nil)
        @client.request(
          "POST", "/ads/insights/reports",
          json: insights_body(
            ad_account_id: ad_account_id, level: level, ids: ids, metrics: metrics,
            breakdowns: breakdowns, from: from, to: to, time_increment: time_increment
          )
        )
      end

      # GET /ads/insights/reports/{reportId} - "running", "done" (with rows)
      # or "failed". Requires ads:read.
      def get(report_id)
        @client.request("GET", "/ads/insights/reports/#{seg(report_id)}")
      end
    end

    # Automated rules: check campaigns on a schedule and notify, pause,
    # activate or adjust the budget. A rule that notifies, pauses or lowers a
    # budget works with ads:write. A rule that can raise spend ("activate", a
    # positive "adjust_budget") needs a key with ads:spend (else 403
    # rule_raises_spend) and action "max_daily_budget", confirmed by the
    # person as confirm_max_daily_budget; it never acts on Google. create,
    # update and undo are not retried after a 5xx, a timeout or a lost
    # connection.
    class AdRules
      include AdPaths

      def initialize(client)
        @client = client
      end

      # GET /ads/rules. Requires ads:read.
      def list
        @client.request("GET", "/ads/rules")
      end

      # POST /ads/rules - a new rule, off until enabled: true.
      #
      # A rule that can RAISE REAL AD SPEND ("activate", a positive
      # "adjust_budget") needs the person's own ceiling as
      # confirm_max_daily_budget and a key with ads:spend (else 403
      # rule_raises_spend). Preview it first with preview. Not retried after a
      # 5xx, a timeout or a lost connection: read the rules with list.
      # Requires ads:write.
      def create(name:, conditions:, action:, ad_account_id: nil, enabled: nil, scope: nil,
                 every_minutes: nil, cooldown_minutes: nil, max_actions_per_run: nil,
                 confirm_max_daily_budget: nil)
        @client.request(
          "POST", "/ads/rules",
          json: rule_body(
            name: name, conditions: conditions, action: action, ad_account_id: ad_account_id,
            enabled: enabled, scope: scope, every_minutes: every_minutes,
            cooldown_minutes: cooldown_minutes, max_actions_per_run: max_actions_per_run,
            confirm_max_daily_budget: confirm_max_daily_budget
          ),
          retry_on: :rate_limit
        )
      end

      # GET /ads/rules/templates - ready-made rules. Requires ads:read.
      def templates
        @client.request("GET", "/ads/rules/templates")
      end

      # POST /ads/rules/preview - what an unsaved rule would match and do
      # now. Requires ads:read.
      def preview(conditions:, action:, name: nil, ad_account_id: nil, scope: nil)
        @client.request(
          "POST", "/ads/rules/preview",
          json: Internal.drop_nil(
            {
              "name" => name, "ad_account_id" => ad_account_id, "scope" => scope,
              "conditions" => conditions.to_a, "action" => action
            }
          )
        )
      end

      # GET /ads/rules/activity - every change the rules made, with before
      # and after. Requires ads:read.
      def activity(rule_id: nil, limit: nil)
        @client.request("GET", "/ads/rules/activity", query: { "rule_id" => rule_id, "limit" => limit })
      end

      # POST /ads/rules/activity/{activityId}/undo - undo a change a rule
      # made.
      #
      # Undo of a pause or of a budget cut RESTARTS or RAISES REAL AD SPEND:
      # pass the amount as confirm_budget_amount after the person agreed, with
      # a key that has ads:spend (else, and on Google always, 403
      # start_in_app). Not retried after a 5xx, a timeout or a lost
      # connection. Requires ads:write.
      def undo(activity_id, confirm_budget_amount: nil)
        @client.request(
          "POST", "/ads/rules/activity/#{seg(activity_id)}/undo",
          json: Internal.drop_nil({ "confirm_budget_amount" => confirm_budget_amount }),
          retry_on: :rate_limit
        )
      end

      # GET /ads/rules/{ruleId}. Requires ads:read.
      def get(rule_id)
        @client.request("GET", "/ads/rules/#{seg(rule_id)}")
      end

      # PATCH /ads/rules/{ruleId} - change a rule (also enabled). A changed
      # action that can raise spend needs confirm_max_daily_budget again and a
      # key with ads:spend (else 403 rule_raises_spend). Not retried after a
      # 5xx, a timeout or a lost connection. Requires ads:write.
      def update(rule_id, name: nil, conditions: nil, action: nil, ad_account_id: nil, enabled: nil,
                 scope: nil, every_minutes: nil, cooldown_minutes: nil, max_actions_per_run: nil,
                 confirm_max_daily_budget: nil)
        @client.request(
          "PATCH", "/ads/rules/#{seg(rule_id)}",
          json: rule_body(
            name: name, conditions: conditions, action: action, ad_account_id: ad_account_id,
            enabled: enabled, scope: scope, every_minutes: every_minutes,
            cooldown_minutes: cooldown_minutes, max_actions_per_run: max_actions_per_run,
            confirm_max_daily_budget: confirm_max_daily_budget
          ),
          retry_on: :rate_limit
        )
      end

      # DELETE /ads/rules/{ruleId}. Requires ads:write.
      def delete(rule_id)
        @client.request("DELETE", "/ads/rules/#{seg(rule_id)}")
      end

      # POST /ads/rules/{ruleId}/preview - what a saved rule would match and
      # do now. Requires ads:read.
      def preview_saved(rule_id)
        @client.request("POST", "/ads/rules/#{seg(rule_id)}/preview")
      end

      # GET /ads/rules/{ruleId}/runs. Requires ads:read.
      def runs(rule_id, limit: nil)
        @client.request("GET", "/ads/rules/#{seg(rule_id)}/runs", query: { "limit" => limit })
      end

      private

      def rule_body(name:, conditions:, action:, ad_account_id:, enabled:, scope:, every_minutes:,
                    cooldown_minutes:, max_actions_per_run:, confirm_max_daily_budget:)
        Internal.drop_nil(
          {
            "name" => name, "ad_account_id" => ad_account_id, "enabled" => enabled,
            "scope" => scope, "conditions" => conditions&.to_a, "action" => action,
            "every_minutes" => every_minutes, "cooldown_minutes" => cooldown_minutes,
            "max_actions_per_run" => max_actions_per_run,
            "confirm_max_daily_budget" => confirm_max_daily_budget
          }
        )
      end
    end

    # Your own numbers per campaign and day (qualified leads, sales,
    # revenue). Rules read them as results.<metric>.
    class AdResults
      include AdPaths

      def initialize(client)
        @client = client
      end

      # GET /ads/campaign-results. Requires ads:read.
      def list(from: nil, to: nil, campaign_id: nil, metric: nil)
        @client.request(
          "GET", "/ads/campaign-results",
          query: { "from" => from, "to" => to, "campaign_id" => campaign_id, "metric" => metric }
        )
      end

      # POST /ads/campaign-results - up to 5,000 rows of "day", "metric",
      # "value" and the campaign ("campaign_id", "external_campaign_id" +
      # "platform", "utm_campaign" or "campaign_name"). Sending a day again
      # replaces it. Requires ads:write.
      def upload(rows)
        @client.request("POST", "/ads/campaign-results", json: { "rows" => rows.to_a })
      end

      # GET /ads/campaign-results/totals - totals over a period, with the
      # formulas. Requires ads:read.
      def totals(from: nil, to: nil, campaign_id: nil)
        @client.request(
          "GET", "/ads/campaign-results/totals",
          query: { "from" => from, "to" => to, "campaign_id" => campaign_id }
        )
      end

      # GET /ads/campaign-results/metrics - your metric names and formulas.
      # Requires ads:read.
      def metrics
        @client.request("GET", "/ads/campaign-results/metrics")
      end

      # PUT /ads/campaign-results/metrics/{key} - name a metric or define a
      # formula (unit "number", "money" or "percent"). Requires ads:write.
      def put_metric(key, label: nil, unit: nil, formula: nil)
        @client.request(
          "PUT", "/ads/campaign-results/metrics/#{seg(key)}",
          json: Internal.drop_nil({ "label" => label, "unit" => unit, "formula" => formula })
        )
      end
    end

    # The network's own image and video library of an ad account. Use an id
    # in an ad as network[<network>]["media_ref"].
    class AdMedia
      include AdPaths

      def initialize(client)
        @client = client
      end

      # GET /ads/media. Requires ads:read.
      def list(ad_account_id:, type: nil, cursor: nil)
        @client.request(
          "GET", "/ads/media",
          query: { "ad_account_id" => ad_account_id, "type" => type, "cursor" => cursor }
        )
      end

      # POST /ads/media - upload an image or video to the network ahead of an
      # ad. Requires ads:write.
      def upload(ad_account_id:, type:, url:, name: nil)
        @client.request(
          "POST", "/ads/media",
          json: Internal.drop_nil(
            { "ad_account_id" => ad_account_id, "type" => type, "url" => url, "name" => name }
          )
        )
      end

      # GET /ads/media/{mediaId} - the processing status of an upload.
      # Requires ads:read.
      def get(media_id, ad_account_id:, type: nil)
        @client.request(
          "GET", "/ads/media/#{seg(media_id)}",
          query: { "ad_account_id" => ad_account_id, "type" => type }
        )
      end

      # DELETE /ads/media/{mediaId}. Requires ads:write.
      def delete(media_id, ad_account_id:, type:)
        @client.request(
          "DELETE", "/ads/media/#{seg(media_id)}",
          query: { "ad_account_id" => ad_account_id, "type" => type }
        )
      end
    end

    # Previews drawn by the network.
    class AdPreviews
      include AdPaths

      def initialize(client)
        @client = client
      end

      # POST /ads/previews - previews of a new ad (the shape of a draft ad).
      # Read-only. Requires ads:read.
      def create(ad_account_id:, ad:, placements: nil, objective: nil)
        @client.request(
          "POST", "/ads/previews",
          json: Internal.drop_nil(
            {
              "ad_account_id" => ad_account_id, "ad" => ad,
              "placements" => placements&.to_a, "objective" => objective
            }
          )
        )
      end

      # GET /ads/campaigns/{id}/ads/{adId}/previews - previews of an existing
      # ad. Requires ads:read.
      def for_ad(campaign_id, ad_id, placements: nil)
        @client.request(
          "GET", "#{ad_path(campaign_id, ad_id)}/previews",
          query: { "placements" => list_param(placements) }
        )
      end
    end

    # Partnership ads with creators (Meta).
    class AdPartnership
      def initialize(client)
        @client = client
      end

      # GET /ads/partnership/content - creator posts you may run as
      # partnership ads. Requires ads:read.
      def list_content(ad_account_id:)
        @client.request("GET", "/ads/partnership/content", query: { "ad_account_id" => ad_account_id })
      end

      # GET /ads/partnership/permissions. Requires ads:read.
      def list_permissions(ad_account_id:)
        @client.request(
          "GET", "/ads/partnership/permissions", query: { "ad_account_id" => ad_account_id }
        )
      end

      # POST /ads/partnership/permissions - ask for or set a permission;
      # Meta's fields pass through as keyword arguments. Requires ads:write.
      def set_permission(ad_account_id:, **fields)
        @client.request(
          "POST", "/ads/partnership/permissions",
          json: stringify(fields).merge("ad_account_id" => ad_account_id)
        )
      end

      private

      def stringify(fields)
        fields.each_with_object({}) { |(key, value), out| out[key.to_s] = value }
      end
    end

    # Ad account admin: identities, health, finance, settings, people,
    # change log, businesses, DSA and the manager hierarchy. account_id is
    # the OmniSocials ad account id.
    class AdAccountsAdmin
      include AdPaths

      def initialize(client)
        @client = client
      end

      # GET /ads/accounts/{accountId}/identities - Pages, profiles and
      # identities an ad can run as. Requires ads:read.
      def identities(account_id)
        @client.request("GET", account_path(account_id, "identities"))
      end

      # GET /ads/accounts/{accountId}/health - status, payment, spend limit,
      # Page and pixel before an ad starts. A check that cannot be read is
      # "unknown"; failed checks carry a "fix_url". Requires ads:read.
      def health(account_id)
        @client.request("GET", account_path(account_id, "health"))
      end

      # GET /ads/accounts/{accountId}/finance - spend limit, amount spent,
      # balance and payment method. Requires ads:read.
      def finance(account_id)
        @client.request("GET", account_path(account_id, "finance"))
      end

      # PATCH /ads/accounts/{accountId}/settings - spend cap, DSA payer and
      # beneficiary, name.
      #
      # A higher spend_cap ALLOWS MORE REAL AD SPEND: pass the new cap as
      # confirm_budget_amount after the person agreed; spend_cap: nil removes
      # the cap and needs confirm_budget_amount: "remove". A spend cap change:
      # needs a key with the opt-in ads:spend scope ("Start ads"); without it,
      # and on Google (api_draft_only) always, the call answers 403
      # start_in_app with the page where a person does it in the app. The name
      # and the DSA names stay open. Not retried after a 5xx, a timeout or a
      # lost connection. Requires ads:write.
      def update_settings(account_id, spend_cap: OmniSocials::NOT_GIVEN, dsa_beneficiary: nil, dsa_payor: nil,
                          name: nil, confirm_budget_amount: nil)
        body = Internal.drop_nil(
          {
            "dsa_beneficiary" => dsa_beneficiary, "dsa_payor" => dsa_payor, "name" => name,
            "confirm_budget_amount" => confirm_budget_amount
          }
        )
        body["spend_cap"] = spend_cap unless spend_cap.is_a?(NotGiven)
        @client.request(
          "PATCH", account_path(account_id, "settings"), json: body, retry_on: :rate_limit
        )
      end

      # GET /ads/accounts/{accountId}/users - people with access. Requires
      # ads:read.
      def list_users(account_id)
        @client.request("GET", account_path(account_id, "users"))
      end

      # POST /ads/accounts/{accountId}/users - give a person access
      # (LinkedIn). Requires ads:write.
      def add_user(account_id, role:, email: nil, member_id: nil)
        @client.request(
          "POST", account_path(account_id, "users"),
          json: Internal.drop_nil({ "email" => email, "member_id" => member_id, "role" => role })
        )
      end

      # DELETE /ads/accounts/{accountId}/users/{userId} - remove a person's
      # access. Requires ads:write.
      def remove_user(account_id, user_id)
        @client.request("DELETE", account_path(account_id, "users/#{seg(user_id)}"))
      end

      # GET /ads/accounts/{accountId}/activity - the change log of the ad
      # account. Requires ads:read.
      def activity(account_id, since: nil, until_time: nil, cursor: nil)
        @client.request(
          "GET", account_path(account_id, "activity"),
          query: { "since" => since, "until" => until_time, "cursor" => cursor }
        )
      end

      # GET /ads/accounts/{accountId}/businesses - Meta business portfolios
      # and TikTok Business Centers. Requires ads:read.
      def businesses(account_id)
        @client.request("GET", account_path(account_id, "businesses"))
      end

      # GET /ads/accounts/{accountId}/dsa - the EU DSA payer and beneficiary
      # (Meta). Requires ads:read.
      def dsa(account_id)
        @client.request("GET", account_path(account_id, "dsa"))
      end

      # GET /ads/accounts/{accountId}/hierarchy - the manager account
      # hierarchy (Google). Requires ads:read.
      def hierarchy(account_id)
        @client.request("GET", account_path(account_id, "hierarchy"))
      end
    end

    # Meta reach and frequency buying. A prediction spends nothing; a
    # reservation does.
    class AdReachFrequency
      include AdPaths

      def initialize(client)
        @client = client
      end

      # POST /ads/reach-frequency - a prediction (objective "awareness",
      # "engagement" or "video_views"; exactly one country in targeting;
      # budget in major units or reach). It spends nothing; Meta needs the
      # reach and frequency capability on the ad account. Requires
      # ads:write.
      def create(ad_account_id:, objective:, targeting:, start_at:, end_at:, budget: nil, reach: nil,
                 frequency_cap: nil, frequency_interval_days: nil)
        @client.request(
          "POST", "/ads/reach-frequency",
          json: Internal.drop_nil(
            {
              "ad_account_id" => ad_account_id, "objective" => objective, "targeting" => targeting,
              "start_at" => start_at, "end_at" => end_at, "budget" => budget, "reach" => reach,
              "frequency_cap" => frequency_cap, "frequency_interval_days" => frequency_interval_days
            }
          )
        )
      end

      # GET /ads/reach-frequency/{predictionId}. Requires ads:read.
      def get(prediction_id, ad_account_id:)
        @client.request(
          "GET", "/ads/reach-frequency/#{seg(prediction_id)}",
          query: { "ad_account_id" => ad_account_id }
        )
      end

      # DELETE /ads/reach-frequency/{predictionId} - cancel a prediction or a
      # reservation. Requires ads:write.
      def cancel(prediction_id, ad_account_id:)
        @client.request(
          "DELETE", "/ads/reach-frequency/#{seg(prediction_id)}",
          query: { "ad_account_id" => ad_account_id }
        )
      end

      # POST /ads/reach-frequency/{predictionId}/reserve - COMMITS REAL AD
      # SPEND: pass the prediction's budget as confirm_budget_amount after the
      # person agreed. Needs a key with the opt-in ads:spend scope ("Start
      # ads"); without it, and on Google (api_draft_only) always, the call
      # answers 403 start_in_app with the page where a person does it in the
      # app. Not retried after a 5xx, a timeout or a lost connection: read the
      # prediction with get. Requires ads:write.
      def reserve(prediction_id, ad_account_id:, confirm_budget_amount:)
        @client.request(
          "POST", "/ads/reach-frequency/#{seg(prediction_id)}/reserve",
          json: { "ad_account_id" => ad_account_id, "confirm_budget_amount" => confirm_budget_amount },
          retry_on: :rate_limit
        )
      end
    end

    # A/B tests and lift studies (Meta).
    class AdStudies
      def initialize(client)
        @client = client
      end

      # GET /ads/studies. Requires ads:read.
      def list(ad_account_id:)
        @client.request("GET", "/ads/studies", query: { "ad_account_id" => ad_account_id })
      end

      # POST /ads/studies - an A/B test between existing campaigns or ad sets;
      # Meta's fields pass through as keyword arguments. Needs a key with the
      # opt-in ads:spend scope ("Start ads"); without it, and on Google
      # (api_draft_only) always, the call answers 403 start_in_app with the
      # page where a person does it in the app. Requires ads:write.
      def create(ad_account_id:, **fields)
        body = fields.each_with_object({}) { |(key, value), out| out[key.to_s] = value }
        @client.request("POST", "/ads/studies", json: body.merge("ad_account_id" => ad_account_id))
      end
    end

    # Planned budget increases of a campaign for high-demand periods (Meta).
    class AdBudgetSchedules
      include AdPaths

      def initialize(client)
        @client = client
      end

      # GET /ads/campaigns/{id}/budget-schedules. Requires ads:read.
      def list(campaign_id)
        @client.request("GET", "/ads/campaigns/#{seg(campaign_id)}/budget-schedules")
      end

      # POST /ads/campaigns/{id}/budget-schedules - plan a budget increase
      # (budget_increase: { "type" => "absolute" | "multiplier", "value" =>
      # ... }).
      #
      # NEW REAL AD SPEND in that period: pass the increase per day (absolute)
      # or the campaign budget times the multiplier as confirm_budget_amount
      # after the person agreed. Needs a key with the opt-in ads:spend scope
      # ("Start ads"); without it, and on Google (api_draft_only) always, the
      # call answers 403 start_in_app with the page where a person does it in
      # the app. Not retried after a 5xx, a timeout or a lost connection: read
      # the schedules with list. Requires ads:write.
      def create(campaign_id, start_at:, end_at:, budget_increase:, confirm_budget_amount:)
        @client.request(
          "POST", "/ads/campaigns/#{seg(campaign_id)}/budget-schedules",
          json: {
            "start_at" => start_at, "end_at" => end_at, "budget_increase" => budget_increase,
            "confirm_budget_amount" => confirm_budget_amount
          },
          retry_on: :rate_limit
        )
      end

      # DELETE /ads/campaigns/{id}/budget-schedules/{scheduleId}. Requires
      # ads:write.
      def delete(campaign_id, schedule_id)
        @client.request(
          "DELETE", "/ads/campaigns/#{seg(campaign_id)}/budget-schedules/#{seg(schedule_id)}"
        )
      end
    end

    # Google reports (read-only; every API caller stops at the draft on
    # Google).
    class AdGoogle
      include AdPaths

      def initialize(client)
        @client = client
      end

      # GET /ads/google/search-terms. Requires ads:read.
      def search_terms(ad_account_id:, campaign_id: nil, external_campaign_id: nil, from: nil,
                       to: nil, limit: nil)
        @client.request(
          "GET", "/ads/google/search-terms",
          query: {
            "ad_account_id" => ad_account_id, "campaign_id" => campaign_id,
            "external_campaign_id" => external_campaign_id, "from" => from, "to" => to,
            "limit" => limit
          }
        )
      end

      # GET /ads/google/recommendations. Requires ads:read.
      def recommendations(ad_account_id:, types: nil)
        @client.request(
          "GET", "/ads/google/recommendations",
          query: { "ad_account_id" => ad_account_id, "types" => list_param(types) }
        )
      end

      # GET /ads/google/keywords - search keywords and negative keywords.
      # Requires ads:read.
      def keywords(ad_account_id:, external_campaign_id: nil, external_ad_set_id: nil)
        @client.request(
          "GET", "/ads/google/keywords",
          query: {
            "ad_account_id" => ad_account_id, "external_campaign_id" => external_campaign_id,
            "external_ad_set_id" => external_ad_set_id
          }
        )
      end

      # GET /ads/google/assets - sitelinks, callouts and structured snippets.
      # Requires ads:read.
      def assets(ad_account_id:, type: nil)
        @client.request(
          "GET", "/ads/google/assets", query: { "ad_account_id" => ad_account_id, "type" => type }
        )
      end

      # GET /ads/google/shared-budgets. Requires ads:read.
      def shared_budgets(ad_account_id:)
        @client.request("GET", "/ads/google/shared-budgets", query: { "ad_account_id" => ad_account_id })
      end

      # GET /ads/google/bid-strategies - portfolio bid strategies. Requires
      # ads:read.
      def bid_strategies(ad_account_id:)
        @client.request("GET", "/ads/google/bid-strategies", query: { "ad_account_id" => ad_account_id })
      end

      # GET /ads/google/ad-schedule - the days and hours of a Google
      # campaign. Requires ads:read.
      def ad_schedule(ad_account_id:, external_campaign_id:)
        @client.request(
          "GET", "/ads/google/ad-schedule",
          query: { "ad_account_id" => ad_account_id, "external_campaign_id" => external_campaign_id }
        )
      end

      # GET /ads/google/labels. Requires ads:read.
      def labels(ad_account_id:)
        @client.request("GET", "/ads/google/labels", query: { "ad_account_id" => ad_account_id })
      end

      # GET /ads/google/local-services-leads. Requires ads:read.
      def local_services_leads(ad_account_id:, since: nil)
        @client.request(
          "GET", "/ads/google/local-services-leads",
          query: { "ad_account_id" => ad_account_id, "since" => since }
        )
      end
    end
  end
end
