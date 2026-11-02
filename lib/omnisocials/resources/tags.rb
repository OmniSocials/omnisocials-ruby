# frozen_string_literal: true

module OmniSocials
  module Resources
    # Tags resource: the workspace's own labels for its posts (a hook style,
    # a format), to filter and compare posts in Analytics. Tags never go to a
    # platform.
    #
    # Set them on a post with tags: on posts.create / create_and_publish /
    # update, in bulk with #apply, filter with tag: on posts.list and
    # analytics.overview, and compare them with analytics.tags. A tag
    # reference is a tag id (Integer or String) or a tag name
    # (case-insensitive); in add / set (and tags: on posts) a name that does
    # not exist yet becomes a new tag.
    class Tags
      # Serialize the tag filter: one id or name, or an Array joined with ",".
      def self.tag_query(tag)
        return nil if tag.nil?
        return tag.map(&:to_s).join(",") if tag.is_a?(Array)

        tag.to_s
      end

      def initialize(client)
        @client = client
      end

      # GET /tags - every tag of the workspace, by name. Each tag is
      # { "id", "name", "color", "created_at" }. Scope posts:read.
      def list
        @client.request("GET", "/tags")
      end

      # POST /tags - create a tag. `name` is at most 40 characters and unique
      # in the workspace (case-insensitive); `color` is one of blue, green,
      # orange, red, purple, pink, teal, yellow, brown, gray (omit it to get
      # the next colour). At most 200 tags per workspace.
      #
      # Errors: 409 tag_exists (the existing tag is in
      # error.body["error"]["tag"]), 409 tag_limit_reached,
      # 400 invalid_tag_name / invalid_tag_color.
      def create(name:, color: nil)
        @client.request(
          "POST", "/tags",
          json: Internal.drop_nil({ "name" => name, "color" => color })
        )
      end

      # PATCH /tags/{id} - rename or recolour a tag. Only the keys you pass
      # are sent; posts keep the tag. Errors: 404 tag_not_found,
      # 409 tag_exists.
      def update(tag_id, name: nil, color: nil)
        body = Internal.drop_nil({ "name" => name, "color" => color })
        @client.request("PATCH", "/tags/#{tag_id}", json: body)
      end

      # DELETE /tags/{id} - delete a tag and take it off every post (the
      # posts stay). Returns { "data" => { "tag", "posts_untagged" } }.
      def delete(tag_id)
        @client.request("DELETE", "/tags/#{tag_id}")
      end

      # POST /tags/apply - add, remove or replace the tags of up to 500 posts
      # at once, published ones included.
      #
      # add, remove and set take tag ids or names; a new name in add or set
      # becomes a tag. set replaces a post's tags (set: [] removes them all),
      # add and remove change only the tags you name. Returns
      # { "data" => { "updated", "posts" => [{ "id", "tags" }], "not_found" } };
      # not_found lists the post ids that are not posts of this workspace.
      # Errors: 400 invalid_post_ids / too_many_posts / too_many_tags /
      # invalid_tags, 404 tag_not_found.
      def apply(post_ids:, add: nil, remove: nil, set: nil)
        body = Internal.drop_nil(
          {
            "post_ids" => Array(post_ids).map(&:to_s),
            "add" => add,
            "remove" => remove,
            "set" => set
          }
        )
        @client.request("POST", "/tags/apply", json: body)
      end
    end
  end
end
