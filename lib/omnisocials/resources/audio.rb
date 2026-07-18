# frozen_string_literal: true

module OmniSocials
  module Resources
    # Audio resource: Instagram Reels audio (Meta's licensed catalog).
    class Audio
      def initialize(client)
        @client = client
      end

      # GET /audio/search?q=&type= - search Meta's licensed audio catalog for
      # Instagram Reels. Omit query for trending audio; type is "music"
      # (default) or "original_sound". Use a result's audio_id as
      # instagram.audio_id on a reel post (with optional
      # instagram.audio_volume / instagram.video_volume, integers 0-100).
      # preview_url is a temporary URL (~1.5 days); never persist it.
      def search(query: nil, type: nil)
        @client.request("GET", "/audio/search", query: { "q" => query, "type" => type })
      end
    end
  end
end
