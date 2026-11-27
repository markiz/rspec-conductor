# frozen_string_literal: true

require "json"

module RSpec
  module Conductor
    module Protocol
      class Socket
        attr_reader :io

        def initialize(io)
          @io = io
        end

        def send_message(message)
          json = JSON.generate(encode_utf8(message))
          length = [json.bytesize].pack("N")
          io.write(length)
          io.write(json.b)
          io.flush
        rescue Errno::EPIPE, IOError
          nil
        end

        def receive_message
          length_bytes = io.read(4)
          return nil unless length_bytes&.bytesize == 4

          length = length_bytes.unpack1("N")
          json = io.read(length)
          return nil unless json&.bytesize == length

          JSON.parse(json, symbolize_names: true)
        rescue Errno::ECONNRESET, IOError, JSON::ParserError
          nil
        end

        def close
          io.close unless io.closed?
        end

        private

        # recursively encode any strings to a safe subset of utf-8
        def encode_utf8(object)
          case object
          when Hash
            object.transform_values { |value| encode_utf8(value) }
          when Array
            object.map { |value| encode_utf8(value) }
          when String
            if object.encoding == Encoding::UTF_8
              object.valid_encoding? ? object : object.scrub
            elsif object.encoding == Encoding::BINARY # try to preserve any valid utf8 strings read as binary for whatever reason
              object.dup.force_encoding(Encoding::UTF_8).tap(&:scrub!)
            else
              object.encode(Encoding::UTF_8, invalid: :replace, undef: :replace)
            end
          when Symbol
            encode_utf8(object.to_s).to_sym
          else
            object
          end
        end
      end
    end
  end
end
