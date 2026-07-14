# frozen_string_literal: true

require "json"
require "openssl"

module OmniSocials
  # Webhook signature verification.
  #
  # OmniSocials signs every webhook delivery with HMAC-SHA256 (Stripe-style):
  #
  # - Header: X-OmniSocials-Signature: t=<unix>,v1=<hex>
  # - Signed value: "{timestamp}.{raw_body}" (UTF-8), keyed with the
  #   webhook's secret, hex digest.
  module Webhooks
    class << self
      # Verify an OmniSocials webhook delivery and return the parsed event.
      #
      # payload   - the raw request body String, exactly as received. Do not
      #             parse and re-serialize it first; the signature is over the
      #             raw bytes.
      # signature - the X-OmniSocials-Signature header value, of the form
      #             t=<unix>,v1=<hex>.
      # secret    - the webhook's signing secret (returned once when the
      #             webhook is created, or via rotate_secret).
      # tolerance - maximum allowed age (and future skew) of the signed
      #             timestamp, in seconds. Defaults to 300. Pass nil to skip
      #             the timestamp check (not recommended).
      #
      # Returns the parsed event as a Hash (string keys).
      #
      # Raises OmniSocials::WebhookVerificationError if the header is
      # malformed, the timestamp is outside the tolerance window, or the
      # signature does not match. Uses a constant-time comparison.
      def verify(payload:, signature:, secret:, tolerance: 300)
        unless payload.is_a?(String)
          raise WebhookVerificationError,
                "payload must be a String (the raw request body), got #{payload.class}."
        end
        unless signature.is_a?(String) && !signature.empty?
          raise WebhookVerificationError, "Missing signature header."
        end

        timestamp = nil
        candidates = []
        signature.split(",").each do |pair|
          key, _, value = pair.strip.partition("=")
          case key
          when "t"
            begin
              timestamp = Integer(value, 10)
            rescue ArgumentError, TypeError
              raise WebhookVerificationError,
                    "Malformed signature header: non-integer timestamp."
            end
          when "v1"
            candidates << value
          end
        end

        if timestamp.nil?
          raise WebhookVerificationError,
                "Malformed signature header: missing 't=' timestamp."
        end
        if candidates.empty?
          raise WebhookVerificationError,
                "Malformed signature header: missing 'v1=' signature."
        end

        unless tolerance.nil?
          drift = (Time.now.to_i - timestamp).abs
          if drift > tolerance
            raise WebhookVerificationError,
                  "Timestamp outside the tolerance window (#{drift}s > #{tolerance}s). " \
                  "The delivery may be stale or replayed."
          end
        end

        signed_value = "#{timestamp}.".b + payload.b
        expected = OpenSSL::HMAC.hexdigest("SHA256", secret, signed_value)

        unless candidates.any? { |candidate| secure_compare(expected, candidate) }
          raise WebhookVerificationError,
                "Signature mismatch: the payload was not signed with this secret, " \
                "or the body was modified in transit."
        end

        begin
          event = JSON.parse(payload)
        rescue JSON::ParserError
          raise WebhookVerificationError, "Payload is not valid JSON."
        end
        unless event.is_a?(Hash)
          raise WebhookVerificationError, "Payload is not a JSON object."
        end
        event
      end

      private

      # Constant-time string comparison.
      def secure_compare(expected, candidate)
        return false unless candidate.is_a?(String)

        if OpenSSL.respond_to?(:secure_compare)
          OpenSSL.secure_compare(expected, candidate)
        else
          expected.bytesize == candidate.bytesize &&
            OpenSSL.fixed_length_secure_compare(expected, candidate)
        end
      end
    end
  end
end
