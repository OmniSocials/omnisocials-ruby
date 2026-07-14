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
                   tiktok x bluesky mastodon google_business].freeze
CREATE_KEYS = (%i[channels scheduled_at media_ids media_urls type source
                  link_url link_title link_description link_thumbnail_url
                  location_id collaborators user_tags] + PLATFORM_KEYS).freeze
CREATE_AND_PUBLISH_KEYS = (CREATE_KEYS - [:scheduled_at]).freeze
UPDATE_KEYS = (%i[content scheduled_at channels media_ids media_urls type
                  location_id collaborators user_tags] + PLATFORM_KEYS).freeze

def kw(names)
  names.map { |name| [:key, name] }
end

EXPECTED_SURFACE = {
  posts: {
    list: kw(%i[status limit offset]),
    get: [[:req, :post_id]],
    recent_platform: kw(%i[limit platforms]),
    create: [[:keyreq, :content]] + kw(CREATE_KEYS),
    create_and_publish: [[:keyreq, :content]] + kw(CREATE_AND_PUBLISH_KEYS),
    update: [[:req, :post_id]] + kw(UPDATE_KEYS),
    delete: [[:req, :post_id]],
    publish: [[:req, :post_id]]
  },
  media: {
    list: kw(%i[limit offset search folder_id]),
    get: [[:req, :media_id]],
    upload: [[:keyreq, :file]] + kw(%i[filename name folder folder_id]),
    upload_from_url: [[:keyreq, :url]] + kw(%i[filename name folder folder_id]),
    upload_from_base64: [%i[keyreq data], %i[keyreq mime_type]] +
                        kw(%i[filename name folder folder_id]),
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
  accounts: {
    list: [],
    get: [[:req, :account_id]]
  },
  analytics: {
    post: [[:req, :post_id]],
    posts: [[:req, :ids]],
    overview: kw(%i[period start_date end_date]),
    accounts: kw(%i[platform date]),
    best_times: [[:keyreq, :platform], [:key, :timezone]]
  },
  locations: {
    search: [[:req, :q]],
    validate: [[:req, :id]]
  },
  webhooks: {
    list: [],
    get: [[:req, :webhook_id]],
    create: [%i[keyreq url], %i[keyreq events]],
    update: [[:req, :webhook_id]] + kw(%i[url events is_active]),
    delete: [[:req, :webhook_id]],
    rotate_secret: [[:req, :webhook_id]]
  }
}.freeze

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
  Call = Struct.new(:method, :path, :query, :json, :multipart)

  attr_reader :calls

  def initialize
    @calls = []
  end

  def request(method, path, query: nil, json: nil, multipart: nil)
    @calls << Call.new(method, path, query, json, multipart)
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

  webhooks = OmniSocials::Resources::Webhooks.new(fake)
  webhooks.update("w1", is_active: false)
  ok(
    fake.last.json == { "is_active" => false },
    "webhooks.update keeps false values while dropping nils"
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
    200 => "OK", 204 => "No Content", 404 => "Not Found",
    429 => "Too Many Requests", 500 => "Internal Server Error"
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

def with_scripted_server(responses)
  server = TCPServer.new("127.0.0.1", 0)
  port = server.addr[1]
  requests = []
  thread = Thread.new do
    responses.each do |response|
      sock = server.accept
      raw = +""
      raw << sock.readpartial(65_536) until raw.include?("\r\n\r\n")
      requests << raw
      sock.write(response)
      sock.close
    end
  end
  yield port, requests
  thread.join(10)
ensure
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

check_client_surface
check_construction_guards
check_body_building
check_webhook_verification
check_live_transport

puts "\nAll #{$checks} checks passed."
