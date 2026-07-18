# frozen_string_literal: true

require "json"
require "net/http"
require "openssl"
require "securerandom"
require "time"
require "uri"

module OmniSocials
  # Synchronous client for the OmniSocials Public API.
  #
  #   require "omnisocials"
  #
  #   client = OmniSocials::Client.new  # reads OMNISOCIALS_API_KEY from env
  #   # or: OmniSocials::Client.new(api_key: "omsk_live_...", base_url: ...,
  #   #                             timeout: ..., max_retries: ...)
  #
  #   post = client.posts.create(
  #     content: "Hello from the SDK",
  #     channels: ["instagram", "linkedin"],
  #     scheduled_at: "2026-08-01T09:00:00Z"
  #   )
  #
  # Zero runtime dependencies: built on Net::HTTP, OpenSSL, and JSON from the
  # Ruby standard library. A fresh connection is opened per request, so there
  # is nothing to close.
  class Client
    DEFAULT_BASE_URL = "https://api.omnisocials.com/v1"
    DEFAULT_TIMEOUT = 30.0
    DEFAULT_MAX_RETRIES = 2
    USER_AGENT = "omnisocials-ruby/#{VERSION}"

    # Statuses that are retried automatically (alongside connection errors).
    RETRY_STATUSES = [429, 500, 502, 503, 504].freeze

    METHOD_CLASSES = {
      "GET" => Net::HTTP::Get,
      "POST" => Net::HTTP::Post,
      "PATCH" => Net::HTTP::Patch,
      "DELETE" => Net::HTTP::Delete
    }.freeze

    CONNECTION_ERRORS = [
      Errno::ECONNREFUSED,
      Errno::ECONNRESET,
      Errno::EHOSTUNREACH,
      Errno::ENETUNREACH,
      Errno::EPIPE,
      Errno::ETIMEDOUT,
      SocketError,
      EOFError,
      IOError,
      Net::OpenTimeout,
      Net::ReadTimeout,
      Net::WriteTimeout,
      OpenSSL::SSL::SSLError,
      Timeout::Error
    ].freeze

    attr_reader :api_key, :base_url, :timeout, :max_retries,
                :posts, :media, :folders, :accounts, :analytics, :audio,
                :locations, :webhooks

    # api_key     - API key (omsk_live_* / omsk_test_*). Falls back to the
    #               OMNISOCIALS_API_KEY environment variable. Raises
    #               OmniSocials::AuthenticationError when neither is set.
    # base_url    - API base URL (default https://api.omnisocials.com/v1).
    # timeout     - per-request timeout in seconds (default 30).
    # max_retries - automatic retries after the first attempt (default 2),
    #               applied on 429, 5xx, and connection errors.
    def initialize(api_key: nil, base_url: nil, timeout: DEFAULT_TIMEOUT,
                   max_retries: DEFAULT_MAX_RETRIES)
      key = api_key.nil? || api_key.to_s.empty? ? ENV["OMNISOCIALS_API_KEY"] : api_key
      if key.nil? || key.to_s.empty?
        raise AuthenticationError.new(
          "No API key provided. Pass api_key: ... to OmniSocials::Client.new " \
          "or set the OMNISOCIALS_API_KEY environment variable. Create a key " \
          "in the OmniSocials app under Settings -> API Keys.",
          status: nil
        )
      end
      @api_key = key
      @base_url = (base_url || DEFAULT_BASE_URL).sub(%r{/+\z}, "")
      @timeout = Float(timeout)
      @max_retries = [max_retries.to_i, 0].max

      @posts = Resources::Posts.new(self)
      @media = Resources::Media.new(self)
      @folders = Resources::Folders.new(self)
      @accounts = Resources::Accounts.new(self)
      @analytics = Resources::Analytics.new(self)
      @audio = Resources::Audio.new(self)
      @locations = Resources::Locations.new(self)
      @webhooks = Resources::Webhooks.new(self)
    end

    # GET /health - API health check (no scopes required).
    def health
      request("GET", "/health")
    end

    # Perform an HTTP request against the API with automatic retries.
    #
    # Returns the parsed response body (Hash/Array) as-is, the raw text for
    # non-JSON responses, or nil for 204. Raises an OmniSocials::APIError
    # subclass on non-2xx and OmniSocials::APIConnectionError when no
    # response was ever received.
    def request(method, path, query: nil, json: nil, multipart: nil)
      uri = build_uri(path, query)
      last_error = nil

      (max_retries + 1).times do |attempt|
        begin
          response = perform(method, uri, json: json, multipart: multipart)
        rescue *CONNECTION_ERRORS => e
          last_error = e
          break if attempt >= max_retries

          sleep(Internal.backoff_delay(attempt, nil))
          next
        end

        should_retry, retry_after = retry_info(response)
        if should_retry && attempt < max_retries
          sleep(Internal.backoff_delay(attempt, retry_after))
          next
        end
        return handle_response(response)
      end

      raise APIConnectionError,
            "Connection error while requesting #{method} #{uri}: " \
            "#{last_error.class}: #{last_error.message}"
    end

    private

    def build_uri(path, query)
      uri = URI.parse("#{base_url}#{path}")
      pairs = Internal.serialize_query(query)
      uri.query = URI.encode_www_form(pairs) if pairs
      uri
    end

    def perform(method, uri, json:, multipart:)
      request_class = METHOD_CLASSES.fetch(method) do
        raise ArgumentError, "Unsupported HTTP method: #{method}"
      end
      req = request_class.new(uri)
      req["Authorization"] = "Bearer #{api_key}"
      req["User-Agent"] = USER_AGENT
      req["Accept"] = "application/json"

      if json
        req["Content-Type"] = "application/json"
        req.body = JSON.generate(json)
      elsif multipart
        boundary = "----OmniSocialsRuby#{SecureRandom.hex(16)}"
        req["Content-Type"] = "multipart/form-data; boundary=#{boundary}"
        req.body = Internal.multipart_body(
          boundary, multipart[:fields] || {}, multipart[:filename], multipart[:data]
        )
      end

      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = uri.scheme == "https"
      http.open_timeout = timeout
      http.read_timeout = timeout
      http.write_timeout = timeout
      http.start { |conn| conn.request(req) }
    end

    def retry_info(response)
      status = response.code.to_i
      if RETRY_STATUSES.include?(status) || status >= 500
        [true, parse_retry_after(response, Internal.parse_body(response.body))]
      else
        [false, nil]
      end
    end

    def handle_response(response)
      status = response.code.to_i
      return nil if status == 204
      return Internal.parse_body(response.body) if status >= 200 && status < 300

      raise error_from_response(response)
    end

    def error_from_response(response)
      body = Internal.parse_body(response.body)
      status = response.code.to_i

      code = nil
      message = "Request failed with status #{status}."
      if body.is_a?(Hash)
        error = body["error"]
        if error.is_a?(Hash)
          code = error["code"] if error["code"].is_a?(String)
          message = error["message"] if error["message"].is_a?(String)
        elsif body["message"].is_a?(String)
          message = body["message"]
        end
      end

      case status
      when 401
        AuthenticationError.new(message, status: status, code: code, body: body)
      when 403
        PermissionDeniedError.new(message, status: status, code: code, body: body)
      when 404
        NotFoundError.new(message, status: status, code: code, body: body)
      when 400, 422
        ValidationError.new(message, status: status, code: code, body: body)
      when 429
        RateLimitError.new(
          message,
          status: status, code: code, body: body,
          retry_after: parse_retry_after(response, body)
        )
      else
        if status >= 500
          ServerError.new(message, status: status, code: code, body: body)
        else
          APIError.new(message, status: status, code: code, body: body)
        end
      end
    end

    def parse_retry_after(response, body)
      header = response["retry-after"]
      if header
        stripped = header.strip
        return [stripped.to_f, 0.0].max if stripped.match?(/\A-?\d+(\.\d+)?\z/)

        begin
          return [Time.httpdate(stripped) - Time.now, 0.0].max
        rescue ArgumentError
          # Not an HTTP-date either; fall through to the body.
        end
      end
      if body.is_a?(Hash) && body["retry_after"].is_a?(Numeric)
        return [body["retry_after"].to_f, 0.0].max
      end

      nil
    end
  end
end
