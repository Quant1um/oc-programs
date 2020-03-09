local rgfx = require("rgfx")

local sbyte, schar = string.byte, string.char

local serialize, deserialize, write, read
do
    local function int2str(n)
        return schar(n & 0xFF, 
                     n >> 8 & 0xFF, 
                     n >> 16 & 0xFF, 
                     n >> 24 & 0xFF, 
                     n >> 32 & 0xFF, 
                     n >> 40 & 0xFF, 
                     n >> 48 & 0xFF,
                     n >> 56 & 0xFF)
    end

    local function str2int(s)
        local b0, b1, b2, b3, b4, b5, b6, b7 = sbyte(s, 1, 8)
        if not (b0 and b1 and b2 and b3 and b4 and b5 and b6 and b7) then return false end
        return b0 | b1 << 8 | b2 << 16 | b3 << 24 | b4 << 32 | b5 << 40 | b6 << 48 | b7 << 56
    end

    function serialize(buffer, stream)
        stream:write("\0rubygfx")
        stream:write(int2str(buffer.w))
        stream:write(int2str(buffer.h))

        local n = buffer.w * buffer.h
        for i = 1, n do
            stream:write(int2str(buffer[i]))
        end
    end

    function deserialize(stream)
        if stream:read(8) ~= "\0rubygfx" then
            return nil, "invalid header"
        end

        local w = str2int(stream:read(8))
        local h = str2int(stream:read(8))

        if not w or not h or w < 0 or h < 0 then
            return nil, "invalid metadata"
        end

        local buffer = rgfx.buffer.create(w, h)

        local n = w * h
        for i = 1, n do
            local px = str2int(stream:read(8))
            if not px then
                return nil, "unexpected eof at " .. i
            end

            buffer[i] = px 
        end

        return buffer
    end

    function write(buffer, file)
        local stream = io.open(file, "wb")
        serialize(buffer, stream)
        stream:close()
    end

    function read(file)
        local stream = io.open(file, "rb")
        local result, err = deserialize(stream)
        stream:close()
        return result, err
    end
end

local bset1, bset2
do
    function bset1(buf, i, j, c)
        i, j = i - 1, j - 1
        local x = (i >> 1) + 1
        local y = (j >> 2) + 1

        local w, h = buf.w, buf.h
        if x < 1 or y < 1 or x > w or y > h then return buf end

        local a = i & 1
        local b = j & 3
        
        local bcode
        if b == 3 then bcode = a | 6
        else bcode = b + a * 3 end 

        local i = x + y * w - w

        local v = buf[i]
        if (v & 0xff00) ~= 0x2800 then
            v = v & ~0xffff | 0x2800
        end

        if c ~= nil then
            v = (v & ~0xFFFFFF0000) | (c << 16)
        end

        buf[i] = v | (1 << bcode)
        return buf
    end

    function bset2(buf, i, j, c)
        i, j = i - 1, j - 1
        local x = (i >> 1) + 1
        local y = (j >> 2) + 1

        local w, h = buf.w, buf.h
        if x < 1 or y < 1 or x > w or y > h then return buf end

        local a = i & 1
        local b = j & 3
        
        local bcode
        if b == 3 then bcode = a | 6
        else bcode = b + a * 3 end 

        local i = x + y * w - w

        local v = buf[i]
        if (v & 0xff00) ~= 0x2800 then
            v = v & ~0xffff | 0x28ff
        end

        if c ~= nil then
            v = (v & 0xFFFFFFFFFF) | (c << 40)
        end

        buf[i] = v & ~(1 << bcode)
        return buf
    end
end

return {
    serialize = serialize,
    deserialize = deserialize,
    read = read,
    write = write,

    bset1 = bset1,
    bset2 = bset2
}