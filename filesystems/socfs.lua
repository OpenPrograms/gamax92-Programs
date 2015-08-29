--[[
Simple OpenComputers FileSystem.
Refer to socfs.txt for details

This is probably not the best implementation that there could be. But the style
of the index area makes it so I have to cache and generate representions out of
it so that I'm not looping through the entire index every time.
--]]
local vcomp = require("vcomponent")
local fs = require("filesystem")
local io = require("io")
local fslib = require("fslib")

local socfs = {}
local _socfs = {}

local function dprint(...)
    print("[socfs] " .. select(1, ...), select(2, ...))
end

function _socfs.readStr(str)
    return (str .. "\0"):match("(.-)\0")
end

function _socfs.vfs2index(socdat, path)
    local parent, name = fslib.getParent(path), fs.name(path)
    local dir = socdat.vfs[parent]
    if dir == nil then return end
    for i = 1, #dir do
        if dir[i][2] == name then
            return socdat.index[dir[i][1]]
        end
    end
end

function _socfs.writeIndex(socdat, index)
    -- TODO: Implement
    -- Note: Cache/Queue?
end

function _socfs.findFreeIndex(socdat)
    local free
    for i = 1, socdat.indexcount do
        local type = socdat.index[i].type
        if type == 0x00 or type == 0x18 or type == 0x19 or type == 0x1A then
            free = i
            break
        end
    end
    if free ~= nil then
        return free
    end
    -- Try to expand index area
    if (socdat.reserve+socdat.datasize)*socdat.blocksize+socdat.indexsize+64 <= socdat.total*socdat.blocksize then
        socdat.indexcount = socdat.indexcount + 1
        socdat.indexsize = socdat.indexsize + 64
        socdat.index[socdat.indexcount] = socdat.index[socdat.indexcount-1]
        socdat.index[socdat.indexcount-1] = {type=0}
        _socfs.writeIndex(socdat, socdat.indexcount)
        _socfs.writeIndex(socdat, socdat.indexcount-1)
        return socdat.indexcount-1
    end
end

function socfs.proxy(socfile)
    checkArg(1, socfile, "string")

    if not fs.exists(socfile) then
        error("No such file", 2)
    end
    local file = io.open(socfile, "rb")
    if file == nil then
        error("Failed to open file")
    end
    local pos, err = file:seek("set", 0x36)
    if pos == nil then
        error("Seeking failed: " .. err)
    end

    local socdat = {}
    file:seek("set", 0x194)
    local superblock = fslib.readRawString(file, 41)
    socdat.modtime   = fslib.str2num(superblock:sub(0x01, 0x08))
    socdat.datasize  = fslib.str2num(superblock:sub(0x09, 0x10))
    socdat.indexsize = fslib.str2num(superblock:sub(0x11, 0x18))
    socdat.magic     = fslib.str2num(superblock:sub(0x19, 0x1B))
    socdat.version   = fslib.str2num(superblock:sub(0x1C, 0x1C))
    socdat.total     = fslib.str2num(superblock:sub(0x1D, 0x24))
    socdat.reserve   = fslib.str2num(superblock:sub(0x25, 0x28))
    socdat.logblock  = fslib.str2num(superblock:sub(0x29, 0x29))

    socdat.filesize   = fs.size(socfile)
    socdat.blocksize  = 2^(socdat.logblock+7)
    socdat.indexcount = socdat.indexsize/64
    superblock = nil

    if socdat.magic ~= 0x434F53 then
        error("SOCFS filesystem not detected")
    elseif socdat.version ~= 0x10 then
        error(string.format("Unknown SOCFS version: %d.%02d", math.floor(socdat.version/16), socdat.version%16))
    elseif socdat.indexsize%64 ~= 0 then
        error("Index Area is not a multiple of 64")
    end

    if socdat.total*socdat.blocksize ~= socdat.filesize then
        dprint("Warning: Size of filesystem differs from media size")
        dprint(socdat.total*socdat.blocksize, socdat.filesize)
        socdat.total = math.min(socdat.total, math.floor(socdat.filesize/socdat.blocksize))
        dprint("New size: " .. socdat.total*socdat.blocksize)
    end

    if socdat.datasize > socdat.total then
        error("Size of data area is larger than the filesystem")
    elseif socdat.indexsize > socdat.total*socdat.blocksize then
        error("Size of index area is larger than the filesystem")
    elseif socdat.reserve > socdat.total then
        error("Size of reserved area is larger than the filesystem")
    elseif (socdat.reserve+socdat.datasize)*socdat.blocksize+socdat.indexsize > socdat.total*socdat.blocksize then
        error("Size of all areas are larger than the filesystem")
    end

    local proxyObj = {}

    -- Cache the Index Area
    socdat.index = {}
    file:seek("set", socdat.total*socdat.blocksize - socdat.indexsize)
    local indexdata = fslib.readRawString(file, socdat.indexsize)
    for i = 1, socdat.indexcount do
        local entrydat = indexdata:sub(socdat.indexsize-i*64+1, socdat.indexsize-i*64+64)
        local entry = {type = entrydat:byte(1, 1)}
        if entry.type == 0x00 or entry.type == 0x02 then
        elseif entry.type == 0x01 then
            entry.time = fslib.str2num(entrydat:sub(0x02, 0x09))
            local uuid = entrydat:sub(0x0A, 0x19):gsub(".", function(a) return string.format("%02x", a:byte()) end)
            entry.uuid = uuid:sub(1, 8) .. "-" .. uuid:sub(9, 12) .. "-" .. uuid:sub(13, 16) .. "-" .. uuid:sub(17, 20) .. "-" .. uuid:sub(21, 32)
            proxyObj.address = entry.uuid
            entry.label = _socfs.readStr(entrydat:sub(0x1A))
        elseif entry.type == 0x10 or entry.type == 0x18 then
            entry.part = _socfs.readStr(entrydat:sub(0x02, 0x3C))
            entry.next = fslib.str2num(entrydat:sub(0x3D, 0x40))
        elseif entry.type == 0x11 or entry.type == 0x19 then
            entry.next = fslib.str2num(entrydat:sub(0x02, 0x05))
            entry.time = fslib.str2num(entrydat:sub(0x06, 0x0D))
            entry.part = _socfs.readStr(entrydat:sub(0x0E))
        elseif entry.type == 0x12 or entry.type == 0x1A then
            entry.next = fslib.str2num(entrydat:sub(0x02, 0x05))
            entry.time = fslib.str2num(entrydat:sub(0x06, 0x0D))
            entry.block = fslib.str2num(entrydat:sub(0x0E, 0x15))
            entry.length = fslib.str2num(entrydat:sub(0x16, 0x1D))
            entry.part = _socfs.readStr(entrydat:sub(0x1E))
        elseif entry.type == 0x17 then
            entry.start = fslib.str2num(entrydat:sub(0x0B, 0x12))
            entry.last = fslib.str2num(entrydat:sub(0x13, 0x1A))
        else
            error(string.format("Index " .. i .. " has unknown type: 0x%02X", entry.type))
        end
        socdat.index[i] = entry
    end
    indexdata = nil
    if socdat.index[1].type ~= 0x01 then
        error("First Index Entry not Volume Entry")
    elseif socdat.index[socdat.indexcount].type ~= 0x02 then
        error("Last Index Entry not Starting Marker Entry")
    end
    for i = 1, socdat.indexcount do
        local entry = socdat.index[i]
        if entry.type == 0x11 or entry.type == 0x12 then
            entry.name = entry.part
            local next = entry.next
            while next ~= 0 do
                if socdat.index[next].type ~= 0x10 then
                    error("Continuation chain points to " .. (socdat.index[next].type == 0x18 and "Deleted" or "non") .. " Continuation Entry")
                end
                entry.name = entry.name .. socdat.index[next].part
                next = socdat.index[next].next
            end
            entry.name = fslib.cleanPath(entry.name)
            if entry.name == "" then
                error("Index " .. i .. " has an empty name")
            end
        end
    end

    -- Build a VFS representation
    socdat.vfs = {[""]={}}
    for i = 1, socdat.indexcount do
        local entry = socdat.index[i]
        if entry.type == 0x11 then
            if socdat.vfs[entry.name] == nil then
                socdat.vfs[entry.name] = {}
            end
        elseif entry.type == 0x12 then
            local parent = fslib.getParent(entry.name)
            if socdat.vfs[parent] == nil then
                socdat.vfs[parent] = {}
            end
        end
    end
    for i = 1, socdat.indexcount do
        local entry = socdat.index[i]
        if entry.type == 0x11 or entry.type == 0x12 then
            local parent = fslib.getParent(entry.name)
            table.insert(socdat.vfs[parent], {i, fs.name(entry.name)})
        end
    end

    local handlelist = {}

    proxyObj.type = "filesystem"
    function proxyObj.isReadOnly()
        return fs.get(socfile).isReadOnly()
    end
    function proxyObj.spaceUsed()
        local used = 0
        for i = 1, socdat.indexcount do
            local entry = socdat.index[i]
            if entry.type ~= 0 and entry.type ~= 0x18 and entry.type ~= 0x19 and entry.type ~= 0x1A then
                used = used + 64
                if entry.type == 0x12 then
                    used = used + math.ceil(entry.length/socdat.blocksize)*socdat.blocksize
                end
            end
        end
        return socdat.reserve*socdat.blocksize + used
    end
    function proxyObj.spaceTotal()
        return socdat.total*socdat.blocksize
    end
    function proxyObj.getLabel()
        return socdat.index[1].label
    end
    function proxyObj.setLabel(value)
        checkArg(1, value, "string")
        socdat.index[1].label = value:sub(1, 39)
        _socfs.writeIndex(socdat, 1)
    end

    function proxyObj.list(path)
        checkArg(1, path, "string")
        path = fslib.cleanPath(path)
        local dir = socdat.vfs[path]
        if dir == nil then
            return nil, "no such file or directory"
        end
        local list = {}
        for i = 1, #dir do
            if socdat.index[dir[i][1]].type == 0x11 then
                list[#list + 1] = dir[i][2] .. "/"
            else
                list[#list + 1] = dir[i][2]
            end
        end
        list.n = #list
        return list
    end
    function proxyObj.exists(path)
        checkArg(1, path, "string")
        return _socfs.vfs2index(socdat, fslib.cleanPath(path)) ~= nil
    end
    function proxyObj.isDirectory(path)
        checkArg(1, path, "string")
        return socdat.vfs[fslib.cleanPath(path)] ~= nil
    end
    function proxyObj.size(path)
        checkArg(1, path, "string")
        local index = _socfs.vfs2index(socdat, fslib.cleanPath(path))
        if index == nil or (index.type ~= 0x12 and index.type ~= 0x1A) then
            return 0
        end
        return index.length
    end
    function proxyObj.lastModified(path)
        checkArg(1, path, "string")
        path = fslib.cleanPath(path)
        local index = _socfs.vfs2index(socdat, fslib.cleanPath(path))
        if index == nil then
            return 0
        end
        return index.time*1000
    end

    function proxyObj.makeDirectory(path)
        -- TODO: Recursive
        checkArg(1, path, "string")
        path = fslib.cleanPath(path)
        local parent = fslib.getParent(path)
        if socdat.vfs[path] ~= nil then
            return false
        end
        -- TODO: Remove when recursive is supported:
        if socdat.vfs[parent] == nil then
            return false
        end
        local icount = math.ceil((#path-51)/59)+1
        local ilist = {}
        for i = 1, icount do
            ilist[i] = _socfs.findFreeIndex(socdat)
            if ilist[i] == nil then
                return nil, "not enough space"
            end
        end
        socdat.index[ilist[1]] = {
            type = 0x11,
            next = ilist[2] or 0,
            time = os.time(),
            part = path:sub(1, 51),
            name = path,
        }
        for i = 2, icount do
            socdat.index[ilist[i]] = {
                type = 0x10,
                part = path:sub((i-1)*59-7, (i-1)*59+51),
                next = ilist[i+1] or 0,
            }
        end
        for i = 1, icount do
            _socfs.writeIndex(socdat, ilist[i])
        end
        socdat.vfs[path] = {}
        -- TODO: Replace with segment logic when recursive is supported:
        table.insert(socdat.vfs[parent], {ilist[1], fs.name(path)})
        return true
    end
    function proxyObj.rename(from, to)
        checkArg(1, from, "string")
        checkArg(2, to, "string")
        from = fslib.cleanPath(from)
        to = fslib.cleanPath(to)
        -- TODO: Stub
        return false
    end
    function proxyObj.remove(path)
        checkArg(1, path, "string")
        path = fslib.cleanPath(path)
        -- TODO: Stub
        return false
    end

    function proxyObj.open(path, mode)
        checkArg(1, path, "string")
		if mode ~= "r" and mode ~= "rb" and mode ~= "w" and mode ~= "wb" and mode ~= "a" and mode ~= "ab" then
			error("unsupported mode", 2)
		end
        path = fslib.cleanPath(path)
        -- TODO: Stub
		return nil, "file not found"
    end
    function proxyObj.read(handle, count)
        checkArg(1, handle, "number")
        checkArg(2, count, "number")
        if handlelist[handle] == nil or handlelist[handle].mode ~= "r" then
            return nil, "bad file descriptor"
        end
    end
    function proxyObj.write(handle, value)
        checkArg(1, handle, "number")
        checkArg(2, value, "string")
        if handlelist[handle] == nil or handlelist[handle].mode ~= "w" then
            return nil, "bad file descriptor"
        end
    end
    function proxyObj.seek(handle, whence, offset)
        checkArg(1, handle, "number")
        checkArg(2, whence, "string")
        checkArg(3, offset, "number")
        if handlelist[handle] == nil then
            return nil, "bad file descriptor"
        end
        if whence ~= "set" and whence ~= "cur" and whence ~= "end" then
            error("invalid mode", 2)
        end
        if offset < 0 then
            return nil, "Negative seek offset"
        end
    end
    function proxyObj.close(handle)
        checkArg(1, handle, "number")
        if handlelist[handle] == nil then
            return nil, "bad file descriptor"
        end
        handlelist[handle] = nil
    end
    proxyObj.soc = socdat
    vcomp.register(proxyObj.address, proxyObj.type, proxyObj)
    return proxyObj
end
return socfs
