local function instance(class, ...)
 return setmetatable({}, class):__init(...)
end

local M = {}

M.stages = {
 normal = { min = 0, max = .4, name = "normal" },
 burn = { min = .4, max = .5, name = "burn" },
 evaporate = { min = .5, max = .6, name = "evaporate" },
 hurt = { min = .7, max = .85, name = "hurt" },
 lava = { min = .85, max = 1, name = "lava" },
 meltdown = { min = 1, max = 1, name = "meltdown" }
}

local meta = {
 __tostring = function(self)
  return self.name
 end
}

for k, v in pairs(M.stages) do
 M.stages[k] = setmetatable(v, meta)
end

function M.stages.byTemp(temp)
 if temp < 0 then
  return M.stages.normal
 elseif temp > 1 then
  return M.stages.meltdown
 else
  for _, v in pairs(M.stages) do
   if type(v) == "table" and type(v.name) == "string" then
    if v.min <= temp and v.max > temp then
     return v
    end
   end
  end
  return M.stages.normal
 end
end

local heatlatch = {}
heatlatch.__index = heatlatch

local controller = {}
controller.__index = controller

function controller:__init(rc)
 assert(rc, "component should not be nil")

 self.chamber = rc
 self:update()

 return self
end

function controller:getOutput()
 return self.output
end

function controller:producesEnergy()
 return self:getOutput() > 1e-6
end

function controller:getHeat()
 return self.heat
end

function controller:getMaxHeat()
 return self.maxHeat
end

function controller:getRelativeHeat()
 return (self.heat / self.maxHeat) or 0
end

function controller:getHeatStage()
 return M.stages.byTemp(self:getRelativeHeat()) 
end

function controller:update()
 local comp = self.chamber

 self.heat = comp.getHeat()
 self.maxHeat = comp.getMaxHeat()
 self.output = comp.getReactorEUOutput()
end

function controller:latch(lock, unlock)
 return instance(heatlatch, self, lock, unlock)
end

function heatlatch:__init(owner, lock, unlock)
 assert(owner and owner.__index == controller, "controller expected") 
 assert(type(lock) == "number" and type(unlock) == "number", "number expected")
 assert(lock > unlock, "invalid params")

 self.owner = owner
 self.lockThreshold = lock
 self.unlockThreshold = unlock
 self.locked = false

 return self
end

function heatlatch:__pushSignal()
 self:isLocked()
end

function heatlatch:getOwner()
 return self.owner
end

function heatlatch:getThresholds()
 return self.lockThreshold, self.unlockThreshold
end

function heatlatch:isLocked()
 local heat = self.owner:getRelativeHeat()

 if self.locked and heat < self.unlockThreshold then
  self.locked = false
 elseif not self.locked and heat > self.lockThreshold then
  self.locked = true
 end

 return self.locked
end

local buflatch = {}
buflatch.__index = buflatch

local bufman = {}
bufman.__index = bufman

function bufman:__init(...)
 self.buffers = {}
 self:add(...)
 self:update()

 return self
end

function bufman:add(...)
 for _, v in pairs({...}) do
  assert(v, "buffer should not be nil")
  self.buffers[#self.buffers + 1] = v
 end
end

function bufman:__ipairs()
 return ipairs(self.buffers)
end

function bufman:__pairs()
 return pairs(self.buffers)
end

function bufman:getCapacity()
 return self.capacity
end

function bufman:getEnergy()
 return self.energy
end

function bufman:getRelativeEnergy()
 return (self.energy / self.capacity) or 0
end

function bufman:isFull()
 return self:getEnergy() >= self:getCapacity() - 1e-6
end

function bufman:isEmpty()
 return self:getEnergy() < 1e-6
end

function bufman:update()
 local buffers = self.buffers

 local capacity = 0
 local energy = 0

 for _, v in pairs(buffers) do
  capacity = capacity + v.getCapacity()
  energy = energy + v.getEnergy()
 end

 self.energy = energy
 self.capacity = capacity
end

function bufman:latch(lock, unlock)
 return instance(buflatch, self, lock, unlock)
end

function buflatch:__init(owner, lock, unlock)
 assert(owner and owner.__index == bufman, "buffer manager expected")
 assert(type(lock) == "number" and type(unlock) == "number", "number expected")
 assert(lock > unlock, "invalid params")

 self.owner = owner
 self.lockThreshold = lock
 self.unlockThreshold = unlock
 self.locked = false

 return self
end

function buflatch:getOwner()
 return self.owner
end

function buflatch:getThresholds()
 return self.lockThreshold, self.unlockThreshold
end

function buflatch:isLocked()
 local energy = self.owner:getRelativeEnergy()
 if self.locked and energy < self.unlockThreshold then
  self.locked = false
 elseif not self.locked and energy > self.lockThreshold then
  self.locked = true
 end

 return self.locked
end

function M.create(...)
 return instance(controller, ...)
end

function M.buffers(...)
 return instance(bufman, ...)
end

return M