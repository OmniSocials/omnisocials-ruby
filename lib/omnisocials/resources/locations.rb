# frozen_string_literal: true

module OmniSocials
  module Resources
    # Locations resource: Instagram and Threads place tagging (search +
    # validate).
    class Locations
      def initialize(client)
        @client = client
      end

      # GET /locations/search - search locations for place tagging.
      #
      # platform is "instagram" (default) or "threads". The two sources use
      # DIFFERENT ids: a Facebook Place ID is not a Threads location id.
      #
      # Instagram: pass q to search Facebook place pages usable as an
      # Instagram location_id. Response: { "data" => [...] } plus optional
      # "error" (a plain string on the degraded path) and "needsPermission".
      #
      # Threads: pass q, OR latitude (-90..90) plus longitude (-180..180) to
      # search around a point instead of q. Response:
      # { "locations" => [{ id, name, address, city, country, latitude,
      # longitude }] } (all fields but id nullable), or
      # { "error" => { "code", "message" } } where code is one of
      # "not_available" (Threads location tagging not enabled in this
      # environment yet), "threads_not_connected", "threads_reauth_required"
      # (the connection lacks the threads_location_tagging permission;
      # reconnect Threads), or "platform_error". Validation problems (neither
      # q nor lat+lng, q under 2 chars, coordinates out of range) raise a 400
      # with the standard error envelope. Pass a result's id as
      # threads.location_id on post create/update.
      #
      # Threads location tagging is currently rolling out: until Meta
      # approves the permissions it is disabled on production and calls
      # return a clear error.
      def search(q = nil, platform: nil, latitude: nil, longitude: nil)
        @client.request(
          "GET", "/locations/search",
          query: {
            "q" => q,
            "platform" => platform,
            "latitude" => latitude,
            "longitude" => longitude
          }
        )
      end

      # GET /locations/validate?id= - validate a location id before attaching
      # it to a post.
      def validate(id)
        @client.request("GET", "/locations/validate", query: { "id" => id })
      end
    end
  end
end
