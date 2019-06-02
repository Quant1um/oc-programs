local bit32 = bit32 or require("bit32")
local band, bor, bnot = bit32.band, bit32.bor, bit32.bnot
local lshift, rshift = bit32.lshift, bit32.rshift

local M = {}

local BYTE_MASK = 0xff
local NO_LSB_MASK = 0xfefefe

local SPLIT2_MASK = 0xFF00FF
local COMBINE2_MASK = 0xFF00FF00

local function pack(r, g, b)
 return bor(b, lshift(g, 8), lshift(r, 16))
end

local function unpack(rgb)
 return band(rshift(rgb, 16), BYTE_MASK), 
        band(rshift(rgb, 8),  BYTE_MASK), 
        band(rgb,             BYTE_MASK)
end

M.pack = pack
M.unpack = unpack

function M.blend(a, b, t)
 if t <= 0 then return a
 elseif t < 255 then
  t = t + 1

  local rb0 = band(a, SPLIT2_MASK)
  local rb1 = band(b, SPLIT2_MASK)
  local g0 = band(rshift(a, 8), SPLIT2_MASK)
  local g1 = band(rshift(b, 8), SPLIT2_MASK)
  local s = 256 - t

  local rb = rb1 * t + rb0 * s
  local g = g1 * t + g0 * s

  return bor(rshift(band(rb, COMBINE2_MASK), 8), band(g, COMBINE2_MASK))
 else return b end
end

function M.add(a, b)
 local sum = band(a, NO_LSB_MASK) + band(b, NO_LSB_MASK)
 return bor(sum, band(rshift(sum, 8), 0x101010) * 0xff)
end

return M