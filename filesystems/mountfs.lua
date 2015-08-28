local fs = require("filesystem")
local shell = require("shell")

local args, opts = shell.parse(...)
args[1] = args[1] or "/mnt/tape/data.raw"
opts.t = opts.t or "msdos"
if not fs.exists(args[1]) then
    error("mountfs: '" .. args[1] .. ": No such file", 2)
end
local ok, fsdrive = pcall(require, opts.t)
if not ok then
    error("mountfs: Filesystem driver '" .. opts.t .. "' is invalid", 2)
end
if fsdrive.proxy == nil then
    error("mountfs: Filesystem driver '" .. opts.t .. "' is incompatible", 2)
end
local z = fsdrive.proxy(args[1])
if opts.d then
    local special
    if opts.t == "msdos" then
        special = "fat"
    elseif opts.t == "socfs" then
        special = "soc"
    end
    if special == nil then
        io.stderr:write("mountfs: No debugging available for '" .. opts.t .. "'\n")
    else
        for k, v in pairs(z[special]) do
            print(k, v)
        end
    end
end
print("mountfs: Mounted at /mnt/" .. z.address:sub(1, 3))
