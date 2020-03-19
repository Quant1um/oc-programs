local component = require("component")
local event = require("event")
local computer = require("computer")
local keyboard = require("keyboard")
local bit32 = require("bit32")
local unicode = require("unicode")
local serialization = require("serialization")

local gpu = component.gpu
local running = true

local function fmult(num, k)
    if num == 1 then return string.format("%d %s", num, k)
    else return string.format("%d %ss", num, k) end
end

local function ftime(time)
    time = math.floor(time)
    local seconds = time % 60
    local minutes = math.floor(time / 60) % 60
    local hours = math.floor(time / 3600)

    local t = {}
    if hours > 0 then table.insert(t, fmult(hours, "hour")) end
    if minutes > 0 then table.insert(t, fmult(minutes, "minute")) end
    table.insert(t, fmult(seconds, "second"))

    local len = #t
    if len <= 1 then return t[1] end
    if len == 2 then return string.format("%s and %s", t[1], t[2]) end
    if len == 3 then return string.format("%s, %s and %s", t[1], t[2], t[3]) end
    error("invl: " .. len)
end

local leaderboards = {}
do
    local size = 9
    local data = {}

    local hnd = io.open("leaderboards.cfg", "r")
    if hnd then
        data = serialization.unserialize(hnd:read("*a")) or {}
        hnd:close()
    end

    local function flush()
        local hnd = io.open("leaderboards.cfg", "w")
        if hnd then
            hnd:write(serialization.serialize(data))
            hnd:close()
        else
            gpu.set(1, 1, "failed to write leaderboards")
            os.sleep(1)
        end
    end

    function leaderboards.insert(name, score, time)
        local wasInserted = false
        for i, v in ipairs(data) do
            if v[2] < score then
                table.insert(data, i, { name, score, time })
                wasInserted = true
                break
            end
        end

        if not wasInserted then
            table.insert(data, { name, score, time })
        end

        while #data > size do
            table.remove(data)
        end

        flush()
    end

    function leaderboards.iterate()
        return ipairs(data)
    end
end

local dir = {}
do
    dir.right   = 1
    dir.up      = 3
    dir.down    = 2
    dir.left    = 4

    function dir.offset(x, y, dir, n)
        n = n or 1
        dir = (dir - 1) % 4 + 1
        if dir == 1 then return x + n, y end
        if dir == 2 then return x, y + n end
        if dir == 3 then return x, y - n end
        if dir == 4 then return x - n, y end
    end

    function dir.inverse(dir)
        return 5 - dir
    end
end

local tiles = {}
do
    tiles.empty = 0
    tiles.apple = 1
    tiles.snake = 2

    function tiles.packsmeta(dir0, dir1)
        return bit32.bor(dir0 - 1, bit32.lshift(dir1 - 1, 2))
    end

    function tiles.unpacksmeta(m)
        return bit32.band(m, 3) + 1, bit32.rshift(m, 2) + 1
    end
end

local field = {}
do
    function field.create(w, h)
        local f = { w = w, h = h }
        for i = 1, w * h do
            f[i] = 0
        end

        return setmetatable(f, { __index = field })
    end

    function field.get(field, x, y)
        local w, h = field.w, field.h
        x = math.floor(x - 1) % w + 1
        y = math.floor(y - 1) % h + 1
        local val = field[x + y * w - w]
        return bit32.band(val, 0x0f), bit32.rshift(val, 4)
    end

    function field.set(field, x, y, tile, meta)
        local w, h = field.w, field.h
        x = math.floor(x - 1) % w + 1
        y = math.floor(y - 1) % h + 1
        field[x + y * w - w] = bit32.bor(tile, bit32.lshift(meta or 0, 4))
    end
end

local screen = {}
do
    local current

    function screen.current()
        return current
    end

    function screen.change(scr)
        screen.push("destroy", scr)
        local prev = current
        current = scr
        screen.push("spawn", prev)
    end

    function screen.push(name, ...)
        if current and name and current[name] then
            current[name](current, ...)
        end
    end
end

local titleScreen = {}
local gameScreen = {}

do
    function titleScreen.create(message, prevPlayer)
        return setmetatable({ message = message, prevPlayer = prevPlayer }, { __index = titleScreen })
    end

    function titleScreen.spawn(title)
        local w, h = gpu.getResolution()

        local y = 3
        for s in title.message:gmatch("[^\r\n]+") do
            gpu.set(math.floor((w - #s) / 2), y, s)
            y = y + 1
        end

        y = y + 2

        local pad = math.floor(w / 5)
        local pstart = pad
        local pend = w - pad
        for i, data in leaderboards.iterate() do
            local lstr = string.format("%d. %s", i, data[1])
            local rstr = string.format("%d apples", data[2])

            gpu.set(pstart, y, lstr)
            gpu.set(pend + 1 - #rstr, y, rstr)
            y = y + 1
        end

        title.startupTime = computer.uptime()
    end

    function titleScreen.key_down(title, address, char, code, name)
        if code == keyboard.keys.enter then
            if name == title.prevPlayer and (computer.uptime() - title.startupTime < 1) then
                return
            end

            computer.beep(500, 0.2)
            screen.change(gameScreen.create(name))
        end
    end

    function titleScreen.interrupted()
        running = false
    end
end

do
    local snakeSpriteTable = {
        [0] = unicode.char(0x2501),
        [1] = unicode.char(0x2517),
        [2] = unicode.char(0x250F),
        [4] = unicode.char(0x2513),
        [5] = unicode.char(0x2503),
        [7] = unicode.char(0x250F),
        [8] = unicode.char(0x251B),
        [10] = unicode.char(0x2503),
        [11] = unicode.char(0x2517),
        [13] = unicode.char(0x251B),
        [14] = unicode.char(0x2513),
        [15] = unicode.char(0x2501)
    }

    local deathSplashes = {
        "Thanks for playing!",
        "Thanks for playing!",
        "Thanks for playing!",
        "Thanks for playing.",
        "Nice try.",
        "Nice try.",
        "Nice try.",
        "Nice try!",
        "UwU"
    }

    local function generateApple(game)
        for i = 1, 10 do
            local x = math.random(game.w)
            local y = math.random(game.h)

            if game.current:get(x, y) == tiles.empty then
                game.next:set(x, y, tiles.apple)
                return true
            end
        end

        local pivotX = math.random(game.w)
        local pivotY = math.random(game.h)

        for j = pivotY, 1, -1 do
            for i = pivotX, 1, -1 do
                if game.current:get(i, j) == tiles.empty then
                    game.next:set(i, j, tiles.apple)
                    return true
                end
            end
        end

        for j = pivotY, game.h, 1 do
            for i = pivotX, 1, -1 do
                if game.current:get(i, j) == tiles.empty then
                    game.next:set(i, j, tiles.apple)
                    return true
                end
            end
        end

        for j = pivotY, 1, -1 do
            for i = pivotX, game.w, 1 do
                if game.current:get(i, j) == tiles.empty then
                    game.next:set(i, j, tiles.apple)
                    return true
                end
            end
        end

        for j = pivotY, game.h, 1 do
            for i = pivotX, game.w, 1 do
                if game.current:get(i, j) == tiles.empty then
                    game.next:set(i, j, tiles.apple)
                    return true
                end
            end
        end

        return false
    end

    local function eatApple(game)
        game.score = game.score + 1
        game.expandLock = game.expandLock + 3

        computer.beep(500, 0.05)
        return not generateApple(game)
    end

    local function winTheGame(game)
        leaderboards.insert(game.player, game.score, game.playTime)
        screen.change(titleScreen.create("You won! Congratulations!\nYou ate " .. game.score .. " apples.\nYou were alive for " .. ftime(game.playTime) .. "\nPress ENTER to restart.", game.player))
    
        computer.beep(500, 0.02)
        computer.beep(400, 0.02)
        computer.beep(300, 0.02)
        computer.beep(400, 0.02)
        computer.beep(500, 0.10)
    end

    local function loseTheGame(game)
        leaderboards.insert(game.player, game.score, game.playTime)
        screen.change(titleScreen.create("You died. " .. deathSplashes[math.random(#deathSplashes)] .. "\nYou ate " .. game.score .. " apples.\nYou were alive for " .. ftime(game.playTime) .. "\nPress ENTER to restart.", game.player)) 
    
        computer.beep(300, 0.1)
        computer.beep(100, 0.1)
        computer.beep(200, 0.2)
    end

    local function loseTheGameByInactivity(game)
        leaderboards.insert(game.player, game.score, game.playTime)
        screen.change(titleScreen.create("Game was stopped due to inactivity.\nYou ate " .. game.score .. " apples.\nYou were alive for " .. ftime(game.playTime) .. "\nPress ENTER to restart.", game.player))
    
        computer.beep(300, 0.1)
        computer.beep(100, 0.1)
        computer.beep(200, 0.2)
    end

    function gameScreen.create(player)
        return setmetatable({ player = player }, { __index = gameScreen })
    end

    function gameScreen.spawn(game)
        local w, h = gpu.getResolution()
        gpu.fill(1, 1, w, h, " ")

        game.statusBarY = h
        h = h - 1

        game.w = w
        game.h = h

        game.current = field.create(w, h)
        game.next = field.create(w, h)

        game.score = 0
        game.expandLock = 6
        game.headX = math.floor(w / 2)
        game.headY = math.floor(h / 2)
        game.headDir = dir.right
        game.nextDir = dir.right

        game.lastInput = computer.uptime()
        game.startTime = computer.uptime()
        game.playTime = 0

        game.inputQueue = {}

        generateApple(game)
    end

    function gameScreen.update(game)
        game.playTime = computer.uptime() - game.startTime
        if computer.uptime() - game.lastInput > 20 then
            loseTheGameByInactivity(game)
            return
        end

        -- changing direction
        if #game.inputQueue > 0 then
            local prevDir = game.headDir
            local nextDir = table.remove(game.inputQueue, 1)
            if nextDir ~= dir.inverse(game.headDir) then
                game.headDir = nextDir
            end

            if prevDir ~= game.headDir then
                game.next:set(game.headX, game.headY, tiles.snake, tiles.packsmeta(prevDir, game.headDir))
            end
        end

        local newSnakeMeta = tiles.packsmeta(game.headDir, game.headDir)

        if game.expandLock <= 0 then
            for j = 1, game.h do
                for i = 1, game.w do
                    local tile, meta = game.current:get(i, j)
                    if tile == tiles.snake then
                        local sdir = tiles.unpacksmeta(meta)
                        local prev, prevMeta = game.current:get(dir.offset(i, j, sdir, -1))
                        if prev == tiles.snake then
                            local pdir, ndir = tiles.unpacksmeta(prevMeta)
                            if ndir ~= sdir then
                                game.next:set(i, j, tiles.empty)
                            end
                        else
                            game.next:set(i, j, tiles.empty)
                        end 
                    end
                end
            end
        else
            game.expandLock = game.expandLock - 1
        end

        game.headX, game.headY = dir.offset(game.headX, game.headY, game.headDir)
        local at = game.current:get(game.headX, game.headY)
        if at == tiles.apple then
            if eatApple(game) then
                winTheGame(game)
                return
            end

            game.next:set(game.headX, game.headY, tiles.snake, newSnakeMeta)
        elseif at == tiles.snake then
            loseTheGame(game)
            return
        else 
            game.next:set(game.headX, game.headY, tiles.snake, newSnakeMeta)
        end

        for j = 1, game.h do
            for i = 1, game.w do
                local prevTile, prevMeta = game.current:get(i, j)
                local nextTile, nextMeta = game.next:get(i, j)

                if prevTile ~= nextTile or prevMeta ~= nextMeta then
                    local s = "U"
                    if nextTile == tiles.empty then s = " "
                    elseif nextTile == tiles.apple then s = unicode.char(0x25C8)
                    elseif nextTile == tiles.snake then
                        s = snakeSpriteTable[nextMeta] or "F"
                    end

                    gpu.set(i, j, s)
                    game.current:set(i, j, game.next:get(i, j))
                end
            end
        end

        local scoreText = "Score: " .. game.score
        gpu.set(1, game.statusBarY, tostring(game.player))
        gpu.set(game.w - #scoreText + 1, game.statusBarY, scoreText)
    end

    function gameScreen.key_down(game, address, char, code, name)
        if name == game.player then
            if code == keyboard.keys.w then table.insert(game.inputQueue, dir.up) end
            if code == keyboard.keys.s then table.insert(game.inputQueue, dir.down) end
            if code == keyboard.keys.a then table.insert(game.inputQueue, dir.left) end
            if code == keyboard.keys.d then table.insert(game.inputQueue, dir.right) end

            while #game.inputQueue > 2 do
                table.remove(game.inputQueue, 1)
            end

            game.lastInput = computer.uptime()
        end
    end
end

local function handleEvent(name, ...)
    screen.push(name, ...)
end

gpu.setBackground(0x000000)
gpu.setForeground(0xffffff)
local w, h = gpu.getResolution()
gpu.fill(1, 1, w, h, " ")

screen.change(titleScreen.create("Welcome to the Snake Game!\nPress ENTER to start."))
while running do
    local t = computer.uptime() + 0.1
    while computer.uptime() < t do
        handleEvent(event.pull(t - computer.uptime()))
    end
    handleEvent("update")
end