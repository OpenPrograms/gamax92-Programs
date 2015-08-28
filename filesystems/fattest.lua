local arg = { ... }
arg[1] = arg[1] or "/mnt/tape/data.raw"
local fs = require("filesystem")
if not fs.exists(arg[1]) then
	error("No such file", 2)
end
local msdos = require("msdos")
local z = msdos.proxy(arg[1])
for k,v in pairs(z.fat) do
	print(k,v)
end
print("Mounting at /mnt/fat16")
fs.mount(z,"/mnt/fat16")
