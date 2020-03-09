local event = require("event")
local component = require("component")
local rgfx = require("rgfx")
local xrgfx = require("xrgfx")
local shell = require("shell")
local ser = require("serialization")
local computer = require("computer")
local unicode = require("unicode")
local buf = rgfx.buffer

local limqueue = {}
do
    function limqueue.create(limit)
        return { first = 0, last = limit - 1 }
    end

    function limqueue.push(list, value)
        local last = list.last + 1
        local first = list.first
        
        list.last = last
        list.first = first + 1

        list[last] = value
        list[first] = nil
    end

    local iter = function(a, i)
        i = i - 1
        local v = a[i]
        if i > a.first then
            return i, v
        end
    end

    function limqueue.iterate(list)
        return iter, list, list.last + 1
    end

    function limqueue.get(list, i)
        return list[list.last - i + 1]
    end
end

local config, updateConfig
do
    local path = shell.resolve(({...})[1] or "chamber", "cfg")
    if not path then
        io.stderr:write("No such datafile!\n")
        return
    end

    local datafile, err = io.open(path, "r")
    if not datafile then
        io.stderr:write("Error while reading datafile: " .. err .. "\n")
        return
    end

    config = ser.unserialize(datafile:read("*a"))
    datafile:close()

    if type(config) ~= "table" then
        io.stderr:write("Invalid datafile content\n")
        return
    end

    local function assign(dest, src)
        for k, v in pairs(src) do
            local s = dest[k]
            if type(s) == "table" and type(v) == "table" then assign(s, v)
            elseif s ~= nil then dest[k] = v end
        end

        return dest
    end
    
    config = assign({
        components = {
            chamber = false,
            buffer = false,
            redstone = false,
            transposer = false,
            gpu = false
        },
        
        heat = { enabled = true, min = 0.1, max = 0.5 },
        energy = { enabled = true, min = 0.1, max = 0.5 },

        manual = 0
    }, config)

    function updateConfig() 
        local datafile, err = io.open(path, "w")
        if not datafile then
            io.stderr:write("Error while writing datafile: " .. err .. "\n")
            return
        end

        datafile:write(ser.serialize(config))
        datafile:close()
    end

    updateConfig() 
end

local chamber = component.proxy(config.components.chamber or "")
local redstone = component.proxy(config.components.redstone or "")
local buffer = component.proxy(config.components.buffer or "")
local transposer = component.proxy(config.components.transposer or "")
local gpu = component.proxy(config.components.gpu or component.gpu.address)

if not chamber or not redstone or not gpu or not buffer or not transposer then
    io.stderr:write("Invalid component configuration.\n")
    io.stderr:write("Reconfigure components in the datafile!\n")
    return
end

local transposerSide = nil
for i = 0, 5 do
    if transposer.getInventorySize(i) then
        if transposerSide then 
            io.stderr:write("Invalid component configuration: transposer side ambiguity\n")
            io.stderr:write("Reconfigure components in the datafile!\n")
            return
        end

        transposerSide = i
    end
end

print("Chamber: "       .. chamber.address)
print("Accumulator: "   .. buffer.address)
print("Redstone: "      .. redstone.address)
print("GPU: "           .. gpu.address)
print("Transposer: "    .. transposer.address)

os.sleep(0.02)

local state = { 
    configure = nil,
    graph = 0,
    history = {
        heat = limqueue.create(150),
        energy = limqueue.create(150),
        production = limqueue.create(150),
        consumption = limqueue.create(150),
        fuel = limqueue.create(150)
    },

    explanation = "",
    description = "",
    active = nil, 

    heat = {
        value = 0,
        max = 0,
        rel = 0
    },

    energy = {
        value = 0,
        max = 0,
        delta = 0,
        rel = 0
    },

    fuel = {
        value = 0,
        full = 0,
        rods = 0,
        rel = 0
    },

    consumption = 0,
    output = 0,
    producing = false
}

local redraw, w, h
do
    local front, back = buf.create(), buf.create()

    local colors = {
        back = 0x454545,
        dark = 0x343434,
        light = 0x565656,
        white = 0xffffff,

        red = 0xfe0000,
        green = 0x00fe00,
        blue = 0x2255fe,

        dred = 0x992222,
        dgreen = 0x229922,
        dblue = 0x223399,

        sred = 0xfe5555,
        sgreen = 0x55fe55,
        sblue = 0x4477fe
    }

    local i = 1
    for _, color in pairs(colors) do
        gpu.setPaletteColor(i, color)
        i = i + 1
    end

    local frames = 0

    local function dhandler(y, v, c)
        local bend = w - 6
        local bstart = 5
        local x = math.floor((v or 0) * (bend - bstart) + bstart + 0.5)
        
        buf.set(front, x, y, "⇃", c, colors.back)
    end

    local function uhandler(y, v, c)
        local bend = w - 6
        local bstart = 5
        local x = math.floor((v or 0) * (bend - bstart) + bstart + 0.5)
        
        buf.set(front, x, y, "↾", c, colors.back)
    end

    local function bar(y, v, c0, c1, c2)
        local bend = w * 2 - 10
        local bstart = 9
        local bedge = math.floor((v or 0) * (bend - bstart) + bstart + 0.5)
        for i = bstart, bend do
            local color = c0
            if i <= bedge then
                color = (i + frames) & 2 == 0 and c1 or c2
            end

            xrgfx.bset1(front, i, y * 4 - 2, color)
        end
    end

    local function text(x, y, str, cl, cl1)
        for c in string.gmatch(str, ".") do
            buf.set(front, x, y, c, cl, cl1 or colors.back)
            x = x + 1
        end
    end

    local function textr(x, y, str, cl, cl1)
        text(x - #str + 1, y, str, cl, cl1)
    end

    local function fnum(f)
        if f > -0.01 and f < 0.01 then f = 0 end
        return string.format("%2.2f", f)
    end

    local function fnumi(f)
        if f > -0.01 and f < 0.01 then f = 0 end
        return string.format("%2.0f", math.floor(f + 0.5))
    end

    local function ftime(s)
        s = math.floor(s)
        local seconds = s % 60
        s = s // 60
        local minutes = s % 60
        local hours = s // 60

        return string.format("%02d:%02d:%02d", hours, minutes, seconds)
    end

    local function graph(gstart, gend, gxstart, gxend, col, func)
        local xx = gxend * 2
        local lasty = nil

        local i = 1
        local v = func(i)
        while v and xx >= gxstart * 2 - 1 do
            local y = math.floor((1 - v) * (gend * 4 + 6 - gstart * 4 - 3) + gstart * 4 - 3 + 0.5)
            local y2 = lasty or y
            
            local sgn = (y > y2) and -1 or ((y < y2) and 1 or 0)
            y2 = y2 - sgn

            if lasty then
                for i = math.min(y, y2), math.max(y, y2) do
                    xrgfx.bset1(front, xx, i, col)
                end
             
                xx = xx - 1
            end

            lasty = y

            i = i + 1
            v = func(i)
        end
    end

    local function defgraph(gstart, gend, gxstart, gxend, limq, color, name)
        local min = 1
        local max = 0

        for _, v in limqueue.iterate(limq) do
            if v == nil then break end
            min = math.min(v, min)
            max = math.max(v, max)
        end

        local center = (min + max) / 2
        local diff   = (max - min) / 2
        diff = math.max(diff, 0.025)
        min = math.max(center - diff, 0)
        max = math.min(center + diff, 1)
        
        graph(gstart, gend, gxstart, gxend, color, function(i)
            local v = limqueue.get(limq, i)
            if v == nil then return nil end
            return (v - min) / (max - min)
        end)

        textr(gxend, gstart - 1, fnumi(max * 100) .. " %", colors.light)
        textr(gxend, gend + 1, fnumi(min * 100) .. " %", colors.light)
        text(gxstart, gend + 1, name, colors.light)
    end

    local function eutgraph(gstart, gend, gxstart, gxend, limq, color, name)
        local min = math.huge
        local max = -math.huge

        for _, v in limqueue.iterate(limq) do
            if v == nil then break end
            min = math.min(v, min)
            max = math.max(v, max)
        end

        local center = (min + max) / 2
        local diff   = (max - min) / 2
        diff = math.max(diff, 32)
        min = center - diff
        max = center + diff
        
        graph(gstart, gend, gxstart, gxend, color, function(i)
            local v = limqueue.get(limq, i)
            if v == nil then return nil end
            return (v - min) / (max - min)
        end)

        textr(gxend, gstart - 1, fnumi(max) .. " EU/t", colors.light)
        textr(gxend, gend + 1, fnumi(min) .. " EU/t", colors.light)
        text(gxstart, gend + 1, name, colors.light)
    end

    local function timegraph(gstart, gend, gxstart, gxend, limq, color, name)
        local min = math.huge
        local max = -math.huge

        for _, v in limqueue.iterate(limq) do
            if v == nil then break end
            min = math.min(v, min)
            max = math.max(v, max)
        end

        local center = (min + max) / 2
        local diff   = (max - min) / 2
        diff = math.max(diff, 32)
        min = math.max(center - diff, 0)
        max = center + diff
        
        graph(gstart, gend, gxstart, gxend, color, function(i)
            local v = limqueue.get(limq, i)
            if v == nil then return nil end
            return (v - min) / (max - min)
        end)

        textr(gxend, gstart - 1, ftime(max), colors.light)
        textr(gxend, gend + 1, ftime(min), colors.light)
        text(gxstart, gend + 1, name, colors.light)
    end

    local graphDrawers = {
        function(gstart, gend, gxstart, gxend)
            defgraph(gstart, gend, gxstart, gxend, state.history.energy, colors.sblue, "ACCUMULATED")
        end,

        function(gstart, gend, gxstart, gxend)
            defgraph(gstart, gend, gxstart, gxend, state.history.heat, colors.sred, "TEMPERATURE")
        end,

        function(gstart, gend, gxstart, gxend)
            eutgraph(gstart, gend, gxstart, gxend, state.history.production, colors.sgreen, "PRODUCTION")
        end,

        function(gstart, gend, gxstart, gxend)
            eutgraph(gstart, gend, gxstart, gxend, state.history.consumption, colors.blue, "CONSUMPTION")
        end,

        function(gstart, gend, gxstart, gxend)
            timegraph(gstart, gend, gxstart, gxend, state.history.fuel, colors.green, "FUEL LEFT")
        end
    }

    function redraw()
        frames = frames + 1
        w, h = front.w, front.h

        buf.fill(front, " ", colors.white, colors.back)

        local panel = h - 2

        if state.configure then
            local conf = state.configure

            text(17, 3, "LIMIT", conf.energy.enabled and colors.white or colors.light, 0x4477fe)
            text(5, 3, "ACCUMULATED", colors.white)
            textr(w - 5, 3, fnumi(conf.energy.min * 100) .. " % - " .. fnumi(conf.energy.max * 100) .. " %", colors.white)
            bar(5, state.energy.rel, colors.dblue, colors.blue, colors.sblue)
            dhandler(4, conf.energy.min, colors.light)
            uhandler(6, conf.energy.max, colors.light)
    
            text(17, 8, "LIMIT", conf.heat.enabled and colors.white or colors.light, 0xfe5555)  
            text(5, 8, "TEMPERATURE", colors.white)
            textr(w - 5, 8, fnumi(conf.heat.min * 100) .. " % - " .. fnumi(conf.heat.max * 100) .. " %", colors.white)
            bar(10, state.heat.rel, colors.dred, colors.red, colors.sred)
            dhandler(9, conf.heat.min, colors.light)
            uhandler(11, conf.heat.max, colors.light)    

            textr(w - 12, panel, "APPLY",  colors.light, colors.green)
            textr(w - 5,  panel, "CANCEL", colors.light, colors.red)
        else
            text(5, 3, "PRODUCTION", colors.white)
            textr(w - 5, 3, string.format("%d EU/t / %d EU/t", math.floor(state.output), math.floor(state.consumption)), colors.white)
            bar(4, state.output / state.consumption, colors.dgreen, colors.green, colors.sgreen)

            local rods = state.fuel.rods
            local rodstr = "no rods"
            if rods == 1 then 
                rodstr = "1 rod"
            elseif rods > 1 then 
                rodstr = rods .. " rods" 
            end

            text(5, 6, "FUEL", colors.white)
            textr(w - 5, 6, string.format("%s (%s)", ftime(state.fuel.value), rodstr), colors.white)
            bar(7, state.fuel.rel, colors.dgreen, colors.green, colors.sgreen)  

            text(5, 9, "ACCUMULATED", colors.white)
            textr(w - 5, 9, fnum(state.energy.rel * 100) .. " %", colors.white)
            bar(10, state.energy.rel, colors.dblue, colors.blue, colors.sblue)
    
            text(5, 12, "TEMPERATURE", colors.white)
            textr(w - 5, 12, fnum(state.heat.rel * 100) .. " %", colors.white)
            bar(13, state.heat.rel, colors.dred, colors.red, colors.sred)    

            local gstart = 15
            local gend = panel - 3
            local gxstart = 5
            local gxend = w - 5

            for i = gxstart, gxend do
                for j = gstart, gend do
                    buf.set(front, i, j, " ", colors.white, colors.dark)
                end
            end
            
            graphDrawers[(state.graph % #graphDrawers) + 1](gstart, gend, gxstart, gxend)

            text(5,  panel, "OFF",  config.manual <  0 and colors.white or colors.light, colors.red)
            text(9,  panel, "AUTO", config.manual == 0 and colors.white or colors.light, colors.sblue)
            text(14, panel, "ON",   config.manual >  0 and colors.white or colors.light, colors.green)
            
            text(17, panel, state.description, colors.light)

            textr(w - 15, panel, "GRAPH MODE", colors.light, colors.white)
            textr(w - 5,  panel, "CONFIGURE", colors.light, colors.white)
        end

        rgfx.flush2b(gpu, front, back)
    end
end

local automatics = {}
do
    function automatics.combine(...)
        local autos = {...}
        
        return function()
            local expl = nil

            for _, auto in ipairs(autos) do
                local s, e = auto()

                expl = e
                if not s then
                    return false, expl
                end
            end
            
            return true, expl
        end
    end

    function automatics.heat()
        local result, expl = true, nil
        return function()
            if config.heat.enabled then
                local rheat = state.heat.rel
                if rheat >= config.heat.max then 
                    result = false
                    expl = "OVERHEAT"
                elseif rheat <= config.heat.min then 
                    result = true
                    expl = nil
                end

                return result, expl
            end

            return true
        end
    end

    function automatics.energy()
        local result, expl = true, nil
        return function()
            if config.energy.enabled then
                local renergy = state.energy.rel
                if renergy >= config.energy.max then 
                    result = false
                    expl = "ACCUMULATOR OVERFLOW"
                elseif renergy <= config.energy.min then 
                    result = true
                    expl = nil
                end

                return result, expl
            end

            return true
        end
    end

    automatics.current = automatics.combine(automatics.heat(), automatics.energy())
end

do
    local events = {}

    local energyA, energyT = nil, -math.huge
    local function calculateDelta()
        if energyA == nil then
            energyA = state.energy.value
            energyT = computer.uptime()
            state.energy.delta = 0
        else
            local t = computer.uptime()
            state.energy.delta = (state.energy.value - energyA) / ((t - energyT) * 20)

            energyA = state.energy.value
            energyT = t
        end
    end

    local acceptableRodIds = {
        ["ic2:uranium_fuel_rod"] = true,
        ["ic2:dual_uranium_fuel_rod"] = true,
        ["ic2:quad_uranium_fuel_rod"] = true,
        ["ic2:mox_fuel_rod"] = true,
        ["ic2:dual_mox_fuel_rod"] = true,
        ["ic2:quad_mox_fuel_rod"] = true,
        ["ic2:lithium_fuel_rod"] = true,
        ["ic2:depleted_isotope_fuel_rod"] = true
    }

    local depletedRodIds = {
        ["ic2:nuclear:11"] = 20000,
        ["ic2:nuclear:12"] = 20000,
        ["ic2:nuclear:13"] = 20000,
        ["ic2:nuclear:14"] = 10000,
        ["ic2:nuclear:15"] = 10000,
        ["ic2:nuclear:16"] = 10000
    }

    local function checkStack(table, stack)
        return table[stack.name] or table[string.format("%s:%d", stack.name, stack.damage)]
    end

    local function calculateFuelDuration()
        local stacks = transposer.getAllStacks(transposerSide).getAll()

        local value = 0
        local full = 0
        local count = 0

        for _, stack in ipairs(stacks) do
            if stack then
                if checkStack(acceptableRodIds, stack) then
                    local timeLeft = stack.maxDamage - stack.damage

                    value = math.max(value, timeLeft)
                    full = math.max(full, stack.maxDamage)
                    count = count + 1
                end

                local res = checkStack(depletedRodIds, stack)
                if res then
                    full = math.max(full, res)
                end
            end
        end

        state.fuel.value = value
        state.fuel.rods = count
        state.fuel.full = full
        state.fuel.rel = (value / full) or 0
    end

    local function readState() 
        state.heat.value = chamber.getHeat()
        state.heat.max = chamber.getMaxHeat()
        state.heat.rel = (state.heat.value / state.heat.max) or 0

        state.energy.value = buffer.getEnergy()
        state.energy.max = buffer.getCapacity()
        state.energy.rel = (state.energy.value / state.energy.max) or 0
        
        state.output = chamber.getReactorEUOutput()
        state.producing = state.output > 0

        calculateDelta()

        state.consumption = -state.energy.delta + state.output

        calculateFuelDuration()
    end

    local function controlState()
        local wasActive = state.active
        if config.manual == 0 then
            local result, explanation = automatics.current()

            state.active = result
            state.explanation = explanation or "AUTO"
        else
            state.active = config.manual > 0
            state.explanation = "MANUALLY OVERRIDDEN"
        end

        if state.active ~= wasActive then
            local t = {}
            for i = 0, 5 do t[i] = state.active and 15 or 0 end
            redstone.setOutput(t)
        end
    end

    local function getDescription()
        if state.fuel.rods == 0 then
            return "OUT OF FUEL"
        end

        if state.producing then
            if state.active then
                return "ENABLED: " .. state.explanation
            else
                return "TURNING OFF: " .. state.explanation
            end
        else
            if state.active then
                return "TURNING ON: " .. state.explanation
            else
                return "DISABLED: " .. state.explanation
            end
        end
    end

    local function updateDescription()
        state.description = getDescription()
    end

    function events.update()
        readState()
        controlState()
        updateDescription()
        redraw()
    end

    function events.longUpdate()
        limqueue.push(state.history.energy,         state.energy.rel)
        limqueue.push(state.history.heat,           state.heat.rel)
        limqueue.push(state.history.production,     state.output)
        limqueue.push(state.history.consumption,    state.consumption)
        limqueue.push(state.history.fuel,           state.fuel.value)
    end

    function events.touch(screenAddress, x, y, button, player)
        if screenAddress ~= gpu.getScreen() then return end

        if state.configure then
            local conf = state.configure
            if x >= 17 and x <= 21 and y == 3 then
                conf.energy.enabled = not conf.energy.enabled
            end

            if x >= 17 and x <= 21 and y == 8 then
                conf.heat.enabled = not conf.heat.enabled
            end

            local pstart = 5
            local pend = w - 6

            if x >= pstart and y <= pend then
                local val = math.floor((x - pstart) / (pend - pstart) * 20) / 20

                if y == 4 then
                    conf.energy.min = math.min(val, conf.energy.max)
                end

                if y == 6 then
                    conf.energy.max = math.max(val, conf.energy.min)
                end

                if y == 9 then
                    conf.heat.min = math.min(val, conf.heat.max)
                end

                if y == 11 then
                    conf.heat.max = math.max(val, conf.heat.min)
                end
            end

            if y == h - 2 then
                if x >= w - 16 and x <= w - 12 then
                    config.heat = conf.heat
                    config.energy = conf.energy
                    updateConfig()

                    state.configure = nil
                elseif x >= w - 10 and x <= w - 5 then
                    state.configure = nil
                end
            end
        else
            if y == h - 2 then
                if x >= 5 and x <= 7 then
                    config.manual = -1
                    updateConfig()
                elseif x >= 9 and x <= 12 then
                    config.manual = 0
                    updateConfig()
                elseif x >= 14 and x <= 16 then
                    config.manual = 1
                    updateConfig()
                elseif x >= w - 24 and x <= w - 15 then
                    state.graph = state.graph + 1
                elseif x >= w - 13 and x <= w - 5 then
                    state.configure = { 
                        heat = { 
                            enabled = config.heat.enabled, 
                            min     = config.heat.min, 
                            max     = config.heat.max 
                        },

                        energy = { 
                            enabled = config.energy.enabled, 
                            min     = config.energy.min, 
                            max     = config.energy.max 
                        }
                    }
                end
            end
        end
    end

    local running = true
    local function handleEvent(name, ...) 
        if name == "interrupted" then 
            running = false 
        end
        
        if name and events[name] then
            events[name](...)
        end
    end

    local lastLongUpdate = -math.huge
    while running do
        if events.update then events.update() end

        local cur = computer.uptime()
        if cur - lastLongUpdate > 30 then
            lastLongUpdate = cur
            if events.longUpdate then events.longUpdate() end
        end

        local data = table.pack(event.pull(0))
        while data[1] ~= nil do
            handleEvent(table.unpack(data))
            data = table.pack(event.pull(0))
        end

        handleEvent(event.pull(0.2))
    end
end