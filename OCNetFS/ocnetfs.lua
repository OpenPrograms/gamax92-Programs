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
socket:setTimeout(3)

local vnetfs = {}

local function sendMessage(ctrl,data)
	socket:write(string.char(ctrl + 31) .. data .. "\n")
	socket:flush()
end

local function getData()
	local stat, line, err = pcall(socket.read, socket, "*l")
	if not stat then
		pcall(socket.close,socket)
		socket = {read = function() return nil, "non open socket" end, write = function() end, flush = function() end, close = function() end}
		vcomp.unregister(vnetfs.address)
		print("ocnetfs: " .. (line or "unknown error"))
		return {}
	elseif not line then
		pcall(socket.close,socket)
		socket = {read = function() return nil, "non open socket" end, write = function() end, flush = function() end, close = function() end}
		vcomp.unregister(vnetfs.address)
		print("ocnetfs: " .. (err or "unknown error"))
		return {}
	elseif line:sub(1,1) ~= "{" then
		error(line,3)
	else
		return load("return " .. line)()
	end
end

vnetfs.type = "filesystem"
vnetfs.address = ip .. ":" .. port
function vnetfs.size(path)
	checkArg(1,path,"string")
	sendMessage(1,serialization.serialize({path}))
	local ret = getData()
	return table.unpack(ret)
end
function vnetfs.seek(handle, whence, offset)
	checkArg(1,handle,"number")
	checkArg(2,whence,"string")
	checkArg(3,offset,"number")
	sendMessage(2,serialization.serialize({handle, whence, offset}))
	local ret = getData()
	return table.unpack(ret)
end
function vnetfs.read(handle, count)
	checkArg(1,handle,"number")
	checkArg(2,count,"number")
	sendMessage(3,serialization.serialize({handle, count}))
	local ret = getData()
	return table.unpack(ret)
end
function vnetfs.isDirectory(path)
	checkArg(1,path,"string")
	sendMessage(4,serialization.serialize({path}))
	local ret = getData()
	return table.unpack(ret)
end
function vnetfs.open(path, mode)
	checkArg(1,path,"string")
	checkArg(2,mode,"string")
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
	checkArg(1,value,"string")
	sendMessage(7,serialization.serialize({value}))
	local ret = getData()
	return table.unpack(ret)
end
function vnetfs.lastModified(path)
	checkArg(1,path,"string")
	sendMessage(8,serialization.serialize({path}))
	local ret = getData()
	return table.unpack(ret)
end
function vnetfs.close(handle)
	checkArg(1,handle,"number")
	sendMessage(9,serialization.serialize({handle}))
	local ret = getData()
	return table.unpack(ret)
end
function vnetfs.rename(from, to)
	checkArg(1,from,"string")
	checkArg(2,to,"string")
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
	checkArg(1,path,"string")
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
	checkArg(1,path,"string")
	sendMessage(15,serialization.serialize({path}))
	local ret = getData()
	return table.unpack(ret)
end
function vnetfs.list(path)
	checkArg(1,path,"string")
	sendMessage(16,serialization.serialize({path}))
	local ret = getData()
	return table.unpack(ret)
end
function vnetfs.write(handle, value)
	checkArg(1,handle,"number")
	checkArg(2,value,"string")
	sendMessage(17,serialization.serialize({handle, value}))
	local ret = getData()
	return table.unpack(ret)
end
function vnetfs.remove(path)
	checkArg(1,path,"string")
	sendMessage(18,serialization.serialize({path}))
	local ret = getData()
	return table.unpack(ret)
end

vcomp.register(vnetfs.address, vnetfs.type, vnetfs)
print("Added component at " .. vnetfs.address)
