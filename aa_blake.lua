local serialization = require("serialization")
local component = require("component")
local event = require("event")

--for debug purposes
--event.listen("modem_message", print) 
--event.listen("blake_error", print)

local pack = table.pack
local unpack = table.unpack
local sleep = os.sleep
local floor = math.floor

local function addr(address, port)
    return address .. ":" .. floor(tonumber(port) or 0)
end

local protoHeaderRequest = "![0blake"
local protoHeaderResponse = "![1blake"

local startServer, stopServer
do -- server
    local servers = {}

    event.listen("modem_message", function(name, localAddr, remoteAddr, port, distance, header, id, data)
        if header == protoHeaderRequest then
            local address = addr(localAddr, port)

            local handler = servers[address]
            if handler then
                local wasSent = false

                local function send(...)
                    if wasSent then error("message was already sent") end
                
                    local t = serialization.serialize(pack(...))
                    if component.invoke(localAddr, "send", remoteAddr, port, protoHeaderResponse, id, t) then
                        wasSent = true
                        return true
                    else
                        return false
                    end
                end

                local function sendError(err)
                    if wasSent then error("message was already sent") end
                
                    local t = serialization.serialize({ n = 0, error = err or "error" })
                    if component.invoke(localAddr, "send", remoteAddr, port, protoHeaderResponse, id, t) then
                        wasSent = true
                        return true
                    else
                        return false
                    end
                end

                local context = {
                    localAddress = localAddr,
                    remoteAddress = remoteAddr,
                    port = port,
                    distance = distance,
                    messageId = id,
                    
                    send = send,
                    error = sendError
                }

                local status, err = pcall(function()
                    local t = serialization.unserialize(data)
                    context.data = t

                    handler(context, unpack(t))
                end)

                if not status then
                    event.push("blake_error", "response", err, context)
                    if not wasSent then sendError(err) end
                    error(err)
                end
            end
        end
    end)

    function startServer(address, port, handler)
        servers[addr(address, port)] = handler
    end

    function stopServer(address, port)
        servers[addr(address, port)] = nil
    end
end

local request, cancelRequest
do -- client
    local reqId = 0
    local handlers = {}

    function request(address, port, device, timeout)
        assert(type(address) == "string", "address must be a string")
        assert(type(port) == "number", "port must be a number")

        if type(device) == "number" then
            device, timeout = timeout, device
        end

        if not device then
            local defaultModem = component.modem
            if not defaultModem then
                error("no primary modem found")
            end
            device = defaultModem.address
        end

        if not timeout then 
            timeout = 30
        end

        return function(handler, ...)
            local id = reqId
            reqId = reqId + 1
        
            local t = serialization.serialize(pack(...))
            if component.invoke(device, "send", address, port, protoHeaderRequest, id, t) then
                local timer = event.timer(timeout, function()
                    local handlerData = handlers[id]
                    if handlerData then
                        local context = {
                            localAddress = device,
                            remoteAddress = address,
                            port = port,
                            distance = nil,
                            messageId = id,

                            success = false,
                            error = "timeout exceeded",

                            request = function(timeout)
                                return request(address, port, device, timeout)
                            end,

                            requestSync = function(timeout)
                                return requestSync(address, port, device, timeout)
                            end
                        }

                        handlers[id] = nil

                        local status, err = xpcall(function()
                            handlerData.handler(context)
                        end, debug.traceback)

                        if not status then
                            event.push("blake_error", "request timeout", err, context)
                            error(err)
                        end
                    end
                end)

                handlers[id] = {
                    handler = handler,
                    timer = timer
                }

                return id
            else
                return nil, "modem has failed to send the message"
            end
        end
    end

    function cancelRequest(id)
        local handlerData = handlers[id]
        if handlerData then
            event.cancel(handlerData.timer)
            handlers[id] = nil
        end
    end

    function requestSync(address, port, device, timeout)
        local req = request(address, port, device, timeout)
        return function(...)
            local done = false
            local data = nil
            req(function(...)
                done = true
                data = pack(...)
            end, ...)
    
            while not done do
                sleep(0.08)
            end
            return unpack(data)
        end
    end

    event.listen("modem_message", function(name, localAddr, remoteAddr, port, distance, header, id, data)
        if header == protoHeaderResponse then
            local handler = handlers[id]
            if handler then
                local context = {
                    localAddress = localAddr,
                    remoteAddress = remoteAddr,
                    port = port,
                    distance = distance,
                    messageId = id,

                    success = true,

                    request = function(timeout)
                        return request(remoteAddr, port, localAddr, timeout)
                    end,

                    requestSync = function(timeout)
                        return requestSync(remoteAddr, port, localAddr, timeout)
                    end
                }

                event.cancel(handler.timer)
                handlers[id] = nil

                local status, err = xpcall(function()
                    local t = serialization.unserialize(data)

                    context.data = t
                    context.success = not t.error
                    context.error = t.error

                    handler.handler(context, unpack(t))
                end, debug.traceback)

                if not status then
                    event.push("blake_error", "request callback", err, context)
                    error(err)
                end
            end
        end
    end)
end

local router
do -- routing
    local function psegments(path, t)
        if not t then t = {} end
    
        if path == "" then return t end
    
        local n = #t
        for part in string.gmatch(path, "[^\\/]+") do
            if part ~= "." and part ~= "" then
                if part == ".." then
                    local prev = t[n]
                    if prev and prev ~= "." and prev ~= ".." then
                        t[n] = nil
                        n = n - 1
                    else
                        n = n + 1
                        t[n] = ".." 
                    end
                else
                    n = n + 1
                    t[n] = part
                end
            end
        end
    
        return t
    end

    function router(routing)
        local routingTree = {}
        local here = {} -- symbol

        for k, v in pairs(routing) do
            local segments = psegments(k)

            local branch = routingTree
            for _, segment in ipairs(segments) do
                local b = branch[segment]
                if not b then
                    b = {}
                    branch[segment] = b
                end

                branch = b
            end

            if branch[here] then
                error("duplication of routes at " .. k)
            end

            branch[here] = v
        end

        return function(context, path, ...)
            if type(path) ~= "string" then
                return context.error("invalid path: " .. tostring(path))
            end

            local segments = psegments(path)
            local branch = routingTree
            local deepestHandler = nil
            local lastIndex = nil
            for i, segment in ipairs(segments) do
                local b = branch[segment]
                if not b then
                    break
                end

                branch = b
                local handler = branch[here]
                if handler then
                    deepestHandler = handler
                    lastIndex = i
                end
            end

            if not deepestHandler then
                return context.error("unknown path segment: " .. tostring(path))
            end

            deepestHandler(context, table.concat(segments, "/", lastIndex + 1), ...)
        end
    end
end

package.loaded["blake"] = {
    startServer = startServer,
    stopServer = stopServer,

    request = request,
    requestSync = requestSync,
    cancelRequest = cancelRequest,
    
    router = router
}