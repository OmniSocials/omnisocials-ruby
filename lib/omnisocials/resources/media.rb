# frozen_string_literal: true

module OmniSocials
  module Resources
    # Media resource: upload, list, check, rename/move, and delete library files.
    class Media
      def initialize(client)
        @client = client
      end

      # GET /media - list library files.
      def list(limit: nil, offset: nil, search: nil, folder_id: nil)
        @client.request(
          "GET", "/media",
          query: {
            "limit" => limit,
            "offset" => offset,
            "search" => search,
            "folder_id" => folder_id
          }
        )
      end

      # GET /media/{id} - fetch a single library file.
      def get(media_id)
        @client.request("GET", "/media/#{media_id}")
      end

      # POST /media/upload - multipart upload (max 100MB inline).
      #
      # `file` is an IO, a file path (String or Pathname), or raw bytes (a
      # binary-encoded String, e.g. from File.binread).
      #
      # A PDF is split into image slides and the response carries `slides`
      # plus a `media_ids` array instead of a single `data` item. For files
      # over 100MB use upload_from_url (up to 1GB) or the create_upload_url
      # presigned flow.
      def upload(file:, filename: nil, name: nil, folder: nil, folder_id: nil)
        upload_name, data = Internal.coerce_file(file, filename)
        fields = Internal.drop_nil(
          { "name" => name, "folder" => folder, "folder_id" => folder_id }
        )
        @client.request(
          "POST", "/media/upload",
          multipart: { fields: fields, filename: upload_name, data: data }
        )
      end

      # POST /media/upload-from-url - server-side fetch, up to 1GB.
      #
      # Files over 100MB are streamed in the background: the response has
      # data["status"] == "processing"; poll get() until it is "ready".
      def upload_from_url(url:, filename: nil, name: nil, folder: nil, folder_id: nil)
        body = Internal.drop_nil(
          {
            "url" => url,
            "filename" => filename,
            "name" => name,
            "folder" => folder,
            "folder_id" => folder_id
          }
        )
        @client.request("POST", "/media/upload-from-url", json: body)
      end

      # POST /media/upload-from-base64 - upload base64-encoded data (without
      # a data URI prefix).
      def upload_from_base64(data:, mime_type:, filename: nil, name: nil,
                             folder: nil, folder_id: nil)
        body = Internal.drop_nil(
          {
            "data" => data,
            "mime_type" => mime_type,
            "filename" => filename,
            "name" => name,
            "folder" => folder,
            "folder_id" => folder_id
          }
        )
        @client.request("POST", "/media/upload-from-base64", json: body)
      end

      # POST /media/create-upload-url - mint a one-time presigned URL.
      #
      # Returns {"upload_url", "upload_token", "expires_in_seconds", ...}.
      # POST the file to upload_url as multipart form data (field name "file")
      # with NO auth headers; the token in the URL authenticates the single
      # upload and expires after 10 minutes.
      def create_upload_url
        @client.request("POST", "/media/create-upload-url")
      end

      # POST /media/check - preflight platform compatibility.
      #
      # Provide one of: a public `url`, an existing `media_id`, or
      # `size_bytes` + `mime`.
      def check(url: nil, media_id: nil, size_bytes: nil, mime: nil)
        body = Internal.drop_nil(
          {
            "url" => url,
            "media_id" => media_id,
            "size_bytes" => size_bytes,
            "mime" => mime
          }
        )
        @client.request("POST", "/media/check", json: body)
      end

      # PATCH /media/{id} - rename and/or move a file.
      #
      # Pass folder_id: nil explicitly to move the file to the root
      # ("All media"); omit it to leave the folder unchanged.
      def update(media_id, name: nil, folder_id: OmniSocials::NOT_GIVEN)
        body = Internal.drop_nil({ "name" => name })
        body["folder_id"] = folder_id unless folder_id.is_a?(NotGiven)
        @client.request("PATCH", "/media/#{media_id}", json: body)
      end

      # DELETE /media/{id} - delete a file. Returns nil (204).
      #
      # Fails with 409 media_in_use if the file is attached to a scheduled or
      # publishing post.
      def delete(media_id)
        @client.request("DELETE", "/media/#{media_id}")
      end
    end
  end
end
