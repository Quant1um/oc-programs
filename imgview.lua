-- color utils
local function rgb2int(r, g, b)
 return b + 256 * (g + r * 256)
end

local palette3 = (function()
 local red = { 0x00, 0x33, 0x66, 0x99, 0xCC, 0xFF }
 local green = { 0x00, 0x24, 0x49, 0x6D, 0x92, 0xB6, 0xDB, 0xFF }
 local blue = { 0x00, 0x40, 0x80, 0xC0, 0xFF }

 local palette = {}
 
 for r = 0, 5 do
  for g = 0, 7 do
   for b = 0, 4 do
    local rbase = red[r + 1]
    local gbase = green[g + 1]
    local bbase = blue[b + 1]
   
    palette[b + 5 * (g + 8 * r)] = rgb2int(rbase, gbase, bbase)
   end
  end
 end

 for gray = 0, 15 do
  local base = (gray + 1) * 0x0F
  palette[240 + gray] = rgb2int(base, base, base)
 end
 
 palette.size = 256
 return palette
end)()

local function setIndexedBackgroundColor(gpu, index)
 if index < 0 then
  gpu.setBackground(palette3[-(1 + index)], false)
 else
  gpu.setBackground(index, true)
 end
end

local function applyIndexedPalette(gpu, palette)
 for i = 0, palette.size - 1 do
  gpu.setPaletteColor(i, palette[i])
 end
end

local function readIndexedPalette(gpu)
 local palette = {}
 palette.size = 16
 for i = 0, palette.size - 1 do
  palette[i] = gpu.getPaletteColor(i)
 end
 return palette
end

-- io utils
local function readByte(handler)
 local byte, err = handler:read(1)

 if err then
  error("failed to read: " .. err)
 elseif not byte then
  error("failed to read: unexpected eof")
 else
  return string.byte(byte)
 end
end

local function readHeader(handle)
 local header = {}
 
 header.height = readByte(handle)
 header.palette = {}
 header.palette.size = readByte(handle)
 for i = 1, header.palette.size do
  header.palette[i - 1] = rgb2int(readByte(handle), readByte(handle), readByte(handle))
 end

 return header
end

local function readStride(handler)
 local stride = {}

 local data, err = handler:read(9)
 if not data or #data < 9 then
  if err then
   error("cannot read file: " .. err)
  else
   return false
  end
 end

 local paletteMask = string.byte(data, 9)
 for i = 1, 8 do
  local index = string.byte(data, i)
  stride[i] = bit32.btest(paletteMask, bit32.lshift(1, i - 1)) and index or -(1 + index)
 end

 return stride
end

local fs = require("filesystem")
local shell = require("shell")
local component = require("component")
local event = require("event")
local gpu = component.gpu

local args = {...}
if #args < 1 then
 io.stderr:write("Usage: ocpview <file>")
 return
end

if not gpu then
 io.stderr:write("No primary GPU found!")
 return
end

local path = shell.resolve(args[1])

if not fs.exists(path) then
 io.stderr:write("No such file found!")
 return
end

local handle, ferr = io.open(path, "rb")

if ferr then
 io.stderr:write("Failed to open file: " .. ferr)
end

local header = readHeader(handle)

local oldPalette = readIndexedPalette(gpu)
local oldw, oldh = gpu.getResolution()
local oldDepth = gpu.getDepth()

gpu.setResolution(gpu.maxResolution())
gpu.setDepth(gpu.maxDepth())

applyIndexedPalette(gpu, header.palette)

local w, h = gpu.getResolution()
local i, j = 1, 1
local function pushIndex(index)
 if i <= w and j <= h then
  setIndexedBackgroundColor(gpu, index)
  gpu.fill(i, j, 1, 1, " ")
 end

 j = j + 1
 if j > header.height then
  j = 1
  i = i + 1
 end
end

while true do
 local indices = readStride(handle)
 if not indices then break end

 for i = 1, #indices do 
  pushIndex(indices[i])
 end
end

handle:close()
while event.pull() ~= "interrupted" do end

gpu.fill(1, 1, w, h, " ")
gpu.setResolution(oldw, oldh)
gpu.setDepth(oldDepth)
applyIndexedPalette(gpu, oldPalette)