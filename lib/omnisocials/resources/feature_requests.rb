# frozen_string_literal: true

module OmniSocials
  module Resources
    # Feature requests resource: requests to the OmniSocials team, for the
    # person who owns the key (their name and email are stored with it so
    # the team can answer). The person sees them in OmniSocials (Settings,
    # Request a feature) and gets an email when the status changes. No scope
    # needed.
    #
    # A request is { "id", "title", "summary", "status" (open, in_progress,
    # completed, declined), "team_answer", "team_replies" => [{ "message",
    # "created_at" }], "votes_count", "limit_id", "platform", "area",
    # "source", "created_at", "updated_at", "completed_at" }.
    class FeatureRequests
      def initialize(client)
        @client = client
      end

      # POST /feature-requests - send a request. Send it only when the
      # person asked for it.
      #
      # summary: (10 to 1000 characters) says what the person wants to do
      # and why; title: (at most 120) is made from it when left out.
      # limit_id: is the "id" of the limits.list entry the request is about.
      # Returns { "outcome", "data" }: "outcome" is "created" (a new
      # request), "voted" (a vote added to the organisation's open request
      # for the same gap) or "already_requested" (this person already has an
      # open request for it; "data" is that request).
      #
      # Errors: 400 invalid_summary / invalid_title / invalid_platform /
      # invalid_area / unknown_limit; 409 not_requestable (a platform rule or
      # a choice of OmniSocials: the entry is in error.body["error"]["limit"],
      # nothing was stored); 429 too_many_requests (10 an hour per person).
      def create(summary:, title: nil, platform: nil, area: nil, limit_id: nil)
        body = Internal.drop_nil(
          {
            "summary" => summary,
            "title" => title,
            "platform" => platform,
            "area" => area,
            "limit_id" => limit_id
          }
        )
        @client.request("POST", "/feature-requests", json: body)
      end

      # GET /feature-requests - the person's own requests, newest first, at
      # most 50: { "data" => [FeatureRequest] }.
      def list
        @client.request("GET", "/feature-requests")
      end

      # GET /feature-requests/{id} - one request with its status and the
      # team's replies. Errors: 400 invalid_id, 404 not_found.
      def get(request_id)
        @client.request("GET", "/feature-requests/#{Internal.path_segment(request_id)}")
      end
    end
  end
end
