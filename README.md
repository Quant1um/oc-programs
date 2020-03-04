# oc-programs
Just a bunch of random (maybe useful) OpenComputers programs/libraries

## 88_virtualc.lua
**virtualc** is a boot script that allows user to create virtual components that can be used to mimic behaviour of real ones

### Usage
Just copy the file into /boot folder and **virtualc** will be ready to use.

**virtualc** has the following methods available:

 - `virtualc.mount(address:string, descriptor:table)` mounts virtual component at the given address. If address is the same as any real component then virtual component will override real component.
 - `virtualc.u(n)mount(address:string)` unmounts virtual component
 - `virtualc.isVirtual(address:string)` checks whether or not given address corresponds to a virtual component. Returns true if it exists and is virtual.

Virtual component descriptor is a table with following properties:

 - `type`_:string_ Type of the component. Will be returned by `component.type`
 - `invokeMethod`_:function(method:string, ...): ..._ Invokes given method of the component.
 - `getMethods`_:function(): table_ Returns list of all methods that current component has.
 - `getMethodInfo`_:function(method:string): boolean, string_ (optional) Returns info of a given method in `isDirect, documentation` format
 - `createProxy`_:function(): table_ (optional) Creates new proxy table for the component.
 - `getFields` _:function(): table_ (optional) Returns list of all fields that current component has. Used by `component.fields` which is currently undocumented.
 - `getSlot` _:function(): number_ (optional) Returns the slot of the component. Used by `component.slot`

## aa_blake.lua
**blake** is a boot script/protocol used for simple http-like request-response communications. Can be used synchronously and asynchronously.

### Usage
Just copy the file into /boot folder and **blake** will be ready to use.



##### Caveats
 - The library does not do any packet fragmentation so maximum payload size is limited by the server config
 - Error handling in callbacks should be made manually or by listening to `blake_error` event
   (by default all errors get eaten due to how `event.listen` works)

## rubygfx
**rubygfx** is a graphics library with double buffering support

### rgfx.lua
**rgfx** implements ruby's core functions such as memory-efficient buffer (stores single pixel as a single 64-bit number), double-buffering, GPU call batching and color manipulation utils

### xrgfx.lua
**xrgfx** implements auxilary features such as buffer serialization and braille set operations

##### Pros
 - Usage of double-buffering allows for faster drawing in some cases
 - RubyGFX tries to batch adjacent pixels into 1 GPU call to reduce draw times
 - Memory efficient buffer (uses only 16000 bytes for 80x25 screen)

##### Cons
 - Does not support Lua 5.2/JNLua (the library heavily relies on Lua 5.3 integers)
 - Supports only characters in 0 - 65535 unicode range (for now)

## rclib.lua [legacy]
**rclib** is a library for controlling IC2 reactor chambers

## imgview.lua [legacy]
**imgview** is an image viewer of the custom image format