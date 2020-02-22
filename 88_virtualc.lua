local component = component or require("component")
local computer = computer or require("computer")

local pairs = pairs
local getmetatable = getmetatable
local type = type
local rawget = rawget

local function checkType(val, ...)
    local valType = type(val)
    for _, t in pairs({...}) do if valType == t then return true end end
    return false
end

local virtualComponents = {}
local virtualProxies = {}

local function isVirtual(address)
    checkArg(1, address, "string")
    return not not virtualComponents[address]
end

local defaultGetMethodInfo = function() return true, "function(...): ... -- undocumented" end
local defaultGetFields = function() return {} end
local defaultGetSlot = function() return -1 end

local defaultCreateProxy = function(desc)
    local proxy = {}

    local mtMethod = {
        __call = function(self, ...)
            return desc:invokeMethod(self.name, ...)
        end,

        __tostring = function(self, ...)
            local _, doc = desc:getMethodInfo(self.name)
            return tostring(doc)
        end
    }    

    proxy.slot = desc:getSlot()
    proxy.type = desc.type
    proxy.address = desc.address

    for _, method in pairs(desc:getMethods()) do
        proxy[method] = setmetatable({ address = desc.address, name = method }, mtMethod)
    end

    return proxy
end

local function mountComponent(address, descriptor)
    checkArg(1, address, "string")
    checkArg(2, descriptor, "table")

    assert(checkType(descriptor.type, "string"),
           "invalid descriptor: type must be a string")
    assert(checkType(descriptor.createProxy, "function", "nil"),
           "invalid descriptor: createProxy must be a function or nil")
    assert(checkType(descriptor.invokeMethod, "function"),
           "invalid descriptor: invokeMethod must be a function")
    assert(checkType(descriptor.getMethodInfo, "function", "nil"),
           "invalid descriptor: getMethodInfo must be a function or nil")
    assert(checkType(descriptor.getMethods, "function"),
           "invalid descriptor: getMethods must be a function")
    assert(checkType(descriptor.getFields, "function", "nil"),
           "invalid descriptor: getFields must be a function or nil")
    assert(checkType(descriptor.getSlot, "function", "nil"),
           "invalid descriptor: getSlot must be a function or nil")

    assert(not component.proxy(address),
           "component with given address is already attached")

    descriptor.address = address
    descriptor.getMethodInfo = descriptor.getMethodInfo or defaultGetMethodInfo
    descriptor.getFields = descriptor.getFields or defaultGetFields
    descriptor.getSlot = descriptor.getSlot or defaultGetSlot
    descriptor.createProxy = descriptor.createProxy or defaultCreateProxy

    virtualComponents[address] = descriptor
    computer.pushSignal("component_added", address, descriptor.type)
end

local function unmountComponent(address)
    checkArg(1, address, "string")
    assert(isVirtual(address), "address should point to a virtual component")

    local descType = virtualComponents[address].type
    virtualComponents[address] = nil
    virtualProxies[address] = nil
    computer.pushSignal("component_removed", address, descType)
end

local function getDescriptor(address)
    checkArg(1, address, "string")
    assert(isVirtual(address), "address should point to a virtual component")

    return virtualComponents[address]
end

local oldComponent
do -- intercept the component library
    local oldDoc = component.doc
    local oldList = component.list
    local oldProxy = component.proxy
    local oldInvoke = component.invoke
    local oldMethods = component.methods
    local oldFields = component.fields
    local oldSlot = component.slot
    local oldType = component.type

    local oldComponent = {
        doc = oldDoc,
        list = oldList,
        proxy = oldProxy,
        invoke = oldInvoke,
        methods = oldMethods,
        fields = oldFields,
        slot = oldSlot,
        type = oldType
    }

    function component.doc(address, method)
        local virtual = virtualComponents[address]
        if virtual then
            local direct, doc = virtual:getMethodInfo(method)
            return doc
        end

        return oldDoc(address, method)
    end

    function component.list(filter, exact)
        local l = oldList(filter, exact)

        for k, v in pairs(virtualComponents) do
            local type = v.type
            if not filter or (exact and filter == type) or
                (not exact and filter:find(type:sub(1, #filter))) then
                l[k] = type
            end
        end

        return l
    end

    function component.proxy(address)
        local virtual = virtualComponents[address]
        if virtual then
            local proxy = virtualProxies[address]
            if not proxy then
                proxy = virtual:createProxy()
                virtualProxies[address] = proxy
            end
            return proxy
        end

        return oldProxy(address)
    end

    function component.invoke(address, method, ...)
        local virtual = virtualComponents[address]
        if virtual then return virtual:invokeMethod(method, ...) end

        return oldInvoke(address, method, ...)
    end

    function component.methods(address)
        local virtual = virtualComponents[address]
        if virtual then
            local methods = {}
            for _, method in pairs(virtual:getMethods()) do
                local direct, doc = virtual:getMethodInfo(method)
                methods[method] = direct
            end
            return methods
        end

        return oldMethods(address)
    end

    function component.fields(address)
        local virtual = virtualComponents[address]
        if virtual then return virtual:getFields() end

        return oldFields(address)
    end

    function component.slot(address)
        local virtual = virtualComponents[address]
        if virtual then return virtual:getSlot() end

        return oldSlot(address)
    end

    function component.type(address)
        local virtual = virtualComponents[address]
        if virtual then return virtual.type end

        return oldType(address)
    end
end

package.loaded["virtualc"] = {
    isVirtual = isVirtual,
    mount = mountComponent,
    unmount = unmountComponent,
    umount = unmountComponent,

    component = oldComponent
}