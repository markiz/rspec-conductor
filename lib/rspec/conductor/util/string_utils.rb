# frozen_string_literal: true

module RSpec
  module Conductor
    module Util
      module StringUtils
        module_function

        # recursively encode any strings (including keys/values/array items) to a safe subset of utf-8
        def convert_to_safe_utf8(object)
          case object
          when Hash
            object.transform_keys { |key| convert_to_safe_utf8(key) }.transform_values { |value| convert_to_safe_utf8(value) }
          when Array
            object.map { |value| convert_to_safe_utf8(value) }
          when String
            if object.encoding == Encoding::UTF_8
              object.valid_encoding? ? object : object.scrub
            elsif object.encoding == Encoding::BINARY # try to preserve any valid utf8 strings read as binary for whatever reason
              object.dup.force_encoding(Encoding::UTF_8).tap(&:scrub!)
            else
              object.encode(Encoding::UTF_8, invalid: :replace, undef: :replace)
            end
          when Symbol
            convert_to_safe_utf8(object.to_s).to_sym
          else
            object
          end
        end
      end
    end
  end
end
