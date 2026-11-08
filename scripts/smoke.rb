# frozen_string_literal: true

# Offline smoke test for the omnisocials gem.
#
# Run from sdk/ruby/:  ruby scripts/smoke.rb
#
# Verifies (with only loopback network access):
# - the library loads and the client constructs
# - every resource exposes every expected method with the exact positional /
#   keyword parameter surface (mirrors the Python SDK)
# - nil-dropping bodies, the NOT_GIVEN sentinel on media.update folder_id /
#   folders.update parent_id, and nested nils (thread_parts: nil) surviving
# - a missing API key raises AuthenticationError at construction time; the
#   OMNISOCIALS_API_KEY env fallback works; the constructor arg wins
# - the error hierarchy matches the spec (incl. RateLimitError#retry_after)
# - OmniSocials::Webhooks.verify round-trips against a signature built exactly
#   like backend/services/webhooks/webhookDispatcher.js, and rejects tampered
#   bodies, stale timestamps, wrong secrets, and malformed headers
# - the transport retries 429/5xx (honoring Retry-After), maps error statuses,
#   returns nil on 204, sends the right headers, and raises
#   APIConnectionError on connection failure (via a scripted loopback server)
# - tags calls (and the tag fields on posts and analytics) send the right
#   method, path, query and body
# - limits and feature request calls send the right method, path, query and
#   body; a create returns the outcome and a 409 not_requestable keeps the
#   limit in the error body
# - ads calls send the right method, path and body; a call that can start ad
#   spend is sent once after a 502 or a lost connection, a read is retried
# - every id goes into the request path as one percent-encoded segment, so an
#   id with "/", "?", "#" or ".." cannot reach another endpoint, and an id of
#   "", "." or ".." raises ArgumentError before anything is sent

require "json"
require "openssl"
require "socket"
require "stringio"
require "tempfile"

require_relative "../lib/omnisocials"

$checks = 0

def ok(condition, label)
  raise "FAILED: #{label}" unless condition

  $checks += 1
  puts "  ok - #{label}"
end

def assert_raises(klass, label)
  yield
  raise "FAILED: #{label} (nothing raised)"
rescue klass => e
  $checks += 1
  puts "  ok - #{label}"
  e
rescue StandardError => e
  raise "FAILED: #{label} (raised #{e.class}: #{e.message})"
end

# ---------------------------------------------------------------------------
# 1. Method surface: exact positional + keyword parameters per resource method
# ---------------------------------------------------------------------------

PLATFORM_KEYS = %i[pinterest youtube instagram facebook linkedin linkedin_page
                   tiktok x bluesky mastodon threads google_business
                   telegram discord linkedin_poll].freeze
CREATE_KEYS = (%i[channels scheduled_at media_ids media_urls type source
                  link_url link_title link_description link_thumbnail_url
                  location_id collaborators user_tags hashtag_set
                  hashtag_set_id hashtag_placement hashtag_platforms] +
               PLATFORM_KEYS).freeze
CREATE_AND_PUBLISH_KEYS = (CREATE_KEYS - [:scheduled_at]).freeze
UPDATE_KEYS = (%i[content scheduled_at channels media_ids media_urls type
                  location_id collaborators user_tags] + PLATFORM_KEYS).freeze

def kw(names)
  names.map { |name| [:key, name] }
end

EXPECTED_SURFACE = {
  posts: {
    list: kw(%i[status limit offset start_date end_date tag]),
    get: [[:req, :post_id]],
    recent_platform: kw(%i[limit platforms]),
    create: [[:keyreq, :content]] +
            kw(CREATE_KEYS + %i[approval_workflow_id draft media_fit comment_dm_automation tags]),
    create_and_publish: [[:keyreq, :content]] +
                        kw(CREATE_AND_PUBLISH_KEYS + %i[media_fit comment_dm_automation tags]),
    update: [[:req, :post_id]] + kw(UPDATE_KEYS + %i[draft media_fit comment_dm_automation tags]),
    delete: [[:req, :post_id]],
    publish: [[:req, :post_id]],
    approve: [[:req, :post_id]] + kw(%i[step_order]),
    reject: [[:req, :post_id]] + kw(%i[comment step_order]),
    get_approval: [[:req, :post_id]]
  },
  media: {
    list: kw(%i[limit offset search folder_id]),
    get: [[:req, :media_id]],
    upload: [[:keyreq, :file]] + kw(%i[filename name folder folder_id pdf_mode]),
    upload_from_url: [[:keyreq, :url]] + kw(%i[filename name folder folder_id pdf_mode]),
    upload_from_base64: [%i[keyreq data], %i[keyreq mime_type]] +
                        kw(%i[filename name folder folder_id pdf_mode]),
    create_upload_url: [],
    check: kw(%i[url media_id size_bytes mime]),
    update: [[:req, :media_id]] + kw(%i[name folder_id]),
    delete: [[:req, :media_id]]
  },
  folders: {
    list: [],
    create: [[:keyreq, :name], [:key, :parent_id]],
    update: [[:req, :folder_id]] + kw(%i[name parent_id]),
    delete: [[:req, :folder_id]]
  },
  hashtag_sets: {
    list: [],
    get: [[:req, :hashtag_set_id]],
    create: [%i[keyreq name], %i[keyreq hashtags]],
    update: [[:req, :hashtag_set_id]] + kw(%i[name hashtags]),
    delete: [[:req, :hashtag_set_id]]
  },
  tags: {
    list: [],
    create: [%i[keyreq name], %i[key color]],
    update: [[:req, :tag_id]] + kw(%i[name color]),
    delete: [[:req, :tag_id]],
    apply: [[:keyreq, :post_ids]] + kw(%i[add remove set])
  },
  accounts: {
    list: [],
    get: [[:req, :account_id]]
  },
  analytics: {
    post: [[:req, :post_id]],
    posts: [[:req, :ids]],
    overview: kw(%i[period start_date end_date tag]),
    accounts: kw(%i[platform date]),
    best_times: [[:keyreq, :platform], [:key, :timezone]],
    tags: kw(%i[start_date end_date platform min_posts])
  },
  locations: {
    search: [[:opt, :q]] + kw(%i[platform latitude longitude]),
    validate: [[:req, :id]]
  },
  pinterest: {
    list_products: kw(%i[source product_group_id bookmark page_size]),
    validate_product: [[:req, :id]]
  },
  automations: {
    list: kw(%i[status post_id platform]),
    get: [[:req, :automation_id]],
    create: [[:keyreq, :actions]] +
            kw(%i[trigger limits name post_id instagram_media_id status platform facebook_post_id]),
    update: [[:req, :automation_id]] +
            kw(%i[name post_id instagram_media_id trigger actions limits status platform facebook_post_id]),
    delete: [[:req, :automation_id]],
    list_events: [[:req, :automation_id]] + kw(%i[outcome limit offset])
  },
  ads: {
    list_accounts: [],
    capabilities: [],
    list: kw(%i[status platform campaign_type limit offset]),
    get: [[:req, :campaign_id]],
    boost: [%i[keyreq post_id], %i[keyreq ad_account_id], %i[keyreq budget]] +
           kw(%i[objective targeting schedule creative name]),
    boost_multi: [%i[keyreq post_id], %i[keyreq ad_account_ids], %i[keyreq budget]] +
                 kw(%i[objective targeting schedule creative name]),
    update: [[:req, :campaign_id]] +
            kw(%i[name budget confirm_budget_amount targeting schedule objective settings]),
    bulk_status: [%i[keyreq campaign_ids], %i[keyreq status], %i[key confirm_budget_amount]],
    duplicate: [[:req, :campaign_id], %i[key name]],
    activate: [%i[req campaign_id], %i[req confirm_budget_amount]],
    activate_multi: [%i[req campaign_ids], %i[req confirm_budget_amount]],
    pause: [[:req, :campaign_id]],
    resume: [[:req, :campaign_id]],
    delete: [[:req, :campaign_id]],
    overview: [],
    suggestions: [],
    research_keywords: kw(%i[keywords url country language limit ad_account_id]),
    keyword_metrics: [[:keyreq, :keywords]] + kw(%i[country language ad_account_id])
  },
  webhooks: {
    list: [],
    get: [[:req, :webhook_id]],
    create: [%i[keyreq url], %i[keyreq events]],
    update: [[:req, :webhook_id]] + kw(%i[url events is_active]),
    delete: [[:req, :webhook_id]],
    rotate_secret: [[:req, :webhook_id]]
  },
  limits: {
    list: kw(%i[platform area])
  },
  feature_requests: {
    create: [[:keyreq, :summary]] + kw(%i[title platform area limit_id]),
    list: [],
    get: [[:req, :request_id]]
  }
}.freeze

DRAFT_KEYS = [%i[keyreq objective], %i[keyreq platforms], %i[keyreq budget],
              %i[keyreq targeting], %i[keyreq ads], %i[key name], %i[key schedule]].freeze
EXPECTED_DRAFTS_SURFACE = {
  defaults: [],
  create: DRAFT_KEYS,
  get: [[:req, :group_id]],
  update: [[:req, :group_id]] + DRAFT_KEYS,
  delete: [[:req, :group_id]],
  attach_account: [%i[req group_id], %i[keyreq platform], %i[keyreq ad_account_id]],
  launch: [[:req, :group_id]] + kw(%i[confirm_budget_amount confirm_budget_amounts])
}.freeze

# The Ads API parity sub-resources (2026-11-05): one method per route of
# backend/routes/api/v1/adsParity.js, with its exact parameters.
def req(*names)
  names.map { |name| [:req, name] }
end

def keyreq(*names)
  names.map { |name| [:keyreq, name] }
end

ADS_PARITY_SURFACE = {
  objects: {
    tree: req(:account_id) + kw(%i[from to status limit cursor]),
    get: req(:account_id, :level, :external_id),
    update: req(:account_id, :level, :external_id) + kw(%i[name budget end_at confirm_budget_amount]),
    set_status: req(:account_id, :level, :external_id) + keyreq(:status) + kw(%i[confirm_budget_amount]),
    duplicate: req(:account_id, :level, :external_id) + kw(%i[deep rename]),
    import_status: req(:account_id),
    start_import: req(:account_id),
    list_external: kw(%i[ad_account_id platform status limit offset]),
    get_external: req(:campaign_id) + kw(%i[from to])
  },
  campaign_ads: {
    list: req(:campaign_id),
    add: req(:campaign_id, :ads),
    get: req(:campaign_id, :ad_id),
    set_status: req(:campaign_id, :ad_id) + keyreq(:status) + kw(%i[confirm_budget_amount]),
    review: req(:campaign_id, :ad_id)
  },
  comments: {
    list: req(:campaign_id, :ad_id) + kw(%i[cursor]),
    reply: req(:campaign_id, :ad_id, :comment_id, :text),
    hide: req(:campaign_id, :ad_id, :comment_id) + kw(%i[hidden]),
    delete: req(:campaign_id, :ad_id, :comment_id)
  },
  targeting: {
    search: keyreq(:ad_account_id, :type, :q) + kw(%i[limit country]),
    browse: keyreq(:ad_account_id, :type),
    reach_estimate: keyreq(:ad_account_id, :targeting) + kw(%i[objective]),
    bid_suggestions: keyreq(:ad_account_id, :targeting) + kw(%i[objective budget])
  },
  audiences: {
    list: keyreq(:ad_account_id) + kw(%i[cursor]),
    create: keyreq(:ad_account_id, :name) +
            kw(%i[description kind lookalike customer_file_source schema rows]),
    get: req(:audience_id) + keyreq(:ad_account_id),
    update: req(:audience_id) + keyreq(:ad_account_id) + kw(%i[name description]),
    delete: req(:audience_id) + keyreq(:ad_account_id),
    add_members: req(:audience_id) + keyreq(:ad_account_id, :schema, :rows),
    remove_members: req(:audience_id) + keyreq(:ad_account_id, :schema, :rows),
    add_companies: req(:audience_id) + keyreq(:ad_account_id, :companies)
  },
  lead_forms: {
    list: keyreq(:ad_account_id),
    create: keyreq(:ad_account_id, :name, :privacy_policy_url, :questions, :thank_you) +
            kw(%i[locale headline description accept_terms]),
    get: req(:form_id),
    update: req(:form_id) + kw(%i[status sync_enabled]),
    delete: req(:form_id),
    send_test_lead: req(:form_id) + kw(%i[fields])
  },
  leads: {
    list: kw(%i[form_id status since until_time limit cursor]),
    counts: kw(%i[form_id]),
    update: req(:lead_id) + kw(%i[status note])
  },
  conversions: {
    destinations: keyreq(:ad_account_id),
    goals: keyreq(:ad_account_id),
    create_custom: keyreq(:ad_account_id, :name, :destination_id) + kw(%i[event url_contains]),
    send_events: keyreq(:ad_account_id, :destination_id, :events)
  },
  insights: {
    query: keyreq(:ad_account_id) + kw(%i[level ids metrics breakdowns from to time_increment]),
    campaign: req(:campaign_id) + kw(%i[from to breakdown time_increment metrics]),
    ad: req(:campaign_id, :ad_id) + kw(%i[from to breakdown]),
    timeline: kw(%i[from to platform source]),
    performance: kw(%i[level metric order limit min_impressions from to platform]),
    alerts: []
  },
  reports: {
    list: [],
    start: keyreq(:ad_account_id) + kw(%i[level ids metrics breakdowns from to time_increment]),
    get: req(:report_id)
  },
  rules: {
    list: [],
    create: keyreq(:name, :conditions, :action) +
            kw(%i[ad_account_id enabled scope every_minutes cooldown_minutes max_actions_per_run
                  confirm_max_daily_budget]),
    templates: [],
    preview: keyreq(:conditions, :action) + kw(%i[name ad_account_id scope]),
    activity: kw(%i[rule_id limit]),
    undo: req(:activity_id) + kw(%i[confirm_budget_amount]),
    get: req(:rule_id),
    update: req(:rule_id) +
            kw(%i[name conditions action ad_account_id enabled scope every_minutes cooldown_minutes
                  max_actions_per_run confirm_max_daily_budget]),
    delete: req(:rule_id),
    preview_saved: req(:rule_id),
    runs: req(:rule_id) + kw(%i[limit])
  },
  results: {
    list: kw(%i[from to campaign_id metric]),
    upload: req(:rows),
    totals: kw(%i[from to campaign_id]),
    metrics: [],
    put_metric: req(:key) + kw(%i[label unit formula])
  },
  media: {
    list: keyreq(:ad_account_id) + kw(%i[type cursor]),
    upload: keyreq(:ad_account_id, :type, :url) + kw(%i[name]),
    get: req(:media_id) + keyreq(:ad_account_id) + kw(%i[type]),
    delete: req(:media_id) + keyreq(:ad_account_id, :type)
  },
  previews: {
    create: keyreq(:ad_account_id, :ad) + kw(%i[placements objective]),
    for_ad: req(:campaign_id, :ad_id) + kw(%i[placements])
  },
  partnership: {
    list_content: keyreq(:ad_account_id),
    list_permissions: keyreq(:ad_account_id),
    set_permission: keyreq(:ad_account_id) + [%i[keyrest fields]]
  },
  accounts: {
    identities: req(:account_id),
    health: req(:account_id),
    finance: req(:account_id),
    update_settings: req(:account_id) +
                     kw(%i[spend_cap dsa_beneficiary dsa_payor name confirm_budget_amount]),
    list_users: req(:account_id),
    add_user: req(:account_id) + keyreq(:role) + kw(%i[email member_id]),
    remove_user: req(:account_id, :user_id),
    activity: req(:account_id) + kw(%i[since until_time cursor]),
    businesses: req(:account_id),
    dsa: req(:account_id),
    hierarchy: req(:account_id)
  },
  reach_frequency: {
    create: keyreq(:ad_account_id, :objective, :targeting, :start_at, :end_at) +
            kw(%i[budget reach frequency_cap frequency_interval_days]),
    get: req(:prediction_id) + keyreq(:ad_account_id),
    cancel: req(:prediction_id) + keyreq(:ad_account_id),
    reserve: req(:prediction_id) + keyreq(:ad_account_id, :confirm_budget_amount)
  },
  studies: {
    list: keyreq(:ad_account_id),
    create: keyreq(:ad_account_id) + [%i[keyrest fields]]
  },
  budget_schedules: {
    list: req(:campaign_id),
    create: req(:campaign_id) + keyreq(:start_at, :end_at, :budget_increase, :confirm_budget_amount),
    delete: req(:campaign_id, :schedule_id)
  },
  google: {
    search_terms: keyreq(:ad_account_id) + kw(%i[campaign_id external_campaign_id from to limit]),
    recommendations: keyreq(:ad_account_id) + kw(%i[types]),
    keywords: keyreq(:ad_account_id) + kw(%i[external_campaign_id external_ad_set_id]),
    assets: keyreq(:ad_account_id) + kw(%i[type]),
    shared_budgets: keyreq(:ad_account_id),
    bid_strategies: keyreq(:ad_account_id),
    ad_schedule: keyreq(:ad_account_id, :external_campaign_id),
    labels: keyreq(:ad_account_id),
    local_services_leads: keyreq(:ad_account_id) + kw(%i[since])
  }
}.freeze

def check_ads_parity_surface(ads)
  count = 2 # bulk_status and duplicate on ads itself
  ADS_PARITY_SURFACE.each do |sub, methods|
    namespace = ads.public_send(sub)
    ok(!namespace.nil?, "client.ads.#{sub} exists")
    methods.each do |method_name, expected_params|
      actual = namespace.method(method_name).parameters.map { |kind, name| [kind, name] }
      ok(
        actual == expected_params,
        "client.ads.#{sub}.#{method_name} params match (#{actual.inspect} vs #{expected_params.inspect})"
      )
      count += 1
    end
    public_methods = namespace.class.public_instance_methods(false).sort
    ok(public_methods == methods.keys.sort, "client.ads.#{sub} has exactly the listed methods")
  end
  ok(count == 108, "108 parity methods (one per route of adsParity.js)")
end

def check_client_surface
  puts "Client surface:"
  client = OmniSocials::Client.new(api_key: "omsk_test_x")

  EXPECTED_SURFACE.each do |resource, methods|
    namespace = client.public_send(resource)
    ok(!namespace.nil?, "client.#{resource} exists")
    methods.each do |method_name, expected_params|
      ok(namespace.respond_to?(method_name), "client.#{resource}.#{method_name} exists")
      actual = namespace.method(method_name).parameters.map { |kind, name| [kind, name] }
      ok(
        actual == expected_params,
        "client.#{resource}.#{method_name} params match " \
        "(#{actual.inspect} vs #{expected_params.inspect})"
      )
    end
  end

  ok(
    !client.ads.respond_to?(:create),
    "client.ads.create is gone (POST /ads/campaigns was removed: use ads.drafts.create)"
  )
  drafts = client.ads.drafts
  ok(drafts.is_a?(OmniSocials::Resources::AdDrafts), "client.ads.drafts exists")
  EXPECTED_DRAFTS_SURFACE.each do |method_name, expected_params|
    actual = drafts.method(method_name).parameters.map { |kind, name| [kind, name] }
    ok(
      actual == expected_params,
      "client.ads.drafts.#{method_name} params match " \
      "(#{actual.inspect} vs #{expected_params.inspect})"
    )
  end

  check_ads_parity_surface(client.ads)

  ok(client.respond_to?(:health), "client.health exists")
  ok(client.method(:health).parameters.empty?, "client.health takes no args")
  ok(client.timeout == 30.0, "default timeout is 30s")
  ok(client.max_retries == 2, "default max_retries is 2")
  # Structural version checks: interpolate VERSION so this script never needs
  # stamping on release (set-version.mjs updates lib/omnisocials/version.rb).
  ok(
    OmniSocials::Client::USER_AGENT == "omnisocials-ruby/#{OmniSocials::VERSION}",
    "User-Agent embeds VERSION"
  )
  ok(OmniSocials::VERSION.match?(/\A\d+\.\d+\.\d+/), "VERSION is semver")
  ok(
    OmniSocials::Client.new(api_key: "k", base_url: "https://x.test/v1/").base_url ==
      "https://x.test/v1",
    "trailing slash is stripped from base_url"
  )

  verify_params = OmniSocials::Webhooks.method(:verify).parameters
  ok(
    verify_params == [%i[keyreq payload], %i[keyreq signature], %i[keyreq secret],
                      %i[key tolerance]],
    "OmniSocials::Webhooks.verify has payload:/signature:/secret:/tolerance: kwargs"
  )
end

# ---------------------------------------------------------------------------
# 2. Construction guards + error hierarchy
# ---------------------------------------------------------------------------

def check_construction_guards
  puts "Construction guards:"
  saved = ENV.delete("OMNISOCIALS_API_KEY")
  begin
    assert_raises(OmniSocials::AuthenticationError, "missing API key raises AuthenticationError") do
      OmniSocials::Client.new
    end
    assert_raises(OmniSocials::AuthenticationError, "empty-string API key raises AuthenticationError") do
      OmniSocials::Client.new(api_key: "")
    end

    ENV["OMNISOCIALS_API_KEY"] = "omsk_test_env"
    ok(
      OmniSocials::Client.new.api_key == "omsk_test_env",
      "env var API key is picked up"
    )
    ok(
      OmniSocials::Client.new(api_key: "omsk_test_arg").api_key == "omsk_test_arg",
      "constructor arg wins over env var"
    )
  ensure
    saved.nil? ? ENV.delete("OMNISOCIALS_API_KEY") : ENV["OMNISOCIALS_API_KEY"] = saved
  end

  [
    OmniSocials::AuthenticationError,
    OmniSocials::PermissionDeniedError,
    OmniSocials::NotFoundError,
    OmniSocials::ValidationError,
    OmniSocials::RateLimitError,
    OmniSocials::ServerError
  ].each do |klass|
    ok(klass < OmniSocials::APIError, "#{klass.name.split('::').last} subclasses APIError")
  end
  ok(OmniSocials::APIError < OmniSocials::Error, "APIError subclasses OmniSocials::Error")
  ok(
    OmniSocials::APIConnectionError < OmniSocials::Error,
    "APIConnectionError subclasses OmniSocials::Error"
  )
  ok(
    OmniSocials::WebhookVerificationError < OmniSocials::Error,
    "WebhookVerificationError subclasses OmniSocials::Error"
  )
  ok(OmniSocials::Error < StandardError, "OmniSocials::Error subclasses StandardError")

  err = OmniSocials::RateLimitError.new("slow down", retry_after: 12.5)
  ok(err.retry_after == 12.5, "RateLimitError#retry_after is exposed")
  ok(err.status == 429, "RateLimitError defaults status to 429")
  api_err = OmniSocials::APIError.new("boom", status: 418, code: "teapot", body: { "a" => 1 })
  ok(
    api_err.status == 418 && api_err.code == "teapot" && api_err.body == { "a" => 1 } &&
      api_err.message == "boom",
    "APIError exposes status/code/body/message"
  )
end

# ---------------------------------------------------------------------------
# 3. Body building: nil-dropping, sentinel, nested nils (via a fake transport)
# ---------------------------------------------------------------------------

class FakeTransport
  Call = Struct.new(:method, :path, :query, :json, :multipart, :retry_on)

  attr_reader :calls

  def initialize
    @calls = []
  end

  def request(method, path, query: nil, json: nil, multipart: nil, retry_on: nil)
    @calls << Call.new(method, path, query, json, multipart, retry_on)
    { "data" => {} }
  end

  def last
    @calls.last
  end
end

def check_body_building
  puts "Body building (nil-dropping, sentinel, nested nils):"
  fake = FakeTransport.new

  posts = OmniSocials::Resources::Posts.new(fake)
  posts.create(content: "hi", channels: %w[instagram], x: { "thread_parts" => nil })
  body = fake.last.json
  ok(
    body == { "content" => "hi", "channels" => %w[instagram], "x" => { "thread_parts" => nil } },
    "posts.create drops top-level nils but keeps nested nil thread_parts"
  )
  ok(fake.last.path == "/posts/create", "posts.create posts to /posts/create")

  posts.update("p1", threads: { "thread_parts" => nil })
  ok(
    fake.last.json == { "threads" => { "thread_parts" => nil } },
    "posts.update keeps nested nil threads.thread_parts (clears a Threads chain)"
  )

  posts.create_and_publish(content: "now", channels: %w[x])
  ok(
    fake.last.path == "/posts/create-and-publish" &&
      fake.last.json == { "content" => "now", "channels" => %w[x] },
    "posts.create_and_publish posts to /posts/create-and-publish"
  )

  posts.update("42", scheduled_at: "2026-08-01T09:00:00Z")
  ok(
    fake.last.method == "PATCH" && fake.last.path == "/posts/42" &&
      fake.last.json == { "scheduled_at" => "2026-08-01T09:00:00Z" },
    "posts.update PATCHes only the given fields"
  )

  posts.recent_platform(limit: 5, platforms: %w[instagram tiktok])
  ok(
    fake.last.query == { "limit" => 5, "platforms" => "instagram,tiktok" },
    "posts.recent_platform joins the platforms array"
  )

  posts.get_approval("42")
  ok(
    fake.last.method == "GET" && fake.last.path == "/posts/42/approval",
    "posts.get_approval GETs /posts/42/approval"
  )

  posts.approve("42")
  ok(
    fake.last.method == "POST" && fake.last.path == "/posts/42/approve" && fake.last.json.nil?,
    "posts.approve without step_order sends no body"
  )
  posts.approve("42", step_order: 2)
  ok(fake.last.json == { "step_order" => 2 }, "posts.approve sends step_order")
  posts.reject("42")
  ok(
    fake.last.path == "/posts/42/reject" && fake.last.json.nil?,
    "posts.reject without arguments sends no body"
  )
  posts.reject("42", comment: "Wrong CTA link")
  ok(fake.last.json == { "comment" => "Wrong CTA link" }, "posts.reject sends comment alone")
  posts.reject("42", comment: "Wrong CTA link", step_order: 2)
  ok(
    fake.last.json == { "comment" => "Wrong CTA link", "step_order" => 2 },
    "posts.reject sends comment and step_order"
  )
  posts.reject("42", step_order: 3)
  ok(fake.last.json == { "step_order" => 3 }, "posts.reject sends step_order alone")

  media = OmniSocials::Resources::Media.new(fake)
  media.update("1001", name: "renamed")
  ok(
    fake.last.json == { "name" => "renamed" },
    "media.update omits folder_id when NOT_GIVEN (sentinel default)"
  )
  media.update("1001", folder_id: nil)
  ok(
    fake.last.json == { "folder_id" => nil },
    "media.update folder_id: nil sends explicit null (move to root)"
  )
  media.update("1001", name: "x", folder_id: "7")
  ok(
    fake.last.json == { "name" => "x", "folder_id" => "7" },
    "media.update sends folder_id when given"
  )

  folders = OmniSocials::Resources::Folders.new(fake)
  folders.update("9", name: "renamed")
  ok(
    fake.last.json == { "name" => "renamed" },
    "folders.update omits parent_id when NOT_GIVEN (sentinel default)"
  )
  folders.update("9", parent_id: nil)
  ok(
    fake.last.json == { "parent_id" => nil },
    "folders.update parent_id: nil sends explicit null (move to top level)"
  )

  analytics = OmniSocials::Resources::Analytics.new(fake)
  analytics.posts(%w[1 2 3])
  ok(fake.last.query == { "ids" => "1,2,3" }, "analytics.posts joins ids into a CSV")
  analytics.posts("4,5")
  ok(fake.last.query == { "ids" => "4,5" }, "analytics.posts passes a CSV string through")

  pinterest = OmniSocials::Resources::Pinterest.new(fake)
  pinterest.list_products(source: "catalog", product_group_id: "443727193917", page_size: 50)
  ok(
    fake.last.method == "GET" && fake.last.path == "/pinterest/products" &&
      fake.last.query == { "source" => "catalog", "product_group_id" => "443727193917",
                           "bookmark" => nil, "page_size" => 50 },
    "pinterest.list_products GETs /pinterest/products with its filters"
  )
  pinterest.validate_product("813744226420795884")
  ok(
    fake.last.method == "GET" && fake.last.path == "/pinterest/products/validate" &&
      fake.last.query == { "id" => "813744226420795884" },
    "pinterest.validate_product GETs /pinterest/products/validate with the id"
  )

  posts.create(content: "pin", channels: %w[pinterest],
               pinterest: { "board_id" => "b1", "product_tags" => %w[813744226420795884] })
  ok(
    fake.last.json["pinterest"] == { "board_id" => "b1", "product_tags" => %w[813744226420795884] },
    "posts.create passes pinterest product_tags through"
  )

  webhooks = OmniSocials::Resources::Webhooks.new(fake)
  webhooks.update("w1", is_active: false)
  ok(
    fake.last.json == { "is_active" => false },
    "webhooks.update keeps false values while dropping nils"
  )

  hashtag_sets = OmniSocials::Resources::HashtagSets.new(fake)
  hashtag_sets.create(name: "Launch", hashtags: %w[saas startup])
  ok(
    fake.last.path == "/hashtag-sets" &&
      fake.last.json == { "name" => "Launch", "hashtags" => %w[saas startup] },
    "hashtag_sets.create posts name + hashtags array"
  )
  hashtag_sets.update("7", hashtags: "#a #b")
  ok(
    fake.last.method == "PATCH" && fake.last.path == "/hashtag-sets/7" &&
      fake.last.json == { "hashtags" => "#a #b" },
    "hashtag_sets.update drops nils and passes a String hashtags through"
  )

  # media.upload input coercion: raw bytes, IO, and file path
  bytes = "\x89PNG\r\nfakebytes".b
  media.upload(file: bytes, filename: "pixel.png")
  call = fake.last
  ok(
    call.multipart[:filename] == "pixel.png" && call.multipart[:data] == bytes,
    "media.upload accepts raw bytes (binary String)"
  )

  media.upload(file: StringIO.new(bytes), filename: "io.png", name: "from-io")
  call = fake.last
  ok(
    call.multipart[:filename] == "io.png" && call.multipart[:data] == bytes &&
      call.multipart[:fields] == { "name" => "from-io" },
    "media.upload accepts an IO and carries form fields"
  )

  Tempfile.create(["smoke", ".jpg"]) do |tmp|
    tmp.binmode
    tmp.write(bytes)
    tmp.flush
    media.upload(file: tmp.path)
    call = fake.last
    ok(
      call.multipart[:filename] == File.basename(tmp.path) && call.multipart[:data] == bytes,
      "media.upload accepts a file path and infers the filename"
    )
  end

  assert_raises(ArgumentError, "media.upload rejects unsupported file types") do
    media.upload(file: 12_345)
  end

  check_tags_bodies(fake)
  check_feature_requests_bodies(fake)
  check_ads_bodies(fake)

  # Query serialization
  serialized = OmniSocials::Internal.serialize_query(
    { "limit" => 50, "flag" => true, "off" => false, "skip" => nil, "s" => "q" }
  )
  ok(
    serialized == { "limit" => "50", "flag" => "true", "off" => "false", "s" => "q" },
    "serialize_query stringifies numbers/booleans and drops nils"
  )

  # Backoff honors an explicit Retry-After and caps it
  ok(
    OmniSocials::Internal.backoff_delay(0, 5.0) == 5.0,
    "backoff_delay uses the server Retry-After when present"
  )
  ok(
    OmniSocials::Internal.backoff_delay(3, 120.0) == 60.0,
    "backoff_delay caps Retry-After at 60s"
  )
  base = OmniSocials::Internal.backoff_delay(0, nil)
  ok(base >= 0.375 && base <= 0.625, "backoff_delay attempt 0 is ~0.5s with jitter")
  later = OmniSocials::Internal.backoff_delay(10, nil)
  ok(later <= 8.0 * 1.25, "backoff_delay is capped at 8s (plus jitter)")
end

def check_tags_bodies(fake)
  puts "Tags bodies:"
  tags = OmniSocials::Resources::Tags.new(fake)
  tags.list
  ok(fake.last.method == "GET" && fake.last.path == "/tags", "tags.list GETs /tags")
  tags.create(name: "Question")
  ok(
    fake.last.method == "POST" && fake.last.path == "/tags" &&
      fake.last.json == { "name" => "Question" },
    "tags.create POSTs /tags with only the given keys"
  )
  tags.create(name: "Behind the scenes", color: "teal")
  ok(fake.last.json == { "name" => "Behind the scenes", "color" => "teal" }, "tags.create sends color")
  tags.update(12, color: "red")
  ok(
    fake.last.method == "PATCH" && fake.last.path == "/tags/12" &&
      fake.last.json == { "color" => "red" },
    "tags.update PATCHes /tags/{id} with only the given keys"
  )
  tags.delete(12)
  ok(fake.last.method == "DELETE" && fake.last.path == "/tags/12", "tags.delete DELETEs /tags/{id}")
  tags.apply(post_ids: ["1024", 1025], add: ["Question", 7])
  ok(
    fake.last.method == "POST" && fake.last.path == "/tags/apply" &&
      fake.last.json == { "post_ids" => %w[1024 1025], "add" => ["Question", 7] },
    "tags.apply POSTs /tags/apply, post ids as strings, nils dropped"
  )
  tags.apply(post_ids: ["1024"], set: [])
  ok(fake.last.json == { "post_ids" => ["1024"], "set" => [] }, "tags.apply sends set: [] (clear)")

  analytics = OmniSocials::Resources::Analytics.new(fake)
  analytics.tags(start_date: "2026-08-01", min_posts: 3)
  ok(
    fake.last.path == "/analytics/tags" &&
      OmniSocials::Internal.serialize_query(fake.last.query) ==
        { "start_date" => "2026-08-01", "min_posts" => "3" },
    "analytics.tags GETs /analytics/tags with only the given filters"
  )
  analytics.overview(period: "30d", tag: %w[Question Listicle])
  ok(
    OmniSocials::Internal.serialize_query(fake.last.query) ==
      { "period" => "30d", "tag" => "Question,Listicle" },
    "analytics.overview joins a tag Array with commas"
  )

  posts = OmniSocials::Resources::Posts.new(fake)
  posts.list(tag: 7)
  ok(
    OmniSocials::Internal.serialize_query(fake.last.query) == { "tag" => "7" },
    "posts.list takes a tag id"
  )
  posts.create(content: "Hi", tags: ["Question", 7])
  ok(fake.last.json == { "content" => "Hi", "tags" => ["Question", 7] }, "posts.create sends tags")
  posts.create_and_publish(content: "Hi", tags: ["Question"])
  ok(fake.last.json["tags"] == ["Question"], "posts.create_and_publish sends tags")
  posts.update("55", tags: nil)
  ok(
    fake.last.method == "PATCH" && fake.last.json == { "tags" => nil },
    "posts.update(tags: nil) sends an explicit null (clears)"
  )
  posts.update("55", content: "New text")
  ok(!fake.last.json.key?("tags"), "posts.update leaves tags out when not given")
end

def check_feature_requests_bodies(fake)
  puts "Limits and feature request bodies:"
  limits = OmniSocials::Resources::Limits.new(fake)
  limits.list(platform: "tiktok", area: "posts")
  ok(
    fake.last.method == "GET" && fake.last.path == "/limits" &&
      OmniSocials::Internal.serialize_query(fake.last.query) == { "platform" => "tiktok", "area" => "posts" },
    "limits.list GETs /limits with platform and area"
  )
  limits.list
  ok(OmniSocials::Internal.serialize_query(fake.last.query).nil?, "limits.list without filters sends no query")

  requests = OmniSocials::Resources::FeatureRequests.new(fake)
  requests.create(
    summary: "Post our daily update to the Announcements topic of our Telegram group.",
    platform: "telegram", limit_id: "telegram.forum_topics"
  )
  ok(
    fake.last.method == "POST" && fake.last.path == "/feature-requests" &&
      fake.last.json == {
        "summary" => "Post our daily update to the Announcements topic of our Telegram group.",
        "platform" => "telegram", "limit_id" => "telegram.forum_topics"
      },
    "feature_requests.create POSTs only the given keys (never source)"
  )
  requests.create(summary: "Reply to Google reviews from the inbox.", title: "Review replies", area: "inbox")
  ok(
    fake.last.json == { "summary" => "Reply to Google reviews from the inbox.", "title" => "Review replies", "area" => "inbox" },
    "feature_requests.create sends title and area"
  )
  requests.list
  ok(fake.last.method == "GET" && fake.last.path == "/feature-requests", "feature_requests.list GETs /feature-requests")
  requests.get(412)
  ok(fake.last.method == "GET" && fake.last.path == "/feature-requests/412", "feature_requests.get GETs /feature-requests/{id}")
end

DRAFT = {
  "name" => "Autumn sale",
  "objective" => "traffic",
  "platforms" => ["meta", { "platform" => "linkedin", "budget_amount" => 20 }],
  "budget" => { "amount" => 10, "currency" => "EUR" },
  "schedule" => { "duration_days" => nil },
  "targeting" => { "countries" => %w[NL BE], "automatic_audience" => true },
  "ads" => [
    {
      "media" => [{ "url" => "https://example.com/sale.jpg", "type" => "image" }],
      "primary_text" => "30% off everything this week",
      "link" => "https://example.com/sale"
    }
  ]
}.freeze

def draft_kwargs
  DRAFT.transform_keys(&:to_sym)
end

def check_ads_bodies(fake)
  ads = OmniSocials::Resources::Ads.new(fake)

  ads.drafts.create(**draft_kwargs)
  ok(
    fake.last.method == "POST" && fake.last.path == "/ads/drafts" && fake.last.json == DRAFT,
    "ads.drafts.create POSTs the draft to /ads/drafts (nested nil kept)"
  )
  ok(fake.last.retry_on.nil?, "ads.drafts.create keeps the normal retries")

  ads.drafts.update("g 1/x", **draft_kwargs)
  ok(
    fake.last.method == "PUT" && fake.last.path == "/ads/drafts/g%201%2Fx" &&
      fake.last.json == DRAFT,
    "ads.drafts.update PUTs the full body with the group id encoded"
  )

  ads.drafts.launch("g-1", confirm_budget_amount: 10)
  ok(
    fake.last.method == "POST" && fake.last.path == "/ads/drafts/g-1/launch" &&
      fake.last.json == { "confirm_budget_amount" => 10 },
    "ads.drafts.launch POSTs the confirmed amount"
  )
  ok(fake.last.retry_on == :rate_limit, "ads.drafts.launch retries a 429 only")
  ads.drafts.launch("g-1", confirm_budget_amounts: { "7" => 10 })
  ok(
    fake.last.json == { "confirm_budget_amounts" => { "7" => 10 } },
    "ads.drafts.launch sends per campaign amounts"
  )

  ads.activate(7, 25)
  ok(
    fake.last.method == "POST" && fake.last.path == "/ads/campaigns/7/activate" &&
      fake.last.json == { "confirm_budget_amount" => 25 },
    "ads.activate POSTs confirm_budget_amount"
  )
  ok(fake.last.retry_on == :rate_limit, "ads.activate retries a 429 only")

  ads.activate("51", 25)
  ok(
    fake.last.path == "/ads/campaigns/51/activate",
    "ads.activate takes the id as a String (the API sends ids as strings)"
  )

  ads.activate_multi([7, 8], 25)
  ok(
    fake.last.path == "/ads/campaigns/activate-multi" &&
      fake.last.json == { "campaign_ids" => [7, 8], "confirm_budget_amount" => 25 } &&
      fake.last.retry_on == :rate_limit,
    "ads.activate_multi sends campaign_ids and retries a 429 only"
  )

  ads.resume(7)
  ok(fake.last.retry_on == :rate_limit, "ads.resume retries a 429 only")
  ads.update(7, budget: { "amount" => 50, "currency" => "EUR" }, confirm_budget_amount: 50)
  ok(
    fake.last.method == "PATCH" && fake.last.retry_on == :rate_limit &&
      fake.last.json == { "budget" => { "amount" => 50, "currency" => "EUR" },
                          "confirm_budget_amount" => 50 },
    "ads.update PATCHes the budget and retries a 429 only"
  )

  ads.boost(post_id: 12_345, ad_account_id: 3, budget: { "amount" => 5, "currency" => "EUR" })
  ok(
    fake.last.path == "/ads/boost" &&
      fake.last.json == { "post_id" => 12_345, "ad_account_id" => 3,
                          "budget" => { "amount" => 5, "currency" => "EUR" } } &&
      fake.last.retry_on.nil?,
    "ads.boost makes a draft and keeps the normal retries"
  )

  ads.drafts.attach_account("g-1", platform: "meta", ad_account_id: 3)
  ok(
    fake.last.path == "/ads/drafts/g-1/account" &&
      fake.last.json == { "platform" => "meta", "ad_account_id" => 3 },
    "ads.drafts.attach_account POSTs the platform and the ad account"
  )

  ads.list(status: "active", limit: 5)
  ok(
    fake.last.method == "GET" && fake.last.path == "/ads/campaigns" &&
      OmniSocials::Internal.serialize_query(fake.last.query) == { "status" => "active", "limit" => "5" },
    "ads.list sends only the given filters"
  )

  check_ads_parity_bodies(ads, fake)
end

def check_ads_parity_bodies(ads, fake)
  ads.objects.tree(3, from: "2026-10-01", status: %w[active paused], limit: 10)
  ok(
    fake.last.method == "GET" && fake.last.path == "/ads/accounts/3/tree" &&
      OmniSocials::Internal.serialize_query(fake.last.query) ==
        { "from" => "2026-10-01", "status" => "active,paused", "limit" => "10" } &&
      fake.last.retry_on.nil?,
    "ads.objects.tree sends from and a comma status list, normal retries"
  )
  ads.objects.update(3, "ad_set", "238", name: "Autumn", end_at: nil)
  ok(
    fake.last.method == "PATCH" && fake.last.path == "/ads/accounts/3/objects/ad_set/238" &&
      fake.last.json == { "name" => "Autumn", "end_at" => nil } && fake.last.retry_on == :rate_limit,
    "ads.objects.update sends end_at: nil as null and retries a 429 only"
  )
  ads.objects.set_status(3, "campaign", "120", status: "active", confirm_budget_amount: 20)
  ok(
    fake.last.method == "PUT" && fake.last.path == "/ads/accounts/3/objects/campaign/120/status" &&
      fake.last.json == { "status" => "active", "confirm_budget_amount" => 20 } &&
      fake.last.retry_on == :rate_limit,
    "ads.objects.set_status PUTs the status and the amount, a 429 only"
  )
  ads.audiences.remove_members("aud 1", ad_account_id: 3, schema: ["email"], rows: [["fake-hash-1"]])
  ok(
    fake.last.method == "DELETE" && fake.last.path == "/ads/audiences/aud%201/members" &&
      fake.last.json == { "ad_account_id" => 3, "schema" => ["email"], "rows" => [["fake-hash-1"]] },
    "ads.audiences.remove_members sends DELETE with a body"
  )
  ads.media.delete("v9", ad_account_id: 3, type: "video")
  ok(
    fake.last.method == "DELETE" && fake.last.json.nil? &&
      OmniSocials::Internal.serialize_query(fake.last.query) == { "ad_account_id" => "3", "type" => "video" },
    "ads.media.delete sends ad_account_id and type in the query"
  )
  ads.reach_frequency.create(ad_account_id: 3, objective: "awareness", targeting: { "countries" => ["NL"] },
                             start_at: "2026-12-01T00:00:00Z", end_at: "2026-12-14T00:00:00Z",
                             reach: 200_000, frequency_cap: 2)
  ok(
    fake.last.path == "/ads/reach-frequency" && fake.last.json == {
      "ad_account_id" => 3, "objective" => "awareness", "targeting" => { "countries" => ["NL"] },
      "start_at" => "2026-12-01T00:00:00Z", "end_at" => "2026-12-14T00:00:00Z",
      "reach" => 200_000, "frequency_cap" => 2
    },
    "ads.reach_frequency.create sends the prediction fields"
  )
  ads.accounts.update_settings(3, spend_cap: nil, confirm_budget_amount: "remove")
  ok(
    fake.last.json == { "spend_cap" => nil, "confirm_budget_amount" => "remove" } &&
      fake.last.retry_on == :rate_limit,
    "ads.accounts.update_settings removes the cap with an explicit null"
  )
  ads.leads.list(since: "2026-10-01T00:00:00Z", until_time: "2026-10-31T00:00:00Z")
  ok(
    OmniSocials::Internal.serialize_query(fake.last.query) ==
      { "since" => "2026-10-01T00:00:00Z", "until" => "2026-10-31T00:00:00Z" },
    "ads.leads.list sends until_time as until"
  )
  ads.lead_forms.create(
    ad_account_id: 3, name: "Quote", privacy_policy_url: "https://example.com/privacy",
    questions: [{ "type" => "email" }], thank_you: { "title" => "Thanks" }, accept_terms: true
  )
  ok(fake.last.json["accept_terms"] == true, "ads.lead_forms.create sends accept_terms")
  ads.audiences.create(ad_account_id: 3, name: "Buyers", customer_file_source: "user_provided",
                       schema: ["email"], rows: [["fake-hash-2"]])
  ok(
    fake.last.json == {
      "ad_account_id" => 3, "name" => "Buyers", "customer_file_source" => "user_provided",
      "schema" => ["email"], "rows" => [["fake-hash-2"]]
    },
    "ads.audiences.create sends the first members"
  )
  ads.update(7, objective: "lead_generation", settings: { "lead_form_id" => "lf-1" })
  ok(
    fake.last.method == "PATCH" && fake.last.path == "/ads/campaigns/7" &&
      fake.last.json == { "objective" => "lead_generation", "settings" => { "lead_form_id" => "lf-1" } },
    "ads.update sends the objective and settings of a draft"
  )
  ads.rules.create(name: "Pause losers", conditions: [{ "metric" => "cpc", "op" => "gt", "value" => 3 }],
                   action: { "type" => "pause" })
  ok(fake.last.retry_on == :rate_limit, "ads.rules.create retries a 429 only")
  ads.budget_schedules.create(7, start_at: "2026-11-27T00:00:00Z", end_at: "2026-11-30T00:00:00Z",
                                 budget_increase: { "type" => "absolute", "value" => 30 },
                                 confirm_budget_amount: 30)
  ok(
    fake.last.path == "/ads/campaigns/7/budget-schedules" && fake.last.retry_on == :rate_limit,
    "ads.budget_schedules.create retries a 429 only"
  )
end

# ---------------------------------------------------------------------------
# 4. Webhook verification (signed exactly like webhookDispatcher.js)
# ---------------------------------------------------------------------------

# Mirror backend/services/webhooks/webhookDispatcher.js signPayload():
# HMAC-SHA256 hex over "#{timestamp}.#{rawBody}", header "t=<ts>,v1=<hex>".
def build_signature(secret, timestamp, raw_body)
  digest = OpenSSL::HMAC.hexdigest("SHA256", secret, "#{timestamp}.#{raw_body}")
  "t=#{timestamp},v1=#{digest}"
end

def check_webhook_verification
  puts "Webhook verification:"
  secret = "whsec_test_secret_abc123"
  event = {
    "id" => "e7c9a1b2-3d4e-5f6a-7b8c-9d0e1f2a3b4c",
    "type" => "post.published",
    "created_at" => "2026-07-14T10:00:05Z",
    "data" => { "post_id" => "123", "status" => "posted" }
  }
  raw_body = JSON.generate(event)
  timestamp = Time.now.to_i
  signature = build_signature(secret, timestamp, raw_body)

  parsed = OmniSocials::Webhooks.verify(
    payload: raw_body, signature: signature, secret: secret
  )
  ok(parsed == event, "valid signature verifies and returns the parsed event")

  rejected = {
    "id" => "e7c9a1b2-3d4e-5f6a-7b8c-9d0e1f2a3b4d",
    "type" => "post.rejected",
    "created_at" => "2026-10-02T09:00:05.000Z",
    "data" => {
      "post_id" => "123456",
      "workspace_id" => 789,
      "status" => "rejected",
      "targets" => [],
      "approval" => {
        "status" => "rejected", "decided_by" => "c4a09e1d", "reason" => "Wrong product photo"
      }
    }
  }
  rejected_body = JSON.generate(rejected)
  parsed_rejected = OmniSocials::Webhooks.verify(
    payload: rejected_body,
    signature: build_signature(secret, timestamp, rejected_body),
    secret: secret
  )
  ok(
    parsed_rejected["type"] == "post.rejected" &&
      parsed_rejected["data"]["approval"] == rejected["data"]["approval"],
    "post.rejected event keeps its approval object"
  )

  ad_event = {
    "id" => "b1f2c3d4-5e6f-7a8b-9c0d-1e2f3a4b5c6d",
    "type" => "ad.status_changed",
    "created_at" => "2026-07-13T10:00:05Z",
    "data" => {
      "campaign_id" => 42,
      "workspace_id" => "456",
      "name" => "Boost: Summer launch post",
      "platform" => "meta",
      "campaign_type" => "boost",
      "status" => "active",
      "previous_status" => "pending_review",
      "external_campaign_id" => "23851234567890123",
      "budget" => { "type" => "daily", "amount" => 10, "currency" => "EUR" }
    }
  }
  ad_body = JSON.generate(ad_event)
  parsed_ad = OmniSocials::Webhooks.verify(
    payload: ad_body, signature: build_signature(secret, timestamp, ad_body), secret: secret
  )
  ok(
    parsed_ad["type"] == "ad.status_changed" && parsed_ad["data"] == ad_event["data"],
    "ad.status_changed event verifies and keeps its campaign data"
  )

  tampered = raw_body.sub("posted", "hacked")
  assert_raises(OmniSocials::WebhookVerificationError, "tampered body raises") do
    OmniSocials::Webhooks.verify(payload: tampered, signature: signature, secret: secret)
  end

  stale_ts = Time.now.to_i - 3600
  stale_signature = build_signature(secret, stale_ts, raw_body)
  assert_raises(OmniSocials::WebhookVerificationError, "stale timestamp (1h old) raises") do
    OmniSocials::Webhooks.verify(payload: raw_body, signature: stale_signature, secret: secret)
  end

  parsed_stale = OmniSocials::Webhooks.verify(
    payload: raw_body, signature: stale_signature, secret: secret, tolerance: nil
  )
  ok(parsed_stale == event, "tolerance: nil skips the timestamp check")

  future_ts = Time.now.to_i + 3600
  future_signature = build_signature(secret, future_ts, raw_body)
  assert_raises(OmniSocials::WebhookVerificationError, "far-future timestamp raises") do
    OmniSocials::Webhooks.verify(payload: raw_body, signature: future_signature, secret: secret)
  end

  # Secret rotation: for 24 hours a delivery also carries
  # X-OmniSocials-Signature-Previous, the same scheme signed with the OLD
  # secret. The new secret fails on it; the old secret verifies it.
  old_secret = "whsec_test_old_secret"
  previous_header = build_signature(old_secret, timestamp, raw_body)
  assert_raises(OmniSocials::WebhookVerificationError, "the new secret does not verify the Previous header") do
    OmniSocials::Webhooks.verify(payload: raw_body, signature: previous_header, secret: secret)
  end
  ok(
    OmniSocials::Webhooks.verify(payload: raw_body, signature: previous_header, secret: old_secret) == event,
    "the Previous header verifies with the old secret"
  )

  assert_raises(OmniSocials::WebhookVerificationError, "wrong secret raises") do
    OmniSocials::Webhooks.verify(payload: raw_body, signature: signature, secret: "wrong_secret")
  end

  ["", "v1=abc", "t=#{timestamp}", "t=notanint,v1=abc", nil].each do |bad|
    assert_raises(OmniSocials::WebhookVerificationError, "malformed header #{bad.inspect} raises") do
      OmniSocials::Webhooks.verify(payload: raw_body, signature: bad, secret: secret)
    end
  end

  assert_raises(OmniSocials::WebhookVerificationError, "non-String payload raises") do
    OmniSocials::Webhooks.verify(payload: { a: 1 }, signature: signature, secret: secret)
  end

  bad_json_sig = build_signature(secret, Time.now.to_i, "not json")
  assert_raises(OmniSocials::WebhookVerificationError, "non-JSON (but signed) payload raises") do
    OmniSocials::Webhooks.verify(payload: "not json", signature: bad_json_sig, secret: secret)
  end
end

# ---------------------------------------------------------------------------
# 5. Live transport behavior against a scripted loopback server
# ---------------------------------------------------------------------------

def http_response(status, body = "", headers = {})
  reason = {
    200 => "OK", 201 => "Created", 204 => "No Content", 404 => "Not Found", 409 => "Conflict",
    429 => "Too Many Requests", 500 => "Internal Server Error", 502 => "Bad Gateway"
  }.fetch(status)
  all = { "Connection" => "close" }
  unless status == 204
    all["Content-Type"] = "application/json"
    all["Content-Length"] = body.bytesize.to_s
  end
  all.merge!(headers)
  raw = +"HTTP/1.1 #{status} #{reason}\r\n"
  all.each { |k, v| raw << "#{k}: #{v}\r\n" }
  raw << "\r\n"
  raw << body unless status == 204
  raw
end

# Read one request: the head, then the body up to its Content-Length.
def read_request(sock)
  raw = +""
  raw << sock.readpartial(65_536) until raw.include?("\r\n\r\n")
  head, body = raw.split("\r\n\r\n", 2)
  length = head[/^content-length:\s*(\d+)/i, 1].to_i
  body << sock.readpartial(65_536) while body.bytesize < length
  "#{head}\r\n\r\n#{body}"
end

# Serves the scripted responses in order (:drop closes the connection without
# an answer), then records any further request and answers it with a 500, so
# a test sees a retry it did not script.
def with_scripted_server(responses)
  server = TCPServer.new("127.0.0.1", 0)
  port = server.addr[1]
  requests = []
  unexpected = http_response(500, '{"error":{"message":"unexpected request"}}')
  thread = Thread.new do
    Thread.current.report_on_exception = false
    (responses + [unexpected] * 5).each do |response|
      sock = server.accept
      requests << read_request(sock)
      sock.write(response) unless response == :drop
      sock.close
    end
  end
  yield port, requests
ensure
  thread&.kill
  server.close
end

def check_live_transport
  puts "Live transport (scripted loopback server):"

  # Retry on 429 honoring Retry-After: 0, then succeed.
  with_scripted_server(
    [
      http_response(429, '{"error":{"code":"rate_limited","message":"slow down"}}',
                    { "Retry-After" => "0" }),
      http_response(200, '{"ok":true}')
    ]
  ) do |port, requests|
    client = OmniSocials::Client.new(api_key: "omsk_test_x", base_url: "http://127.0.0.1:#{port}")
    result = client.health
    ok(result == { "ok" => true }, "429 is retried (honoring Retry-After) and the retry succeeds")
    ok(requests.length == 2, "exactly two requests were made")
    ok(requests[0].include?("GET /health HTTP/1.1"), "request line targets /health")
    ok(requests[0].include?("Authorization: Bearer omsk_test_x"), "Authorization header is sent")
    ok(requests[0].include?("User-Agent: omnisocials-ruby/#{OmniSocials::VERSION}"), "User-Agent header is sent")
  end

  # 500 twice with max_retries: 1 exhausts retries and raises ServerError.
  with_scripted_server(
    [http_response(500, '{"error":{"message":"boom"}}'),
     http_response(500, '{"error":{"message":"boom"}}')]
  ) do |port, requests|
    client = OmniSocials::Client.new(
      api_key: "omsk_test_x", base_url: "http://127.0.0.1:#{port}", max_retries: 1
    )
    err = assert_raises(OmniSocials::ServerError, "500 raises ServerError after retries") do
      client.health
    end
    ok(err.status == 500 && err.message == "boom", "ServerError carries status and body message")
    ok(requests.length == 2, "500 was retried once (max_retries: 1)")
  end

  # 404 maps to NotFoundError with code/message from the body; not retried.
  with_scripted_server(
    [http_response(404, '{"error":{"code":"post_not_found","message":"Post not found"}}')]
  ) do |port, requests|
    client = OmniSocials::Client.new(api_key: "omsk_test_x", base_url: "http://127.0.0.1:#{port}")
    err = assert_raises(OmniSocials::NotFoundError, "404 raises NotFoundError") do
      client.posts.get("nope")
    end
    ok(err.code == "post_not_found" && err.message == "Post not found" && err.status == 404,
       "NotFoundError carries code/message/status from the body")
    ok(err.body.is_a?(Hash) && err.body["error"]["code"] == "post_not_found",
       "NotFoundError#body is the parsed JSON body")
    ok(requests.length == 1, "404 is not retried")
  end

  # A review that moved on: 409 step_changed keeps current_step_order.
  with_scripted_server(
    [http_response(409, '{"error":{"code":"step_changed","message":"The review is on step 2 now.","current_step_order":2}}')]
  ) do |port, requests|
    client = OmniSocials::Client.new(api_key: "omsk_test_x", base_url: "http://127.0.0.1:#{port}")
    err = assert_raises(OmniSocials::APIError, "409 step_changed raises APIError") do
      client.posts.approve("1024", step_order: 1)
    end
    ok(err.status == 409 && err.code == "step_changed" && err.body["error"]["current_step_order"] == 2,
       "step_changed carries current_step_order in the body")
    ok(requests[0].include?("POST /posts/1024/approve HTTP/1.1") && requests[0].include?('{"step_order":1}'),
       "approve sends POST /posts/1024/approve with step_order")
  end

  # 204 returns nil.
  with_scripted_server([http_response(204)]) do |port, requests|
    client = OmniSocials::Client.new(api_key: "omsk_test_x", base_url: "http://127.0.0.1:#{port}")
    ok(client.posts.delete("1").nil?, "204 returns nil")
    ok(requests[0].include?("DELETE /posts/1 HTTP/1.1"), "delete sends DELETE /posts/1")
  end

  # RateLimitError exposes retry_after from the header (max_retries: 0).
  with_scripted_server(
    [http_response(429, '{"error":{"code":"rate_limited","message":"slow down"}}',
                   { "Retry-After" => "7" })]
  ) do |port, _requests|
    client = OmniSocials::Client.new(
      api_key: "omsk_test_x", base_url: "http://127.0.0.1:#{port}", max_retries: 0
    )
    err = assert_raises(OmniSocials::RateLimitError, "429 raises RateLimitError with retries off") do
      client.health
    end
    ok(err.retry_after == 7.0, "RateLimitError#retry_after comes from the Retry-After header")
    ok(err.code == "rate_limited", "RateLimitError#code comes from the body")
  end

  check_feature_requests_transport
  check_ads_transport

  # Connection refused raises APIConnectionError.
  closed_port_server = TCPServer.new("127.0.0.1", 0)
  closed_port = closed_port_server.addr[1]
  closed_port_server.close
  client = OmniSocials::Client.new(
    api_key: "omsk_test_x", base_url: "http://127.0.0.1:#{closed_port}", max_retries: 0
  )
  assert_raises(OmniSocials::APIConnectionError, "connection failure raises APIConnectionError") do
    client.health
  end
end

def check_feature_requests_transport
  limit = {
    "id" => "tiktok.delete", "kind" => "platform", "kind_label" => "The platform does not allow it",
    "area" => "posts", "platforms" => ["tiktok"], "title" => "Delete a TikTok video",
    "says" => "TikTok's API cannot delete a video.", "instead" => "Delete the video in the TikTok app.",
    "requestable" => false
  }
  conflict = JSON.generate(
    "error" => {
      "code" => "not_requestable",
      "message" => "TikTok's API cannot delete a video. A request cannot change this, so nothing was sent.",
      "limit" => limit
    }
  )
  with_scripted_server([http_response(409, conflict)]) do |port, requests|
    err = assert_raises(OmniSocials::APIError, "a not_requestable limit raises APIError") do
      ads_client(port).feature_requests.create(summary: "Delete my TikTok videos.", limit_id: "tiktok.delete")
    end
    ok(
      err.status == 409 && err.code == "not_requestable" &&
        err.body["error"]["limit"]["instead"] == "Delete the video in the TikTok app.",
      "409 not_requestable keeps the limit in the error body"
    )
    ok(requests.length == 1, "a 409 is not retried")
  end

  with_scripted_server(
    [http_response(200, '{"outcome":"already_requested","data":{"id":412,"status":"open"}}')]
  ) do |port, _requests|
    result = ads_client(port).feature_requests.create(summary: "Post to a Telegram topic, please.")
    ok(
      result["outcome"] == "already_requested" && result["data"]["id"] == 412,
      "feature_requests.create returns the outcome next to data"
    )
  end
end

def ads_client(port)
  OmniSocials::Client.new(
    api_key: "omsk_test_x", base_url: "http://127.0.0.1:#{port}", timeout: 5
  )
end

def check_ads_transport
  bad_gateway = http_response(
    502, '{"error":{"code":"bad_gateway","message":"upstream"}}', { "Retry-After" => "0" }
  )
  money_calls = {
    "drafts.launch" => ->(ads) { ads.drafts.launch("g-1", confirm_budget_amount: 10) },
    "activate" => ->(ads) { ads.activate(7, 25) },
    "activate_multi" => ->(ads) { ads.activate_multi([7, 8], 25) },
    "resume" => ->(ads) { ads.resume(7) },
    "update" => ->(ads) { ads.update(7, budget: { "amount" => 50, "currency" => "EUR" }, confirm_budget_amount: 50) },
    "objects.update" => lambda { |ads|
      ads.objects.update(3, "ad_set", "238", budget: { "amount" => 40, "currency" => "EUR" }, confirm_budget_amount: 40)
    },
    "objects.set_status" => ->(ads) { ads.objects.set_status(3, "campaign", "120", status: "active", confirm_budget_amount: 20) },
    "bulk_status" => ->(ads) { ads.bulk_status(campaign_ids: [7, 8], status: "active", confirm_budget_amount: 25) },
    "campaign_ads.set_status" => ->(ads) { ads.campaign_ads.set_status(7, 51, status: "active", confirm_budget_amount: 25) },
    "rules.create" => lambda { |ads|
      ads.rules.create(name: "Scale", conditions: [{ "metric" => "ctr", "op" => "gt", "value" => 2 }],
                       action: { "type" => "adjust_budget", "percent" => 20, "max_daily_budget" => 50 },
                       confirm_max_daily_budget: 50)
    },
    "rules.update" => ->(ads) { ads.rules.update(4, enabled: true) },
    "rules.undo" => ->(ads) { ads.rules.undo(9, confirm_budget_amount: 25) },
    "accounts.update_settings" => ->(ads) { ads.accounts.update_settings(3, spend_cap: 500, confirm_budget_amount: 500) },
    "reach_frequency.reserve" => ->(ads) { ads.reach_frequency.reserve("rf-1", ad_account_id: 3, confirm_budget_amount: 1000) },
    "budget_schedules.create" => lambda { |ads|
      ads.budget_schedules.create(7, start_at: "2026-11-27T00:00:00Z", end_at: "2026-11-30T00:00:00Z",
                                     budget_increase: { "type" => "absolute", "value" => 30 }, confirm_budget_amount: 30)
    }
  }

  money_calls.each do |name, call|
    with_scripted_server([bad_gateway]) do |port, requests|
      assert_raises(OmniSocials::ServerError, "ads.#{name} raises ServerError on a 502") do
        call.call(ads_client(port).ads)
      end
      ok(requests.length == 1, "ads.#{name} after a 502 is sent exactly once")
    end
  end

  with_scripted_server([bad_gateway]) do |port, requests|
    ads_client(port).ads.drafts.launch("g-1", confirm_budget_amount: 10) rescue nil
    ok(
      requests[0].start_with?("POST /ads/drafts/g-1/launch HTTP/1.1") &&
        requests[0].end_with?('{"confirm_budget_amount":10}'),
      "ads.drafts.launch sends POST /ads/drafts/g-1/launch with the amount"
    )
  end

  with_scripted_server([:drop]) do |port, requests|
    assert_raises(OmniSocials::APIConnectionError, "a lost connection on ads.activate raises") do
      ads_client(port).ads.activate(7, 25)
    end
    ok(requests.length == 1, "ads.activate after a lost connection is sent exactly once")
  end

  with_scripted_server(
    [http_response(429, '{"error":{"code":"rate_limited"}}', { "Retry-After" => "0" }),
     http_response(200, '{"data":{"ok":true}}')]
  ) do |port, requests|
    ads_client(port).ads.activate(7, 25)
    ok(requests.length == 2, "ads.activate after a 429 is retried")
  end

  with_scripted_server([bad_gateway, http_response(200, '{"data":{"ok":true}}')]) do |port, requests|
    result = ads_client(port).ads.capabilities
    ok(
      requests.length == 2 && result == { "data" => { "ok" => true } },
      "ads.capabilities (a read) after a 502 is retried"
    )
  end

  with_scripted_server([http_response(200, '{"data":{"ok":true}}')]) do |port, requests|
    ads_client(port).ads.drafts.update("g-1", **draft_kwargs)
    ok(
      requests[0].start_with?("PUT /ads/drafts/g-1 HTTP/1.1") &&
        JSON.parse(requests[0].split("\r\n\r\n", 2)[1]) == DRAFT,
      "ads.drafts.update sends PUT /ads/drafts/g-1 with the full body"
    )
  end
end

# ---------------------------------------------------------------------------
# 6. Path segments: a caller-supplied id stays inside one encoded segment
# ---------------------------------------------------------------------------

# Every method that puts a caller-supplied id into the request path:
# [resource class, method, HTTP method, path before the id, path after the id].
ID_PATHS = [
  [OmniSocials::Resources::Accounts, :get, "GET", "/accounts/", ""],
  [OmniSocials::Resources::Analytics, :post, "GET", "/analytics/posts/", ""],
  [OmniSocials::Resources::FeatureRequests, :get, "GET", "/feature-requests/", ""],
  [OmniSocials::Resources::Folders, :update, "PATCH", "/folders/", ""],
  [OmniSocials::Resources::Folders, :delete, "DELETE", "/folders/", ""],
  [OmniSocials::Resources::HashtagSets, :get, "GET", "/hashtag-sets/", ""],
  [OmniSocials::Resources::HashtagSets, :update, "PATCH", "/hashtag-sets/", ""],
  [OmniSocials::Resources::HashtagSets, :delete, "DELETE", "/hashtag-sets/", ""],
  [OmniSocials::Resources::Media, :get, "GET", "/media/", ""],
  [OmniSocials::Resources::Media, :update, "PATCH", "/media/", ""],
  [OmniSocials::Resources::Media, :delete, "DELETE", "/media/", ""],
  [OmniSocials::Resources::Tags, :update, "PATCH", "/tags/", ""],
  [OmniSocials::Resources::Tags, :delete, "DELETE", "/tags/", ""],
  [OmniSocials::Resources::Webhooks, :get, "GET", "/webhooks/", ""],
  [OmniSocials::Resources::Webhooks, :update, "PATCH", "/webhooks/", ""],
  [OmniSocials::Resources::Webhooks, :delete, "DELETE", "/webhooks/", ""],
  [OmniSocials::Resources::Webhooks, :rotate_secret, "POST", "/webhooks/", "/rotate-secret"],
  [OmniSocials::Resources::Posts, :get, "GET", "/posts/", ""],
  [OmniSocials::Resources::Posts, :update, "PATCH", "/posts/", ""],
  [OmniSocials::Resources::Posts, :delete, "DELETE", "/posts/", ""],
  [OmniSocials::Resources::Posts, :publish, "POST", "/posts/", "/publish"],
  [OmniSocials::Resources::Posts, :retry, "POST", "/posts/", "/retry"],
  [OmniSocials::Resources::Posts, :approve, "POST", "/posts/", "/approve"],
  [OmniSocials::Resources::Posts, :reject, "POST", "/posts/", "/reject"],
  [OmniSocials::Resources::Posts, :get_approval, "GET", "/posts/", "/approval"],
  [OmniSocials::Resources::Automations, :get, "GET", "/automations/", ""],
  [OmniSocials::Resources::Automations, :update, "PATCH", "/automations/", ""],
  [OmniSocials::Resources::Automations, :delete, "DELETE", "/automations/", ""],
  [OmniSocials::Resources::Automations, :list_events, "GET", "/automations/", "/events"],
  [OmniSocials::Resources::Inbox, :mark_read, "POST", "/inbox/conversations/", "/read"]
].freeze

# An id an integrator might pass on from its own users. Unencoded, "/" adds
# segments, ".." climbs out of /posts and "#" cuts off the rest of the path:
# posts.publish(HOSTILE_ID) would POST /webhooks/wh_fake/rotate-secret.
HOSTILE_ID = "../webhooks/wh_fake/rotate-secret#"
HOSTILE_SEGMENT = "..%2Fwebhooks%2Fwh_fake%2Frotate-secret%23"

def check_path_segments
  puts "Path segments (fake transport):"
  fake = FakeTransport.new
  ID_PATHS.each do |klass, name, verb, before, after|
    klass.new(fake).public_send(name, HOSTILE_ID)
    ok(
      fake.last.method == verb && fake.last.path == "#{before}#{HOSTILE_SEGMENT}#{after}",
      "#{klass.name.split("::").last}##{name} keeps a hostile id inside one segment of #{before}{id}#{after}"
    )
  end

  posts = OmniSocials::Resources::Posts.new(fake)
  [["a b", "a%20b"], ["x?y=1", "x%3Fy%3D1"], ["50%", "50%25"], [42, "42"]].each do |value, encoded|
    posts.get(value)
    ok(fake.last.path == "/posts/#{encoded}", "posts.get(#{value.inspect}) sends /posts/#{encoded}")
  end

  puts "Path segments (scripted loopback server):"
  with_scripted_server([http_response(200, '{"data":{"ok":true}}')]) do |port, requests|
    client = OmniSocials::Client.new(api_key: "omsk_test_x", base_url: "http://127.0.0.1:#{port}")
    client.posts.publish(HOSTILE_ID)
    ok(
      requests[0].start_with?("POST /posts/#{HOSTILE_SEGMENT}/publish HTTP/1.1"),
      "posts.publish sends POST /posts/{encoded id}/publish, not /webhooks/.../rotate-secret"
    )
  end

  # Port 9 is closed: an id that is refused raises ArgumentError before any
  # connection; one that is sent would raise APIConnectionError instead.
  client = OmniSocials::Client.new(api_key: "omsk_test_x", base_url: "http://127.0.0.1:9", max_retries: 0)
  ["", ".", ".."].each do |bad|
    assert_raises(ArgumentError, "posts.delete(#{bad.inspect}) raises ArgumentError before sending") do
      client.posts.delete(bad)
    end
    assert_raises(ArgumentError, "webhooks.rotate_secret(#{bad.inspect}) raises ArgumentError") do
      client.webhooks.rotate_secret(bad)
    end
    assert_raises(ArgumentError, "inbox.mark_read(#{bad.inspect}) raises ArgumentError") do
      client.inbox.mark_read(bad)
    end
    assert_raises(ArgumentError, "ads.get(#{bad.inspect}) raises ArgumentError") do
      client.ads.get(bad)
    end
  end
end

check_client_surface
check_construction_guards
check_body_building
check_webhook_verification
check_live_transport
check_path_segments

puts "\nAll #{$checks} checks passed."
