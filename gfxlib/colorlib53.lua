local M = {}

local BYTE_MASK = 0xff
local NO_LSB_MASK = 0xfefefe

local SPLIT2_MASK = 0xFF00FF
local COMBINE2_MASK = 0xFF00FF00

local function pack(r, g, b)
 return b | (g << 8) | (r << 16)
end

local function unpack(rgb)
 return (rgb >> 16) & BYTE_MASK, 
        (rgb >> 8)  & BYTE_MASK, 
        (rgb)       & BYTE_MASK
end

M.pack = pack
M.unpack = unpack

function M.blend(a, b, t)
 if t <= 0 then return a
 elseif t < 255 then
  t = t + 1  

  local rb0 = a & SPLIT2_MASK
  local rb1 = b & SPLIT2_MASK
  local g0 = (a >> 8) & SPLIT2_MASK
  local g1 = (b >> 8) & SPLIT2_MASK
  local s = 256 - t
  
  local rb = rb1 * t + rb0 * s
  local g = g1 * t + g0 * s

  return ((rb & COMBINE2_MASK) >> 8) | (g & COMBINE2_MASK)
 else return b end
end

function M.add(a, b)
 local sum = a & NO_LSB_MASK + b & NO_LSB_MASK
 return sum | ((sum >> 8) & 0x101010 * 0xff)
end

return M