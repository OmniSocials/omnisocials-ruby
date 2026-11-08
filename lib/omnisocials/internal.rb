# frozen_string_literal: true

require "cgi"
require "json"
require "pathname"

module OmniSocials
  # Sentinel distinguishing "omitted" from an explicit nil.
  #
  # A few endpoints treat null as meaningful (for example
  # media.update(folder_id: nil) moves a file to the root folder), so nil
  # cannot double as "not provided" there. Use OmniSocials::NOT_GIVEN as the
  # default for those parameters.
  class NotGiven
    def inspect
      "NOT_GIVEN"
    end
    alias to_s inspect
  end

  NOT_GIVEN = NotGiven.new.freeze

  # Internal helpers shared by the client core and the resource classes.
  # Not part of the public API.
  module Internal
    MAX_BACKOFF_SECONDS = 8.0

    class << self
      # Drop nil and NOT_GIVEN values (top level only).
      #
      # Nested values are passed through untouched, so platform option hashes
      # can still carry meaningful nils (e.g. x: { "thread_parts" => nil } on
      # update clears an X thread).
      def drop_nil(hash)
        hash.reject { |_key, value| value.nil? || value.is_a?(NotGiven) }
      end

      # URL-encode a caller-supplied id as exactly one path segment. "/", "?",
      # "#" and "%" are encoded too, so an id cannot add a segment, start a
      # query or a fragment, or carry an escape of its own (an id such as
      # "../webhooks/wh_1/rotate-secret#" would otherwise move the call to
      # another endpoint of the same API key). Spaces become %20 (a path
      # segment treats "+" literally, unlike a query string). Every id that
      # goes into a request path goes through this method.
      def path_segment(value)
        CGI.escape(value.to_s).gsub("+", "%20")
      end

      # Refuse a request path with an empty, "." or ".." segment.
      # path_segment leaves "." and ".." as they are, and URL normalization
      # drops such a segment or climbs one level, so an id of ".." would reach
      # another endpoint; an empty id would reach the list route. Raises
      # ArgumentError before anything is sent.
      def check_path(path)
        segments = path.to_s.split("?", 2).first.to_s.split("/", -1).drop(1)
        if segments.any? { |segment| segment.empty? || segment == "." || segment == ".." }
          raise ArgumentError, "Invalid request path #{path.inspect}: an id cannot be empty, \".\" or \"..\"."
        end

        path
      end

      # Join an array into a comma-separated string; pass strings through.
      def join_list(value)
        return nil if value.nil?
        return value if value.is_a?(String)

        value.map(&:to_s).join(",")
      end

      # Stringify query params, dropping nil/NOT_GIVEN values.
      def serialize_query(params)
        return nil if params.nil? || params.empty?

        out = {}
        params.each do |key, value|
          next if value.nil? || value.is_a?(NotGiven)

          out[key.to_s] =
            case value
            when true then "true"
            when false then "false"
            else value.to_s
            end
        end
        out.empty? ? nil : out
      end

      # Parse a response body as JSON, falling back to the raw text.
      def parse_body(raw)
        return nil if raw.nil? || raw.empty?

        begin
          JSON.parse(raw)
        rescue JSON::ParserError
          raw
        end
      end

      # Delay before retry number +attempt+ (0-based): 0.5s, 1s, 2s... + jitter.
      #
      # An explicit Retry-After from the server wins over the computed backoff.
      def backoff_delay(attempt, retry_after)
        return [retry_after, 60.0].min unless retry_after.nil?

        delay = [0.5 * (2**attempt), MAX_BACKOFF_SECONDS].min
        delay * (0.75 + rand * 0.5)
      end

      # Normalize the +file+ argument to [filename, binary_data].
      #
      # Accepts:
      # - an IO / File / StringIO (anything responding to #read)
      # - a file path (a String or Pathname)
      # - raw bytes (a binary-encoded String, e.g. from File.binread)
      #
      # The content is read fully into memory so automatic retries can resend it.
      def coerce_file(file, filename)
        case file
        when Pathname
          path = file.to_s
          return [filename || File.basename(path), File.binread(path)]
        when String
          # A binary-encoded String is treated as raw bytes; any other String
          # is treated as a file path (mirrors the Python SDK where str = path).
          return [filename || "upload", file] if file.encoding == Encoding::BINARY

          return [filename || File.basename(file), File.binread(file)]
        end

        if file.respond_to?(:read)
          data = file.read.to_s.b
          inferred = file.respond_to?(:path) ? file.path : nil
          resolved = filename
          resolved ||= File.basename(inferred) if inferred.is_a?(String) && !inferred.empty?
          return [resolved || "upload", data]
        end

        raise ArgumentError,
              "file must be an IO, a file path (String or Pathname), or raw bytes " \
              "(a binary-encoded String, e.g. from File.binread); got #{file.class}."
      end

      # Build a multipart/form-data body (single file part named "file" plus
      # optional plain form fields), hand-rolled so the SDK stays dependency-free.
      def multipart_body(boundary, fields, filename, data)
        body = String.new(encoding: Encoding::BINARY)
        fields.each do |name, value|
          body << "--#{boundary}\r\n".b
          body << "Content-Disposition: form-data; name=\"#{name}\"\r\n\r\n".b
          body << value.to_s.b
          body << "\r\n".b
        end
        safe_name = filename.to_s.gsub('"', "%22").gsub(/[\r\n]/, " ")
        body << "--#{boundary}\r\n".b
        body << "Content-Disposition: form-data; name=\"file\"; filename=\"#{safe_name}\"\r\n".b
        body << "Content-Type: application/octet-stream\r\n\r\n".b
        body << data.to_s.b
        body << "\r\n--#{boundary}--\r\n".b
        body
      end
    end
  end
end
