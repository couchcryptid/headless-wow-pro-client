local enc = require("hwc.questie.encoding")
local function hex(h) return (h:gsub("%x%x", function(c) return string.char(tonumber(c, 16)) end)) end

describe("base64", function()
  it("decodes padded and unpadded tails", function()
    assert.are.equal("foobar", enc.decode_base64("Zm9vYmFy"))
    assert.are.equal("fo", enc.decode_base64("Zm8="))
    assert.are.equal("f", enc.decode_base64("Zg=="))
  end)
  it("rejects characters outside the alphabet", function()
    assert.has_error(function() enc.decode_base64("Zm9v!") end, "hwc: base64: invalid input")
  end)
end)

describe("decompress", function()
  local LD = require("hwc.vendor.LibDeflate")
  it("inflates zlib (1) and raw deflate (0)", function()
    assert.are.equal("hello hello hello", enc.decompress(LD:CompressZlib("hello hello hello"), 1))
    assert.are.equal("hello hello hello", enc.decompress(LD:CompressDeflate("hello hello hello"), 0))
  end)
  it("rejects trailing garbage like the client", function()
    assert.has_error(function() enc.decompress(LD:CompressZlib("x") .. "junk", 1) end,
      "C_EncodingUtil.DecompressString: invalid compressed data")
  end)
  it("rejects unknown methods", function()
    assert.has_error(function() enc.decompress("x", 2) end,
      "C_EncodingUtil.DecompressString: unsupported compression method 2")
  end)
end)

describe("c_encoding_util", function()
  it("exposes plain functions with the WoW signatures", function()
    local C = enc.c_encoding_util()
    assert.are.equal("f", C.DecodeBase64("Zg=="))
    assert.are.equal(1000, C.DeserializeCBOR(hex("1903e8")))
    local LD = require("hwc.vendor.LibDeflate")
    assert.are.equal("abc", C.DecompressString(LD:CompressZlib("abc"), 1))
  end)
end)

-- RFC 8949 Appendix A vectors
describe("cbor", function()
  local cases = {
    { "00", 0 }, { "17", 23 }, { "1818", 24 }, { "1903e8", 1000 }, { "1a000f4240", 1000000 },
    { "1b000000e8d4a51000", 1000000000000 }, { "20", -1 }, { "3903e7", -1000 },
    { "f93c00", 1.0 }, { "fa47c35000", 100000.0 }, { "fb3ff199999999999a", 1.1 },
    { "f4", false }, { "f5", true }, { "6449455446", "IETF" }, { "4401020304", "\1\2\3\4" },
  }
  for _, c in ipairs(cases) do
    it("decodes " .. c[1], function() assert.are.equal(c[2], enc.deserialize_cbor(hex(c[1]))) end)
  end
  it("decodes half floats (subnormal, negative, infinity)", function()
    assert.are.equal(5.960464477539063e-08, enc.deserialize_cbor(hex("f90001")))
    assert.are.equal(-4.0, enc.deserialize_cbor(hex("f9c400")))
    assert.are.equal(math.huge, enc.deserialize_cbor(hex("f97c00")))
    assert.are.equal(-math.huge, enc.deserialize_cbor(hex("f9fc00")))
  end)
  it("decodes null as nil, arrays 1-based with holes, and maps", function()
    assert.is_nil(enc.deserialize_cbor(hex("f6")))
    assert.are.same({ 1, { 2, 3 }, { 4, 5 } }, enc.deserialize_cbor(hex("8301820203820405")))
    local t = enc.deserialize_cbor(hex("8301f603"))
    assert.are.equal(1, t[1]); assert.is_nil(t[2]); assert.are.equal(3, t[3])
    assert.are.same({ a = 1, b = { 2, 3 } }, enc.deserialize_cbor(hex("a26161016162820203")))
    assert.are.same({ [1] = "x", [7] = "y" }, enc.deserialize_cbor(hex("a2016178076179")))
  end)
  it("decodes indefinite-length strings, arrays and maps", function()
    assert.are.same({ 1, 2 }, enc.deserialize_cbor(hex("9f0102ff")))
    assert.are.same({ a = 1 }, enc.deserialize_cbor(hex("bf616101ff")))
    assert.are.equal("streaming", enc.deserialize_cbor(hex("7f657374726561646d696e67ff")))
  end)
  it("unwraps tags", function()
    assert.are.equal(1363896240, enc.deserialize_cbor(hex("c11a514b67b0")))
  end)
  it("rejects trailing data and truncated input", function()
    assert.has_error(function() enc.deserialize_cbor(hex("0000")) end, "hwc: cbor: trailing data")
    assert.has_error(function() enc.deserialize_cbor(hex("1903")) end, "hwc: cbor: unexpected end of data")
  end)
end)
