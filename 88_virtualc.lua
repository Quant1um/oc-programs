local component = component or require("component")
local computer = computer or require("computer")
 
local pairs = pairs
local getmetatable = getmetatable
local type = type
 
local function getmetaprop(table, prop)
 local metatable = getmetatable(table)
 if type(metatable) == "table" then return rawget(metatable, prop) end
 return nil
end
 
local function isNaN(val)
 return type(val) == "number" and val ~= val
end
 
local virtualComponents = {}
 
local function getType(virtual, address)
 local componentType = getmetaprop(virtual, "__type")
 if type(componentType) == "function" then
  return componentType(virtual, address)
 elseif componentType == nil then
  return "virtual"
 else
  return tostring(componentType)
 end
end
 
local function isVirtual(address)
 assert(address ~= nil and not isNaN(address), "address shouldn't be nil or nan")
 return not not virtualComponents[address]
end
 
local function mountComponent(address, proxy)
 assert(address ~= nil and not isNaN(address), "address shouldn't be nil or nan")
 assert(type(proxy) == "table", "proxy should be a table")
 assert(not component.proxy(address), "component with given address already attached")
 
 virtualComponents[address] = proxy
 computer.pushSignal("component_added", address, getType(proxy, address))
end
 
local function unmountComponent(address)
 assert(address ~= nil and not isNaN(address), "address shouldn't be nil or nan")
 assert(isVirtual(address), "address should point to virtual component")
 
 virtualComponents[address] = nil
 computer.pushSignal("component_removed", address, getType(proxy, address))
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
   local metaDoc = getmetaprop(virtual, "__doc")
   local metaDocType = type(metaDoc)
   if metaDocType == "function" then
    return metaDoc(virtual, address, method)
   elseif metaDocType == "table" then
    local doc = metaDoc[method]
    if doc then return doc end
    return nil
   else
    local method = virtual[method]
    if method then return tostring(method) end
    return nil
   end
  end
 
  return oldDoc(address, method)
 end
 
 function component.list(filter, exact)
  local l = oldList(filter, exact)
 
  for k, v in pairs(virtualComponents) do
   local type = getType(v, k)
   if not filter or (exact and filter == type) or (not exact and filter:find(type:sub(1, #filter))) then
    l[k] = type
   end
  end
 
  return l
 end
 
 function component.proxy(address)
  local virtual = virtualComponents[address]
  if virtual then
   local metaProxy = getmetaprop(virtual, "__proxy")
   local metaProxyType = type(metaProxy)
   
   if metaProxyType == "table" then return metaProxy end
   if metaProxyType == "function" then return metaProxy(virtual, address) end
   return virtual
  end
 
  return oldProxy(address)
 end
 
 function component.invoke(address, method, ...)
  local virtual = virtualComponents[address]
  if virtual then
   local metaInvoke = getmetaprop(virtual, "__invoke")
   
   if type(metaInvoke) == "function" then return invokeMethod(virtual, address, method, ...) end
   
   local vmethod = virtual[method]
   if vmethod then return vmethod(...) end
   error("no such method")  
  end
 
  return oldInvoke(address, method, ...)
 end
 
 function component.methods(address)
  local virtual = virtualComponents[address]
  if virtual then
   local metaMethods = getmetaprop(virtual, "__methods")
   local metaMethodsType = type(metaMethods)
   
   if metaMethodsType == "function" then return metaMethods(virtual, address) end
   if metaMethodsType == "table" then return metaMethods end
   
   local methods = {}
   for k, v in pairs(virtual) do
    if type(v) == "function" then
     methods[k] = true
    end
   end
   return methods
  end
 
  return oldMethods(address)
 end
 
 function component.fields(address)
  local virtual = virtualComponents[address]
  if virtual then
   local metaFields = getmetaprop(virtual, "__fields")
   local metaFieldsType = type(metaFields)
   
   if metaFieldsType == "function" then return metaFields(virtual, address) end
   if metaFieldsType == "table" then return metaFields end
   
   local fields = {}
   for k, v in pairs(virtual) do
    if type(v) ~= "function" then
     fields[k] = true
    end
   end
   return fields
  end
 
  return oldFields(address)
 end
 
 function component.slot(address)
  local virtual = virtualComponents[address]
  if virtual then
   local metaSlot = getmetaprop(virtual, "__slot")
   if type(metaSlot) == "function" then
    return metaSlot(virtual, address)
   elseif metaSlot == nil then
    return -1
   else
    return metaSlot
   end  
  end
 
  return oldSlot(address)
 end
 
 function component.type(address)
  local virtual = virtualComponents[address]
  if virtual then
   return getType(virtual, address)
  end
 
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
