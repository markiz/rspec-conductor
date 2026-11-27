# frozen_string_literal: true

require "spec_helper"

describe RSpec::Conductor::Util::StringUtils do
  describe "#convert_to_safe_utf8" do
    [
      [nil, nil],
      ["valid utf-8 string", "valid utf-8 string"],
      ["invalid \xFFutf-8 string", "invalid �utf-8 string"],
      ["caf\xE9".b.force_encoding(Encoding::ISO_8859_1), "café"],
      ["valid utf-8 string encoded as binary: résumé".b, "valid utf-8 string encoded as binary: résumé"],
      ["invalid \xFFutf-8 string encoded as binary".b, "invalid �utf-8 string encoded as binary"],
      [:symbol, :symbol],
      [:"utf-8 symbol é", :"utf-8 symbol é"],
      [{ "some \xFFutf-8 key" => "some \xFFutf-8 value" }, { "some �utf-8 key" => "some �utf-8 value" }],
      [["boom\xFF", 1, 2, 3, { "boom v2 \xFF" => 4 }], ["boom�", 1, 2, 3, { "boom v2 �" => 4 }]]
    ].each do |input, output|
      it "properly handles #{input.inspect}" do
        expect(described_class.convert_to_safe_utf8(input)).to eq(output)
      end
    end
  end
end
