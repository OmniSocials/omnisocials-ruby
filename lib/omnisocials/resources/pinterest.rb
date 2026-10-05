# frozen_string_literal: true

module OmniSocials
  module Resources
    # Pinterest resource: product Pins for product tagging (list + validate).
    class Pinterest
      def initialize(client)
        @client = client
      end

      # GET /pinterest/products - list the product Pins of the connected
      # Pinterest account. Pass a result's pin_id in
      # pinterest: { "product_tags" => [...] } on post create/update to tag
      # the product on the Pin (max 24 per Pin). Pinterest only accepts a
      # product Pin that is public, belongs to the same account and links to
      # a website that account claimed; products of other merchants cannot
      # be tagged.
      #
      # source is "catalog" or "pins". "catalog" reads the Pinterest catalog
      # (with price, currency, availability, item_id) and needs catalog
      # access, which is given one time in the OmniSocials composer
      # (Pinterest options, Add products, Connect catalog); product_group_id
      # and page_size (1..100, default 25) apply to this source only. "pins"
      # reads the account's own Pins and works on every connection; one call
      # scans up to 250 Pins, so "products" can be empty while "bookmark" is
      # set (call again with bookmark:). When source is left out the API
      # uses "catalog" when the connection has catalog access, else "pins".
      #
      # Response (not the usual "data" envelope):
      # { "products" => [{ pin_id, title, description, link, image_url,
      # price, currency, availability, item_id }], "bookmark", "source",
      # "catalog_access" } plus "product_groups" and "product_group_id" for
      # the catalog source, or { "error" => { "code", "message" } } without
      # "products" when the list could not be read, both with HTTP 200. code
      # is one of "pinterest_not_connected",
      # "pinterest_catalog_access_required" or "platform_error". A bad source
      # or product_group_id raises a 400 with the standard error envelope.
      def list_products(source: nil, product_group_id: nil, bookmark: nil,
                        page_size: nil)
        @client.request(
          "GET", "/pinterest/products",
          query: {
            "source" => source,
            "product_group_id" => product_group_id,
            "bookmark" => bookmark,
            "page_size" => page_size
          }
        )
      end

      # GET /pinterest/products/validate?id= - check whether a Pin can be
      # used in pinterest product_tags before creating the post. id is a Pin
      # id or a Pin link (https://www.pinterest.com/pin/<id>/). Response:
      # { "valid", "pin_id", ... }; "unverified" => true means the check
      # could not run and the publish step is the final check.
      def validate_product(id)
        @client.request("GET", "/pinterest/products/validate", query: { "id" => id })
      end
    end
  end
end
