# frozen_string_literal: true

module OmniSocials
  module Resources
    # Folders resource: organize media library files into folders.
    class Folders
      def initialize(client)
        @client = client
      end

      # GET /folders - list media folders (with per-folder file counts).
      def list
        @client.request("GET", "/folders")
      end

      # POST /folders - create a folder (optionally nested under parent_id).
      def create(name:, parent_id: nil)
        body = Internal.drop_nil({ "name" => name, "parent_id" => parent_id })
        @client.request("POST", "/folders", json: body)
      end

      # PATCH /folders/{id} - rename and/or move a folder.
      #
      # Pass parent_id: nil explicitly to move the folder to the top level;
      # omit it to leave the parent unchanged.
      def update(folder_id, name: nil, parent_id: OmniSocials::NOT_GIVEN)
        body = Internal.drop_nil({ "name" => name })
        body["parent_id"] = parent_id unless parent_id.is_a?(NotGiven)
        @client.request("PATCH", "/folders/#{folder_id}", json: body)
      end

      # DELETE /folders/{id} - delete a folder. Returns nil (204).
      #
      # The folder's media is NOT deleted: files move to the root and
      # subfolders move up to the deleted folder's parent.
      def delete(folder_id)
        @client.request("DELETE", "/folders/#{folder_id}")
      end
    end
  end
end
