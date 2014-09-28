local function errprint(msg)
	io.stderr:write(msg)
end

local component = require("component")
if not component.isAvailable("internet") then
	errprint("Internet card is required")
	return
end

local shell = require("shell")
local args,opts = shell.parse(...)
if #args < 2 then
	print("Usage: ocnetfs ip port")
	return
end

local ip,port = args[1],tonumber(args[2])
if port == nil then
	errprint("Non numerical port",0)
	return
end

local internet = require("internet")
local serialization = require("serialization")
local vcomp = require("vcomponent")

local socket = internet.open(ip,port)

local vnetfs = {}

local function sendMessage(ctrl,data)
	socket:write(string.char(ctrl) .. data .. "\n")
	socket:flush()
end

local function getData()
	local line, err = socket:read("*l")
	if not line then
		print("ocnetfs: " .. err or "unknown error")
		vcomp.unregister(vnetfs.address)
	end
	return load("return " .. line)()
end

vnetfs.type = "filesystem"
vnetfs.address = ip .. ":" .. port
function vnetfs.size(path)
	sendMessage(1,serialization.serialize({path}))
	local ret = getData()
	return table.unpack(ret)
end
function vnetfs.seek(handle, whence, offset)
	sendMessage(2,serialization.serialize({handle, whence, offset}))
	local ret = getData()
	return table.unpack(ret)
end
function vnetfs.read(handle, count)
	sendMessage(3,serialization.serialize({handle, count}))
	local ret = getData()
	return table.unpack(ret)
end
function vnetfs.isDirectory(path)
	sendMessage(4,serialization.serialize({path}))
	local ret = getData()
	return table.unpack(ret)
end
function vnetfs.open(path, mode)
	sendMessage(5,serialization.serialize({path, mode}))
	local ret = getData()
	return table.unpack(ret)
end
function vnetfs.spaceTotal()
	sendMessage(6,serialization.serialize({}))
	local ret = getData()
	return table.unpack(ret)
end
function vnetfs.setLabel(value)
	sendMessage(7,serialization.serialize({value}))
	local ret = getData()
	return table.unpack(ret)
end
function vnetfs.lastModified(path)
	sendMessage(8,serialization.serialize({path}))
	local ret = getData()
	return table.unpack(ret)
end
function vnetfs.close(handle)
	sendMessage(9,serialization.serialize({handle}))
	local ret = getData()
	return table.unpack(ret)
end
function vnetfs.rename(from, to)
	sendMessage(10,serialization.serialize({from, to}))
	local ret = getData()
	return table.unpack(ret)
end
function vnetfs.isReadOnly()
	sendMessage(11,serialization.serialize({}))
	local ret = getData()
	return table.unpack(ret)
end
function vnetfs.exists(path)
	sendMessage(12,serialization.serialize({path}))
	local ret = getData()
	return table.unpack(ret)
end
function vnetfs.getLabel()
	sendMessage(13,serialization.serialize({}))
	local ret = getData()
	return table.unpack(ret)
end
function vnetfs.spaceUsed()
	sendMessage(14,serialization.serialize({}))
	local ret = getData()
	return table.unpack(ret)
end
function vnetfs.makeDirectory(path)
	sendMessage(15,serialization.serialize({path}))
	local ret = getData()
	return table.unpack(ret)
end
function vnetfs.list(path)
	sendMessage(16,serialization.serialize({path}))
	local ret = getData()
	return table.unpack(ret)
end
function vnetfs.write(handle, value)
	sendMessage(17,serialization.serialize({handle, value}))
	local ret = getData()
	return table.unpack(ret)
end
function vnetfs.remove(path)
	sendMessage(18,serialization.serialize({path}))
	local ret = getData()
	return table.unpack(ret)
end

vcomp.register(vnetfs.address, vnetfs.type, vnetfs)
print("Added component at " .. vnetfs.address)
