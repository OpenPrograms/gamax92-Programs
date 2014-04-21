local arg = { ... }
if #arg ~= 1 then
	print("Usage: fattest filename")
	return
end
local fs = require("filesystem")
if not fs.exists(arg[1]) then
	error("No such file", 2)
end
local fat16 = require("fat16")
local z = fat16.proxy(arg[1])
for k,v in pairs(z.fat) do
	print(k,v)
end