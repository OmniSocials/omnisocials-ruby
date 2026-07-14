# frozen_string_literal: true

module OmniSocials
  # Error hierarchy for the OmniSocials SDK.
  #
  #   OmniSocials::Error (base)
  #     OmniSocials::APIError (has #status, #code, #message, #body)
  #       OmniSocials::AuthenticationError (401)
  #       OmniSocials::PermissionDeniedError (403)
  #       OmniSocials::NotFoundError (404)
  #       OmniSocials::ValidationError (400 / 422)
  #       OmniSocials::RateLimitError (429, exposes #retry_after seconds when known)
  #       OmniSocials::ServerError (>= 500)
  #     OmniSocials::APIConnectionError (network failure / timeout)
  #     OmniSocials::WebhookVerificationError

  # Base class for every error raised by this SDK.
  class Error < StandardError; end

  # A non-2xx response from the OmniSocials API.
  #
  # Attributes:
  #   status - HTTP status code (nil for client-side failures such as a
  #            missing API key at construction time).
  #   code   - machine-readable error code from the API body
  #            ({"error" => {"code" => ..., "message" => ...}}) when present.
  #   body   - the parsed response body (Hash) when the response was JSON,
  #            otherwise the raw response text, or nil.
  class APIError < Error
    attr_reader :status, :code, :body

    def initialize(message, status: nil, code: nil, body: nil)
      super(message)
      @status = status
      @code = code
      @body = body
    end
  end

  # 401 - missing or invalid API key.
  class AuthenticationError < APIError; end

  # 403 - the API key lacks the required scope.
  class PermissionDeniedError < APIError; end

  # 404 - the requested resource does not exist.
  class NotFoundError < APIError; end

  # 400 / 422 - the request was malformed or failed validation.
  class ValidationError < APIError; end

  # 429 - rate limit exceeded (100 requests per minute).
  #
  # #retry_after is the number of seconds to wait before retrying, taken from
  # the Retry-After header (or the body's retry_after field) when present.
  class RateLimitError < APIError
    attr_reader :retry_after

    def initialize(message, status: 429, code: nil, body: nil, retry_after: nil)
      super(message, status: status, code: code, body: body)
      @retry_after = retry_after
    end
  end

  # >= 500 - something went wrong on OmniSocials' side.
  class ServerError < APIError; end

  # The request never got a response (network failure or timeout).
  class APIConnectionError < Error
    def initialize(message = "Connection error.")
      super
    end
  end

  # Webhook signature verification failed.
  class WebhookVerificationError < Error; end
end
