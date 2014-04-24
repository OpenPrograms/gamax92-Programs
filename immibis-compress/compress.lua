local fs = require("filesystem")
local shell = require("shell")
local ipack = require("ipack")
local inFN, outFN

local args = {...}
if #args ~= 2 then
	print("Usage: compress <input file> <output file>")
	return
end

inFN = shell.resolve(args[1])
outFN = shell.resolve(args[2])

if not fs.exists(inFN) then
	error("No such file", 0)
end

local f = io.open(inFN, "rb")
local data = f:read("*a")
f:close()

local out = ipack.compress(data, 8, 0)

local f = io.open(outFN, "wb")
f:write(out)
f:close()

print("uncompressed size: ", data:len())
print("compressed size: ", out:len())
print("compression ratio: ", math.floor(out:len() / data:len() * 1000)/10 .. "%")