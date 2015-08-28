-- WARNING: Severly untested.
local component = require("component")
local vcomp = require("vcomponent")
local fs = require("filesystem")
local io = require("io")

local filedescript = {}

local tapefs = {}
function tapefs.proxy(address)
	local found = false
	for k,v in component.list("tape_drive") do
		if k == address and v == "tape_drive" then
			found = true
			break
		end
	end
	if not found then
		error("No such component",2)
	end
	local label
	component.invoke(address, "seek", -math.huge)
	local proxyObj = {}
	proxyObj.type = "filesystem"
	proxyObj.address = "tfs-" .. address:gsub("-","")
	proxyObj.isDirectory = function(path)
		checkArg(1,path,"string")
		path = fs.canonical(path)
		if path == "" then
			return true
		elseif path == "data.raw" and component.invoke(address, "isReady") then
			return false
		else
			return nil, "no such file or directory"
		end
	end
	proxyObj.lastModified = function(path)
		checkArg(1,path,"string")
		-- Unsupported
		return 0
	end
	proxyObj.list = function(path)
		checkArg(1,path,"string")
		path = fs.canonical(path)
		if path ~= "" then
			return nil, "no such file or directory"
		end
		local list = {}
		if path == "" and component.invoke(address, "isReady") then
			table.insert(list, "data.raw")
		end
		list.n = #list
		local iterator = 0
		return list
	end
	proxyObj.spaceTotal = function()
		return component.invoke(address, "getSize")
	end
	proxyObj.open = function(path,mode)
		checkArg(1,path,"string")
		checkArg(2,mode,"string")
		if path ~= "data.raw" or not component.invoke(address, "isReady") then
			return nil, "file not found"
		end
		if mode ~= "r" and mode ~= "rb" and mode ~= "w" and mode ~= "wb" and mode ~= "a" and mode ~= "ab" then
			error("unsupported mode",2)
		end
		while true do
			local rnddescrpt = math.random(1000000000,9999999999)
			if filedescript[rnddescrpt] == nil then
				filedescript[rnddescrpt] = {
					seek = 0,
					mode = mode:sub(1,1) == "r" and "r" or "w"
				}
				return rnddescrpt
			end
		end
	end
	proxyObj.remove = function(path)
		checkArg(1,path,"string")
		return false
	end
	proxyObj.rename = function(path, newpath)
		checkArg(1,path,"string")
		checkArg(1,newpath,"string")
		return false
	end
	proxyObj.read = function(fd, count)
		count = count or 1
		checkArg(1,fd,"number")
		checkArg(2,count,"number")
		if filedescript[fd] == nil or filedescript[fd].mode ~= "r" then
			return nil, "bad file descriptor"
		end

		component.invoke(address, "seek", -math.huge)
		component.invoke(address, "seek", filedescript[fd].seek)

		local data = component.invoke(address, "read", count)
		filedescript[fd].seek = filedescript[fd].seek + #data
		return data
	end
	proxyObj.close = function(fd)
		checkArg(1,fd,"number")
		if filedescript[fd] == nil then
			return nil, "bad file descriptor"
		end
		filedescript[fd] = nil
	end
	proxyObj.getLabel = function()
		return component.invoke(address, "getLabel")
	end
	proxyObj.seek = function(fd,kind,offset)
		checkArg(1,fd,"number")
		checkArg(2,kind,"string")
		checkArg(3,offset,"number")
		if filedescript[fd] == nil then
			return nil, "bad file descriptor"
		end
		if kind ~= "set" and kind ~= "cur" and kind ~= "end" then
			error("invalid mode",2)
		end
		if offset < 0 then
			return nil, "Negative seek offset"
		end
		local newpos
		if kind == "set" then
			newpos = offset
		elseif kind == "cur" then
			newpos = filedescript[fd].seek + offset
		elseif kind == "end" then
			newpos = component.invoke(address, "getSize") + offset - 1
		end
		filedescript[fd].seek = math.min(math.max(newpos, 0), component.invoke(address, "getSize") - 1)
		return filedescript[fd].seek
	end
	proxyObj.size = function(path)
		checkArg(1,path,"string")
		path = fs.canonical(path)
		if path == "data.raw" and component.invoke(address, "isReady") then
			return component.invoke(address, "getSize")
		end
		return 0
	end
	proxyObj.isReadOnly = function()
		return false
	end
	proxyObj.setLabel = function(newlabel)
		component.invoke(address, "setLabel", newlabel)
		return newlabel
	end
	proxyObj.makeDirectory = function(path)
		checkArg(1,path,"string")
		return false
	end
	proxyObj.exists = function(path)
		checkArg(1,path,"string")
		path = fs.canonical(path)
		if (path == "data.raw" and component.invoke(address, "isReady")) or path == "" then
			return true
		end
		return false
	end
	proxyObj.spaceUsed = function()
		return component.invoke(address, "getSize")
	end
	proxyObj.write = function(fd,data)
		checkArg(1,fd,"number")
		checkArg(2,data,"string")
		if filedescript[fd] == nil or filedescript[fd].mode ~= "w" then
			return nil, "bad file descriptor"
		end

		component.invoke(address, "seek", -math.huge)
		component.invoke(address, "seek", filedescript[fd].seek)

		component.invoke(address, "write", data)
		filedescript[fd].seek = filedescript[fd].seek + #data
		return true
	end
	vcomp.register(proxyObj.address, proxyObj.type, proxyObj)
	return proxyObj
end
return tapefs