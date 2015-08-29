local fs = require("filesystem")
local shell = require("shell")
local fslib = require("fslib")

local function errprint(...)
    local arg = table.pack(...)
    local out = {}
    for i = 1, arg.n do
        out[#out+1] = tostring(arg[i])
        out[#out+1] = i < arg.n and "\t" or "\n"
    end
    io.stderr:write(table.concat(out))
    io.stderr:flush()
    os.exit()
end

local usage = [[Usage: mksocfs [OPTIONS...] filename
Options:
 --blocksize Number of bytes per block
 --reserved  Number of reserved blocks
 --datasize  Size of the data area (blocks)
 --indexsize Size of the index area (bytes)
 --label     Filesystem label
]]

local args, opts = shell.parse(...)
if #args < 1 then
    print(usage)
    return
end

local default = {
    blocksize=512,
    reserved=1,
-- I really don't know what to put for this:
    datasize=0,
    indexsize=64*128,
    label="",
}

for k, v in pairs(opts) do
    if default[k] == nil then
        errprint("mksocfs: " .. k .. ": Unknown argument")
    elseif k ~= "label" and (tonumber(v) == nil or math.floor(tonumber(v)) ~= tonumber(v)) then
        errprint("mksocfs: " .. k .. ": Invalid value")
    end
end
for k, v in pairs(default) do opts[k] = (type(v) == "number" and tonumber(opts[k]) or opts[k]) or v end
default = nil

opts.blocklog = math.log(opts.blocksize)/math.log(2)-7

if opts.blocklog < 1 or opts.blocklog > 255 or math.floor(opts.blocklog) ~= opts.blocklog then
    errprint("mksocfs: Invalid blocksize")
elseif opts.blocklog == 1 and opts.reserved < 2 then
    errprint("mksocfs: Invalid reserved count")
elseif opts.indexsize%64 ~= 0 then
    errprint("mksocfs: Invalid index area size")
end

if not fs.exists(args[1]) then
    errprint("mksocfs: " .. args[1] .. ": No such file")
elseif fs.isDirectory(args[1]) then
    errprint("mksocfs: " .. args[1] .. ": Cannot format a directory")
end

local size = fs.size(args[1])
if size == 0 then
    local file, err = io.open(args[1], "rb")
    if not file then
        errprint("mksocfs: " .. args[1] .. ": " .. err:sub(1, 1):upper() .. err:sub(2))
    end
    size, err = file:seek("end")
    file:close()
    if not size then
        errprint("mksocfs: " .. args[1] .. ": " .. err:sub(1, 1):upper() .. err:sub(2))
    end
end
if size == 0 then
    error("mksocfs: " .. args[1] .. ": Cannot get size of file")
end

local file, err = io.open(args[1], "wb")
if not file then
    errprint("mksocfs: " .. args[1] .. ": " .. err:sub(1, 1):upper() .. err:sub(2))
end
local seek, err = file:seek("set", 0x0194)
if not seek then
    file:close()
    errprint("mksocfs: " .. args[1] .. ": " .. err:sub(1, 1):upper() .. err:sub(2))
end

print("Writing SOCFS Super Block ...")

local creation = os.time()
file:write(table.concat({
    fslib.num2str(creation, 8),
    fslib.num2str(opts.datasize, 8),
    fslib.num2str(opts.indexsize, 8),
    "SOC",
    "\x10",
    fslib.num2str(math.floor(size/opts.blocksize), 8),
    fslib.num2str(opts.reserved, 4),
    fslib.num2str(opts.blocklog, 1)
}))
file:seek("set", math.floor(size/opts.blocksize)*opts.blocksize-opts.indexsize)
local indexsize = opts.indexsize/64
local empty = string.rep("\0", 64)

local r = function(a, b) return string.char(math.random(a or 0, b or 255)) end
local uuid = table.concat({r(), r(), r(), r(), r(), r(), r(64, 79), r(), r(128, 191), r(), r(), r(), r(), r(), r(), r()})

print("Writing SOCFS Index Area ...")

for i = 1, indexsize do
    if i == 1 then
        file:write("\2" .. string.rep("\0", 63))
    elseif i == indexsize then
        local label = opts.label:sub(1, 39)
        label = label .. string.rep("\0", 39-#label)
        file:write(table.concat({
            "\1",
            fslib.num2str(creation, 8),
            uuid,
            label,
        }))
    else
        file:write(empty)
    end
end
file:close()

print("Wrote SOCFS filesystem structures")
