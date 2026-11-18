-- Stand-ins for the parts of WoW's C_EncodingUtil that QuestieDB uses:
-- DecodeBase64 (RFC 4648), DecompressString (zlib / raw deflate) and
-- DeserializeCBOR (RFC 8949).
--
-- Inflate is delegated to the vendored LibDeflate 1.0.2-release
-- (zlib licence, kept verbatim next to it). Its sha256 is:
--   76f2114e527c2be1ac5cf768a68084946a3e19f63592834640020b7c9b5a450f
-- Base64 and CBOR are written here from the RFCs.
local bit = require("bit")
local LibDeflate = require("hwc.vendor.LibDeflate")

local M = {}

-- ---------------------------------------------------------------- base64

local B64_VALUE = {}
do
  local alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
  for i = 1, #alphabet do B64_VALUE[alphabet:byte(i)] = i - 1 end
end

local function base64_invalid() error("hwc: base64: invalid input", 0) end

-- Standard alphabet. '=' padding is optional, but when present it must close
-- the input and bring the length to a multiple of 4.
function M.decode_base64(s)
  local len = #s
  local pad = 0
  while pad < 2 and len > 0 and s:byte(len) == 61 do
    len = len - 1
    pad = pad + 1
  end
  if pad > 0 and (len + pad) % 4 ~= 0 then base64_invalid() end
  if len % 4 == 1 then base64_invalid() end

  local out, n = {}, 0
  local acc, bits = 0, 0
  for i = 1, len do
    local v = B64_VALUE[s:byte(i)]
    if v == nil then base64_invalid() end
    acc = acc * 64 + v
    bits = bits + 6
    if bits == 24 then
      n = n + 1
      out[n] = string.char(bit.rshift(acc, 16), bit.band(bit.rshift(acc, 8), 255), bit.band(acc, 255))
      acc, bits = 0, 0
    end
  end
  if bits == 12 then
    n = n + 1
    out[n] = string.char(bit.rshift(acc, 4))
  elseif bits == 18 then
    n = n + 1
    out[n] = string.char(bit.rshift(acc, 10), bit.band(bit.rshift(acc, 2), 255))
  end
  return table.concat(out)
end

-- --------------------------------------------------------------- inflate

-- method 0 = raw deflate, 1 = zlib. Like the client, trailing bytes after the
-- compressed stream are an error.
function M.decompress(data, method)
  local result, leftover
  if method == 0 then
    result, leftover = LibDeflate:DecompressDeflate(data)
  elseif method == 1 then
    result, leftover = LibDeflate:DecompressZlib(data)
  else
    error("C_EncodingUtil.DecompressString: unsupported compression method " .. tostring(method), 0)
  end
  if result == nil or leftover ~= 0 then
    error("C_EncodingUtil.DecompressString: invalid compressed data", 0)
  end
  return result
end

-- ------------------------------------------------------------------ cbor

local byte = string.byte

local function truncated() error("hwc: cbor: unexpected end of data", 0) end

-- Big-endian unsigned integer of `n` bytes at `pos`, as a double (exact to 2^53).
local function read_uint(s, pos, n)
  if pos + n - 1 > #s then truncated() end
  local v = 0
  for i = pos, pos + n - 1 do v = v * 256 + byte(s, i) end
  return v
end

-- RFC 8949 Appendix D.
local function half_to_number(h)
  local sign = (h >= 0x8000) and -1 or 1
  local exp = bit.band(bit.rshift(h, 10), 0x1f)
  local mant = bit.band(h, 0x3ff)
  local val
  if exp == 0 then
    val = mant * 2 ^ -24
  elseif exp ~= 31 then
    val = (mant + 1024) * 2 ^ (exp - 25)
  elseif mant == 0 then
    val = math.huge
  else
    val = 0 / 0
  end
  return sign * val
end

local function single_to_number(s, pos)
  local u = read_uint(s, pos, 4)
  local sign = (u >= 2 ^ 31) and -1 or 1
  local exp = bit.band(bit.rshift(u, 23), 0xff)
  local mant = u % 2 ^ 23
  local val
  if exp == 0 then
    val = mant * 2 ^ -149
  elseif exp ~= 255 then
    val = (mant + 2 ^ 23) * 2 ^ (exp - 150)
  elseif mant == 0 then
    val = math.huge
  else
    val = 0 / 0
  end
  return sign * val
end

local function double_to_number(s, pos)
  local hi = read_uint(s, pos, 4)
  local lo = read_uint(s, pos + 4, 4)
  local sign = (hi >= 2 ^ 31) and -1 or 1
  local exp = bit.band(bit.rshift(hi, 20), 0x7ff)
  local mant = (hi % 2 ^ 20) * 2 ^ 32 + lo
  local val
  if exp == 0 then
    val = mant * 2 ^ -1074
  elseif exp ~= 2047 then
    val = (mant + 2 ^ 52) * 2 ^ (exp - 1075)
  elseif mant == 0 then
    val = math.huge
  else
    val = 0 / 0
  end
  return sign * val
end

local BREAK = {} -- sentinel for the 0xff stop code

local decode_item

-- Reads the argument for additional info `ai` at `pos`.
-- Returns value (nil when indefinite), next position, indefinite flag.
local function read_argument(s, pos, ai)
  if ai < 24 then return ai, pos, false end
  if ai == 24 then return read_uint(s, pos, 1), pos + 1, false end
  if ai == 25 then return read_uint(s, pos, 2), pos + 2, false end
  if ai == 26 then return read_uint(s, pos, 4), pos + 4, false end
  if ai == 27 then return read_uint(s, pos, 8), pos + 8, false end
  if ai == 31 then return nil, pos, true end
  error("hwc: cbor: reserved additional info " .. ai, 0)
end

local function read_string(s, pos, len)
  if pos + len - 1 > #s then truncated() end
  return s:sub(pos, pos + len - 1), pos + len
end

local function decode_string(s, pos, major, len, indefinite)
  if not indefinite then return read_string(s, pos, len) end
  local chunks, n = {}, 0
  while true do
    if pos > #s then truncated() end
    local ib = byte(s, pos)
    if ib == 0xff then return table.concat(chunks), pos + 1 end
    if bit.rshift(ib, 5) ~= major then error("hwc: cbor: bad chunk in indefinite string", 0) end
    local clen, cpos, cindef = read_argument(s, pos + 1, bit.band(ib, 0x1f))
    if cindef then error("hwc: cbor: nested indefinite string", 0) end
    n = n + 1
    chunks[n], pos = read_string(s, cpos, clen)
  end
end

local function decode_array(s, pos, len, indefinite)
  local t = {}
  local i = 0
  while indefinite or i < len do
    local v
    v, pos = decode_item(s, pos, indefinite)
    if v == BREAK then return t, pos end
    i = i + 1
    t[i] = v -- nil leaves a hole, keeping later items at their index
  end
  return t, pos
end

local function decode_map(s, pos, len, indefinite)
  local t = {}
  local i = 0
  while indefinite or i < len do
    local k, v
    k, pos = decode_item(s, pos, indefinite)
    if k == BREAK then return t, pos end
    if k == nil then error("hwc: cbor: null map key", 0) end
    v, pos = decode_item(s, pos, false)
    i = i + 1
    t[k] = v
  end
  return t, pos
end

-- Returns the decoded value and the next position. `allow_break` lets a 0xff
-- stop code through as BREAK (only valid inside indefinite containers).
decode_item = function(s, pos, allow_break)
  if pos > #s then truncated() end
  local ib = byte(s, pos)
  pos = pos + 1
  if ib == 0xff then
    if allow_break then return BREAK, pos end
    error("hwc: cbor: unexpected break", 0)
  end
  local major = bit.rshift(ib, 5)
  local ai = bit.band(ib, 0x1f)

  if major == 7 then
    if ai == 20 then return false, pos end
    if ai == 21 then return true, pos end
    if ai == 22 or ai == 23 then return nil, pos end -- null, undefined
    if ai == 25 then return half_to_number(read_uint(s, pos, 2)), pos + 2 end
    if ai == 26 then return single_to_number(s, pos), pos + 4 end
    if ai == 27 then return double_to_number(s, pos), pos + 8 end
    error("hwc: cbor: unsupported simple value", 0)
  end

  local arg, npos, indefinite = read_argument(s, pos, ai)
  pos = npos
  if major == 0 then
    if indefinite then error("hwc: cbor: bad indefinite integer", 0) end
    return arg, pos
  elseif major == 1 then
    if indefinite then error("hwc: cbor: bad indefinite integer", 0) end
    return -1 - arg, pos
  elseif major == 2 or major == 3 then
    return decode_string(s, pos, major, arg, indefinite)
  elseif major == 4 then
    return decode_array(s, pos, arg, indefinite)
  elseif major == 5 then
    return decode_map(s, pos, arg, indefinite)
  end
  -- major 6: tag. Skip the number and return the inner item.
  if indefinite then error("hwc: cbor: bad indefinite tag", 0) end
  return decode_item(s, pos, false)
end

function M.deserialize_cbor(bytes)
  local value, pos = decode_item(bytes, 1, false)
  if pos <= #bytes then error("hwc: cbor: trailing data", 0) end
  return value
end

-- ------------------------------------------------------------- C_EncodingUtil

-- Plain functions (not methods), matching the WoW signatures.
function M.c_encoding_util()
  return {
    DecodeBase64 = M.decode_base64,
    DecompressString = M.decompress,
    DeserializeCBOR = M.deserialize_cbor,
  }
end

return M
