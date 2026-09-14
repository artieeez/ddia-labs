# Ruby 4.0.5 ships json 2.1.0, which accepts options on JSON.parse only as
# keyword arguments. Rails 8.1 still calls JSON.parse(source, options) with a
# positional hash (ActionDispatch JSON parameter parsing and
# ActiveSupport::JSON.decode). Bridge the two signatures so raw JSON request
# bodies keep parsing. Remove once Rails supports the keyword-only form.
require "json"

module JsonRubyCompat
  module ParseWithKeywordOptions
    def parse(source, options = nil, **keywords)
      opts = keywords.empty? ? options : (options || {}).merge(keywords)
      super(source, **opts)
    end
  end
end

JSON.singleton_class.prepend(JsonRubyCompat::ParseWithKeywordOptions)
