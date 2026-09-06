# frozen_string_literal: true

module OmniSocials
  module Resources
    # Approval workflows resource: the workflows configured in the dashboard
    # (Approvals). List them here and route a post through one at create time
    # via approval_workflow_id on posts.create.
    class ApprovalWorkflows
      def initialize(client)
        @client = client
      end

      # GET /approval-workflows - the workflows this workspace can use
      # (company-wide plus workspace-bound), with steps and named approvers.
      def list
        @client.request("GET", "/approval-workflows")
      end
    end
  end
end
