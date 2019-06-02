local component = component or require("component")

local setmetatable, type, assert = setmetatable, type, assert
local min, max, concat = math.min, math.max, table.concat

local EMPTY_CHAR = " "

local instance, class, instanceof
do --oop
 function instance(class, ...)
  return setmetatable({}, class):__init(...)
 end

 function class()
  local class = {}
  class.__index = class
  class.__class = class
  return class
 end
end

local int2pcol, pcol2int
do
 function int2pcol(i)
  if i < 0 then return -1 - i, true end
  return i, false
 end

 function pcol2int(col, palette)
  if palette then return -1 - i end
  return col
 end
end

local buffer = class()
do
 local function idx(x, y, w) return (x - 1 + (y - 1) * w) * 3 + 1 end

 function buffer:__init(w, h)
  assert(type(w) == "number" and w > 0, "invalid width")
  assert(type(h) == "number" and h > 0, "invalid height")
  
  self.width = w
  self.height = h
  
  self.data = {}
  self:clear()

  return self
 end
 
 function buffer:size()
  return self.width, self.height
 end
 
 function buffer:resize(w, h)
  assert(type(w) == "number" and w > 0, "invalid width")
  assert(type(h) == "number" and h > 0, "invalid height")
  
  self.width, self.height = w, h
  self:clear()
 end
 
 function buffer:get(x, y)
  local data = self.data
  local i = idx(x, y, self.width)
  return data[i], data[i + 1], data[i + 2]
 end
 
 function buffer:set(x, y, back, fore, char)
  local data = self.data
  local i = idx(x, y, self.width)
  if back then data[i] = back end
  if fore then data[i + 1] = fore end
  if char then data[i + 2] = char end
 end
 
 function buffer:clear()
  local w, h, data = self.width, self.height, self.data
  for i = 1, w * h * 3, 3 do
   data[i], data[i + 1], data[i + 2] = 0, 0, EMPTY_CHAR
  end
 end

 
 function buffer:__tostring()
  return "gfx-buffer: " .. self.width .. "x" .. self.height
 end
end

local context = class()
do
 local function pixelCompare(back1, fore1, char1, back2, fore2, char2)
  if back1 ~= back2 then return false end
  if char1 ~= char2 then return false end
  if char1 ~= EMPTY_CHAR and fore1 ~= fore2 then return false end
  return true
 end

 local function pixelCompareIgnoreChar(back1, fore1, char1, back2, fore2, char2)
  if back1 ~= back2 then return false end
  if char1 ~= EMPTY_CHAR and char2 ~= EMPTY_CHAR and fore1 ~= fore2 then return false end
  return true
 end

 -- returns: width, height, operation (0 - fill, 1 - set, 2 - set vertical)
 local function findOptimalDrawCall(back, fore, char, x, y, w, h, front, backbuf)
  local sethScore = 1
  local setvScore = 1
  local fillxScore = 1
  local fillyScore = 1
  
  -- finding scores (area of draw call)
  local b, f, c, b1, c1, f1
  for x1 = x + 1, w do
   b, f, c = front:get(x1, y)
   if pixelCompare(b, f, c, backbuf:get(x1, y)) then break end

   if fillxScore == sethScore and pixelCompare(back, fore, char, b, f, c) then 
    fillxScore = fillxScore + 1 
    sethScore = sethScore + 1
   elseif pixelCompareIgnoreChar(back, fore, char, b, f, c) then
    sethScore = sethScore + 1
   else 
    break
   end
  end
  
  local rowXDiff = fillxScore - 1
  for y1 = y + 1, h do
   b, f, c = front:get(x, y1)
   if pixelCompare(b, f, c, backbuf:get(x, y1)) then break end

   if fillyScore == setvScore and pixelCompare(back, fore, char, b, f, c) then 
    setvScore = setvScore + 1

    local valid = true
    for x1 = x, x + rowXDiff do
     b1, f1, c1 = front:get(x1, y1)
     if not pixelCompare(back, fore, char, b, f, c) then
      valid = false
      break
     end
    end

    if valid then 
     fillyScore = fillyScore + 1 
    end
   elseif pixelCompareIgnoreChar(back, fore, char, b, f, c) then
    setvScore = setvScore + 1
   else
    break
   end
  end

  -- finding optimal drawcall using previously calculated scores
  local fillScore = fillxScore * fillyScore
  if fillScore >= sethScore then
   if fillScore >= setvScore then
    return fillxScore, fillyScore, 0
   else
    return 1, setvScore, 2
   end
  else
   if sethScore > setvScore then
    return sethScore, 1, 1
   else
    return 1, setvScore, 2
   end
  end
 end

 function context:__init(gpu, w, h)
  assert(gpu and gpu.address and component.type(gpu.address) == "gpu", "invalid gpu")
  assert(not w or (type(w) == "number" and w > 0), "invalid width")
  assert(not h or (type(h) == "number" and h > 0), "invalid height")

  self.front = instance(buffer, 1, 1)
  self.back = instance(buffer, 1, 1)
  
  self.gpu = gpu
  local rw, rh = gpu.getResolution()
  self:setResolution(w or rw, h or rh)
 
  return self
 end

 function context:getResolution()
  return w, h
 end

 function context:setResolution(w, h)
  self.width = w or self.width
  self.height = h or self.height
  
  self.front:resize(w, h)
  self.back:resize(w, h)
  
  self.gpu.setResolution(w, h)
  self.gpu.fill(1, 1, w, h, EMPTY_CHAR)
 end

 function context:flush(a, b, w, h)
  local gpu = self.gpu
  local front, back = self.front, self.back
  local sw, sh = self.width, self.height 

  a = max(a or 1, 1) 
  b = max(b or 1, 1)
  w = min(w or sw, sw)
  h = min(h or sh, sh)

  local foreColor = pcol2int(gpu.getForeground())
  local backColor = pcol2int(gpu.getBackground())
  local drawCalls = 0
  local charbuf = {}

  local b1, f1, c1
  for y = b, h do
   for x = a, w do
    b1, f1, c1 = front:get(x, y)

    if not pixelCompare(b1, f1, c1, back:get(x, y)) then
     local dwidth, dheight, operation = findOptimalDrawCall(b1, f1, c1, x, y, w, h, front, back)
     
     if backColor ~= b1 then 
      gpu.setBackground(int2pcol(b1))
      backColor = b1
     end

     if c1 ~= EMPTY_CHAR and foreColor ~= f1 then
      gpu.setForeground(int2pcol(f1))
      foreColor = f1
     end

     if operation == 0 then
      for y0 = y, y + dheight - 1 do
       for x0 = x, x + dwidth - 1 do
       back:set(x0, y0, b1, f1, c1)
      end
     end
  
     gpu.fill(x, y, dwidth, dheight, c1)
    elseif operation == 1 then
     for c = 1, dwidth do
      local x0 = x + c - 1 
      local _, _, ch = front:get(x0, y)
  
      back:set(x0, y, b1, f1, ch)
      charbuf[c] = ch 
     end
 
     gpu.set(x, y, concat(charbuf, nil, 1, dwidth))
    else
     for c = 1, dheight do
      local y0 = y + c - 1 
      local _, _, ch = front:get(x, y0)
  
      back:set(x, y0, b1, f1, ch)
      charbuf[c] = ch 
     end
 
     gpu.set(x, y, concat(charbuf, nil, 1, dheight), true)
    end

    drawCalls = drawCalls + 1
    x = x + dwidth - 1
   end
  end
 end
 return drawCalls
end

 function context:backbuffer()
  return self.back
 end

 function context:frontbuffer()
  return self.front
 end

 function context:__tostring()
  return "gfx-context: " .. self.gpu.address .. " (".. self.width .. "x" .. self.height .. ")"
 end
end

local M = {}

function M.context(...)
 return instance(context, ...)
end

function M.pixelbuffer(...)
 return instance(buffer, ...)
end

M.pcol2int = pcol2int
M.int2pcol = int2pcol

return M