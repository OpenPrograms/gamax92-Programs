local shell = require("shell")
local fs = require("filesystem")
local args = {...}
if #args < 1 then
	print("Usage: debug file (arguments)")
	return
end
args[1] = shell.resolve(args[1])
if not fs.exists(args[1]) then
	error("No such file",0)
end
print(xpcall(function() return loadfile(args[1])(table.unpack(args,2)) end,debug.traceback))
