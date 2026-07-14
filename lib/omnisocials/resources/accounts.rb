# frozen_string_literal: true

module OmniSocials
  module Resources
    # Accounts resource: connected social accounts for the API key's workspace.
    class Accounts
      def initialize(client)
        @client = client
      end

      # GET /accounts - list connected social accounts.
      #
      # The response also carries workspace_id and workspace_name for the
      # workspace the API key belongs to.
      def list
        @client.request("GET", "/accounts")
      end

      # GET /accounts/{id} - fetch a single connected account.
      def get(account_id)
        @client.request("GET", "/accounts/#{account_id}")
      end
    end
  end
end
