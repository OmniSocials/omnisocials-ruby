# frozen_string_literal: true

module OmniSocials
  module Resources
    # Locations resource: Instagram place tagging (search + validate).
    class Locations
      def initialize(client)
        @client = client
      end

      # GET /locations/search?q= - search Facebook place pages usable as an
      # Instagram location_id.
      def search(q)
        @client.request("GET", "/locations/search", query: { "q" => q })
      end

      # GET /locations/validate?id= - validate a location id before attaching
      # it to a post.
      def validate(id)
        @client.request("GET", "/locations/validate", query: { "id" => id })
      end
    end
  end
end
