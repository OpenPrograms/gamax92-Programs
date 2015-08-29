local fs = require("filesystem")

local fslib = {}

function fslib.readRawString(file, size)
    local str = ""
    while #str < size do
        str = str .. file:read(size - #str)
    end
    return str
end

if string.pack then
    function fslib.str2num(data)
        return string.unpack("<I" .. #data, data)
    end

    function fslib.num2str(data, size)
        return string.pack("<I" .. size, data)
    end
else
    function fslib.str2num(data)
        local count = 0
        for i = 1, #data do
            count = count + bit32.lshift(data:byte(i, i), (i - 1) * 8)
        end
        return count
    end

    function fslib.num2str(data, size)
        local str = ""
        for i = 1, size do
            str = str .. string.char(bit32.rshift(bit32.band(data, bit32.lshift(0xFF, (i - 1) * 8)), (i - 1) * 8))
        end
        return str
    end
end

function fslib.cleanPath(path)
    return table.concat(fs.segments(path), "/")
end

function fslib.getParent(path)
    return path:match("(.*)/") or ""
end

return fslib
