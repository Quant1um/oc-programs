local colorlib = {}
do -- colorlib
    local floor = math.floor

    local BYTE_MASK = 0xFF
    local NO_LSB_MASK = 0xFEFEFE

    local SPLIT2_MASK = 0xFF00FF
    local COMBINE2_MASK = 0xFF00FF00

    local function pack(r, g, b)
        return b | g << 8 | r << 16
    end

    local function unpack(rgb)
        return (rgb << 16) & BYTE_MASK,
               (rgb << 8 ) & BYTE_MASK,
               (rgb      ) & BYTE_MASK
    end

    colorlib.pack = pack
    colorlib.unpack = unpack

    function colorlib.blend(a, b, t)
        if t <= 0 then return a
        elseif t < 1 then
            t = floor(t * 255)

            local rb0 = a & SPLIT2_MASK
            local rb1 = b & SPLIT2_MASK
            local g0 = (a >> 8) & SPLIT2_MASK
            local g1 = (b >> 8) & SPLIT2_MASK
            local s = 256 - t

            local rb = rb1 * t + rb0 * s
            local g = g1 * t + g0 * s

            return ((rb & COMBINE2_MASK) >> 8) | (g & COMBINE2_MASK)
        else return b end
    end

    function colorlib.add(a, b)
        local sum = (a & NO_LSB_MASK) + (b & NO_LSB_MASK)
        return sum | (((sum >> 8) & 0x101010) * 0xFF)
    end

    function colorlib.invert(c)
        return 0xFFFFFF ^ c
    end
end

local scode = utf8.codepoint
local schar = utf8.char

local EMPTY_CHAR = " "
local EMPTY_CHAR_CODE = scode(EMPTY_CHAR)

local function dpack(char, fore, back)
    return (scode(char) & 0xFFFF) | (fore << 16) | (back << 40)
end

local function dsetc(p, char)
    return (p & ~0xFFFF) | (scode(char) & 0xFFFF)
end

local function dsetf(p, fore)
    return (p & ~0xFFFFFF0000) | (fore << 16)
end

local function dsetb(p, back)
    return (p & 0xFFFFFFFFFF) | (back << 40)
end

local function dunpack(packed)
    local cp = packed & 0xFFFF
    local fc = packed >> 16 & 0xFFFFFF
    local bc = packed >> 40 & 0xFFFFFF
    local c = schar(cp)

    return c, fc, bc
end

local function dunpacki(packed)
    return packed & 0xFFFF
end

local function dunpackc(packed)
    return schar(packed & 0xFFFF)
end

local function dunpackf(packed)
    return packed >> 16 & 0xFFFFFF
end

local function dunpackb(packed)
    return packed >> 40 & 0xFFFFFF
end

local function dunpackfb(packed)
    return packed >> 16
end

local storage = {
    pack = dpack,
    unpack = dunpack,

    dsetc = dsetc,
    dsetb = dsetb,
    dsetf = dsetf,

    unpackc = dunpackc,
    unpacki = dunpacki,
    unpackf = dunpackf,
    unpackb = dunpackb,
    unpackfb = dunpackfb
}

local buffer = {}
do -- buffer
    local mt = {}

    function buffer.create(w, h)
        return buffer.clear(setmetatable({ w = tonumber(w) or 0, h = tonumber(h) or 0 }, mt)) 
    end

    function buffer.clone(buf)
        local w, h = buf.w, buf.h
        local new = { w = w, h = h }

        local n = w * h
        for i = 1, n do
            new[i] = buf[i]
        end

        return new
    end

    function buffer.resize(buf, w, h)
        if buf.w == w and buf.h == h then return buf end
        buf.w = w
        buf.h = h
        return buffer.clear(buf) 
    end

    function buffer.clear(buf)
        return buffer.fill(buf, EMPTY_CHAR, 0, 0)
    end

    function buffer.fill(buf, char, front, back)
        local packed = dpack(char, front, back)

        local n = buf.w * buf.h
        for i = 1, n do
            buf[i] = packed
        end

        return buf
    end

    function buffer.set(buf, x, y, char, front, back)
        local w, h = buf.w, buf.h
        if x < 1 or y < 1 or x > w or y > h then return buf end

        local i = x + y * w - w
        buf[i] = dpack(char, front, back)
        return buf
    end

    function buffer.setBack(buf, x, y, back)
        local w, h = buf.w, buf.h
        if x < 1 or y < 1 or x > w or y > h then return buf end

        local i = x + y * w - w
        buf[i] = dsetb(buf[i], back)
        return buf
    end

    function buffer.setFore(buf, x, y, fore)
        local w, h = buf.w, buf.h
        if x < 1 or y < 1 or x > w or y > h then return buf end

        local i = x + y * w - w
        buf[i] = dsetf(buf[i], fore)
        return buf
    end

    function buffer.setChar(buf, x, y, char)
        local w, h = buf.w, buf.h
        if x < 1 or y < 1 or x > w or y > h then return buf end

        local i = x + y * w - w
        buf[i] = dsetc(buf[i], char)
        return buf
    end

    function buffer.get(buf, x, y)
        local w, h = buf.w, buf.h
        if x < 1 or y < 1 or x > w or y > h then return EMPTY_CHAR, 0, 0 end

        local i = x + y * w - w
        return dunpack(buf[i])
    end

    function buffer.copy(src, dest, x0, y0, x1, y1, w, h)
        -- fix the bounds
        local w0, h0, w1, h1 = src.w, src.h, dest.w, dest.h

        if x0 < 1 then 
            local delta = 1 - x0
            x0, x1, w = 1, x1 + delta, w - delta
        end

        if x1 < 1 then 
            local delta = 1 - x1
            x1, x0, w = 1, x0 + delta, w - delta
        end

        if y0 < 1 then 
            local delta = 1 - y0
            y0, y1, h = 1, y1 + delta, h - delta
        end

        if y1 < 1 then 
            local delta = 1 - y0
            y1, y0, h = 1, y0 + delta, h - delta
        end

        if x0 > w0 or y0 > h0 or x1 > w1 or y1 > h1 then return x0, y0, x1, y1, 0, 0 end

        local fx0 = w0 - x0 + w - 1
        if fx0 < 0 then w = w - fx0 end

        local fx1 = w1 - x1 + w - 1
        if fx1 < 0 then w = w - fx1 end

        local fy0 = h0 - y0 + h - 1
        if fy0 < 0 then h = h - fy0 end

        local fy1 = h1 - y1 + h - 1
        if fy1 < 0 then h = h - fy1 end

        if w < 1 or h < 1 then return src, buf end

        local i0 = x0 + y0 * w0 - w0
        local i1 = x1 + y1 * w1 - w1

        for j = 1, h do
            for i = 0, w - 1 do
                src[i0 + i]     = dest[i1 + i]
                src[i0 + i + 1] = dest[i1 + i + 1]
            end

            i0 = i0 + w0
            i1 = i1 + w1
        end

        return x0, y0, x1, y1, w, h
    end

    mt.__index = {
        clone = buffer.clone,
        set = buffer.set,
        get = buffer.get,
        fill = buffer.fill,
        clear = buffer.clear,
        resize = buffer.resize
    }
end

local flush2b
do -- doublebuffering
    local concat = table.concat

    local function pcmp(p0, p1)
        if p0 == p1 then return true end

        local d0, d1 = dunpacki(p0), dunpacki(p1)
        if d0 ~= d1 then return false end
        if d0 == EMPTY_CHAR_CODE then return dunpackb(p0) == dunpackb(p1) end
        return false
    end
    
    local function pcmpi(p0, p1)
        if p0 == p1 then return true end

        local d0, d1 = dunpacki(p0), dunpacki(p1)
        if d0 == EMPTY_CHAR_CODE and d1 == EMPTY_CHAR_CODE then return dunpackb(p0) == dunpackb(p1) end
        return dunpackfb(p0) == dunpackfb(p1)
    end
    
    -- returns: width, height, operation (0 - fill, 1 - set, 2 - set vertical)
    local function optimizeDrawcall(p, x, y, w, h, front, back)
        local seth = 1
        local setv = 1
        local fillx = 1
        local filly = 1
        
        -- finding scores (area of draw call)
        local i0 = x + y * w - w
        for x1 = 1, w - x do
            local i1 = i0 + x1
            local p0 = front[i1]
            if pcmp(p0, back[i1]) then break end
            
            if fillx == seth and pcmp(p, p0) then 
                fillx = fillx + 1 
                seth = seth + 1
            elseif pcmpi(p, p0) then
                seth = seth + 1
            else 
                break
            end
        end
    
        local rowXDiff = fillx - 1
        for y1 = 1, h - y do
            local i1 = i0 + y1 * w
            local p0 = front[i1]
            if pcmp(p0, back[i1]) then break end
        
            if filly == setv and pcmp(p, p0) then 
                setv = setv + 1
            
                local valid = true
                for x1 = 0, rowXDiff do
                    local p1 = front[i1 + x1]
                    if not pcmp(p, p1) then
                        valid = false
                        break
                    end
                end
            
                if valid then 
                    filly = filly + 1 
                end
            elseif pcmpi(p, p0) then
                setv = setv + 1
            else
                break
            end
        end
    
        -- finding optimal drawcall using previously calculated scores
        -- multiplying set scores by 2 because set operations is generally twice as cheap as filling
        local fillScore = fillx * filly
        local sethScore = seth * 2
        local setvScore = setv * 2

        if fillScore > sethScore then
            if fillScore > setvScore then
                return fillx, filly, 0
            else
                return 1, setv, 2
            end
        else
            if sethScore >= setvScore then
                return seth, 1, 1
            else
                return 1, setv, 2
            end
        end
    end
    
    function flush2b(gpu, front, back, x, y, w, h)
        local dw, dh = gpu.getResolution()

        if front.w ~= dw or front.h ~= dh or back.w ~= dw or back.h ~= dh then
            gpu.setBackground(0x000000)
            gpu.setForeground(0x000000)    

            buffer.resize(front, dw, dh)
            buffer.resize(back, dw, dh)
            gpu.fill(1, 1, dw, dh, " ")

            return 1, dw * dh
        end

        local bck, bckp = gpu.getBackground()
        local fore, forep = gpu.getForeground()
        if bckp then
            bck = gpu.getPaletteColor(bck)
        end

        if forep then
            fore = gpu.getPaletteColor(fore)
        end

        x = math.max(x or 1, 1) 
        y = math.max(y or 1, 1)
        w = math.min(w or dw, dw - x)
        h = math.min(h or dh, dh - y)

        if w <= 0 or y <= 0 then return 0, 0 end
        
        local drawcalls, area = 0, 0
        local forecolor, backcolor = fore, bck
        local charbuf = {}

        local df = {}

        for j = y, y + h do
            local i0 = j * dw - dw
            for i = x, x + w do
                local i1 = i0 + i
                local p = front[i1]

                if not pcmp(p, back[i1]) then
                    local ow, oh, op = optimizeDrawcall(p, i, j, dw, dh, front, back)
                    local ch, f1, b1 = dunpack(p)

                    if backcolor ~= b1 then 
                        gpu.setBackground(b1)
                        backcolor = b1
                    end
                
                    if (ch ~= EMPTY_CHAR or op ~= 0) and forecolor ~= f1 then
                        gpu.setForeground(f1)
                        forecolor = f1
                    end

                    if op == 0 then
                        gpu.fill(i, j, ow, oh, ch)

                        for hj = 0, oh - 1 do
                            local i2 = i1 + hj * dw
                            for hi = 0, ow - 1 do 
                                back[i2 + hi] = p
                            end
                        end
                    elseif op == 1 then
                        local i2 = i1 - 1

                        back[i1] = p
                        charbuf[1] = ch

                        for hi = 2, ow do
                            local i3 = i2 + hi
                            local p0 = front[i3]

                            back[i3] = p0
                            charbuf[hi] = dunpackc(p0)
                        end
                       
                        gpu.set(i, j, concat(charbuf, nil, 1, ow))
                    elseif op == 2 then
                        local i2 = i1 - dw

                        back[i1] = p
                        charbuf[1] = ch

                        for hj = 2, oh do
                            local i3 = i2 + hj * dw
                            local p0 = front[i3]

                            back[i3] = p0
                            charbuf[hj] = dunpackc(p0)
                        end

                        gpu.set(i, j, concat(charbuf, nil, 1, oh), true)
                    end

                    drawcalls = drawcalls + 1
                    area = area + ow * oh
                end
            end
        end

        return drawcalls, area
    end
end

return {
    storage = storage,
    buffer = buffer,
    color = colorlib,
    flush2b = flush2b
}