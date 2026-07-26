# frozen_string_literal: true

module OmniSocials
  module Resources
    # Hashtag sets resource: saved, reusable hashtag groups applied to posts
    # at create time (via hashtag_set / hashtag_set_id on posts.create).
    class HashtagSets
      def initialize(client)
        @client = client
      end

      # GET /hashtag-sets - list the workspace's saved hashtag sets.
      def list
        @client.request("GET", "/hashtag-sets")
      end

      # GET /hashtag-sets/{id} - fetch a single hashtag set.
      def get(hashtag_set_id)
        @client.request("GET", "/hashtag-sets/#{hashtag_set_id}")
      end

      # POST /hashtag-sets - create a hashtag set.
      #
      # `hashtags` is an Array of tags, or a single String of tags. Apply the
      # set on posts.create via hashtag_set (name, case-insensitive) or
      # hashtag_set_id.
      def create(name:, hashtags:)
        @client.request(
          "POST", "/hashtag-sets",
          json: { "name" => name, "hashtags" => hashtags }
        )
      end

      # PATCH /hashtag-sets/{id} - rename and/or replace the tags.
      #
      # `hashtags` replaces the FULL list.
      def update(hashtag_set_id, name: nil, hashtags: nil)
        body = Internal.drop_nil({ "name" => name, "hashtags" => hashtags })
        @client.request("PATCH", "/hashtag-sets/#{hashtag_set_id}", json: body)
      end

      # DELETE /hashtag-sets/{id} - delete a hashtag set. Returns nil (204).
      def delete(hashtag_set_id)
        @client.request("DELETE", "/hashtag-sets/#{hashtag_set_id}")
      end
    end
  end
end
