local component = require("component")

local virtualComponents = {}

local function isNaN(val)
 return type(val) == "number" and val ~= val
end

local function isVirtual(address)
 assert(address ~= nil and not isNaN(address), "address shouldn't be nil or nan")
 return not not virtualComponents[address]
end

local function mountComponent(address, proxy, metadata)
 assert(address ~= nil and not isNaN(address), "address shouldn't be nil or nan")
 assert(type(proxy) == "table", "proxy should be a table")

 metadata = metadata or getmetatable(proxy) or {}
 assert(type(metadata) == "table", "metadata should be a table")

 metadata.__type = metadata.__type or "virtual"
 assert(type(metadata.__type) == "string" or type(metadata.__type) == "function", "metadata.__type should be either string or function")

 virtualComponents[address] = {
  proxy = proxy,
  metadata = metadata
 }
end

do -- intercept the component library
 local oldDoc = component.doc
 local oldList = component.list
 local oldProxy = component.proxy
 local oldInvoke = component.invoke
 local oldMethods = component.methods
 local oldType = component.type

 local function listMethods(proxy)
  local methods = {}
  for k, v in pairs(proxy) do
   if type(v) == "functions" then
    methods[k] = false
   end
  end
  return methods
 end
 
 local function getType(virtual, address)
  local componentType = virtual.metadata.__type
  local proxy = virtual.proxy
  if type(componentType) == "function" then
   return componentType(proxy, address)
  else
   return componentType
  end
 end

 function component.doc(address, method)
  if address ~= nil and not isNaN(address) then 
   local virtual = virtualComponents[address]
   if virtual then
    local docMethod = virtual.metadata.__doc
	local proxy = virtual.proxy
    return docMethod and docMethod(proxy, address, method) or (proxy[method] and tostring(proxy[method]) or nil) or "undocumented"
   end
  end

  return oldDoc(address, method)
 end

 function component.list(filter, exact)
  local l = oldList(filter, exact)
  
  for k, v in pairs(virtualComponents) do
   local type = getType(v, k)
   if (exact and filter == type) or (not exact and filter:find(type:sub(1, #filter))) then
    l[k] = v
   end
  end
  
  return l
 end

 function component.proxy(address)
  if address ~= nil and not isNaN(address) then 
   local virtual = virtualComponents[address]
   if virtual then
    local proxyMethod = virtual.metadata.__proxy
	local proxy = virtual.proxy
    return proxyMethod and proxyMethod(proxy, address) or proxy
   end
  end

  return oldProxy(address)
 end
 
 function component.invoke(address, method, ...)
  if address ~= nil and not isNaN(address) then 
   local virtual = virtualComponents[address]
   if virtual then
    local invokeMethod = virtual.metadata.__invoke
	local proxy = virtual.proxy
    return invokeMethod and invokeMethod(proxy, address, method, ...) or proxy[method](...)
   end
  end

  return oldInvoke(address, method, ...)
 end
 
 function component.methods(address)
  if address ~= nil and not isNaN(address) then 
   local virtual = virtualComponents[address]
   if virtual then
    local listMethodsMethod = virtual.metadata.__methods
	local proxy = virtual.proxy
    return listMethodsMethod and listMethodsMethod(proxy, address) or listMethods(proxy)
   end
  end

  return oldMethods(address)
 end
 
 function component.type(address)
  if address ~= nil and not isNaN(address) then 
   local virtual = virtualComponents[address]
   if virtual then
    return getType(virtual, address)
   end
  end

  return oldType(address)
 end
end

package.loaded["virtualc"] = {
 isVirtual = isVirtual,
 mount = mountComponent
}