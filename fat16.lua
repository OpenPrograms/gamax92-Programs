--Uncomplete
local fs = require("filesystem")
local io = require("io")

local fat16 = {}
local _fat16 = {}

function _fat16.seekSector(file, sector, size)
	file:seek("set", sector * size)
end
function _fat16.readRawString(file, size)
	return file:read(size)
end
function _fat16.readWord(file)
	return file:read(1):byte() + bit32.lshift(file:read(1):byte(),8)
end
function _fat16.readByte(file)
	return file:read(1):byte()
end
function _fat16.readDoubleWord(file)
	return file:read(1):byte() + bit32.lshift(file:read(1):byte(),8) + bit32.lshift(file:read(1):byte(),16) + bit32.lshift(file:read(1):byte(),24)
end

function fat16.proxy(path)
	if not fs.exists(path) then
		error("No such file.",2)
	end
	local file = fs.open(path,"rb")
	local pos, err = file:seek("set",0x1fe)
	if pos == nil then
		error("Seeking failed: " .. err)
	end
	local bbs = _fat16.readWord(file)
	if bbs ~= 0xaa55 then
		file:close()
		error("Bad boot block signature " .. string.format("%04X",bbs),2)
	end
	local fat_settings = {}
	file:seek("set", 0x03)
	fat_settings.omd = _fat16.readRawString(file, 8)
	fat_settings.bps = _fat16.readWord(file)
	fat_settings.bpau = _fat16.readByte(file)
	fat_settings.rb = _fat16.readWord(file)
	fat_settings.fatc = _fat16.readByte(file)
	fat_settings.rdec = _fat16.readWord(file)
	fat_settings.tnobw = _fat16.readWord(file)
	file:seek("set", 0x16)
	fat_settings.fatbc = _fat16.readWord(file)
	file:seek("set", 0x1c)
	fat_settings.hbc = _fat16.readDoubleWord(file)
	fat_settings.tnobdw = _fat16.readDoubleWord(file)
	file:seek("set", 0x27)
	fat_settings.vsn = _fat16.readDoubleWord(file)
	fat_settings.label = _fat16.readRawString(file, 11)
	file:close()
	local proxyObj = {}
	proxyObj.type = "filesystem"
	proxyObj.address = "" -- FAT Serial Number
	proxyObj.isDirectory = function()
	end
	proxyObj.lastModified = function()
	end
	proxyObj.list = function()
	end
	proxyObj.spaceTotal = function()
	end
	proxyObj.open = function()
	end
	proxyObj.remove = function()
	end
	proxyObj.rename = function()
	end
	proxyObj.read = function()
	end
	proxyObj.close = function()
	end
	proxyObj.getLabel = function()
	end
	proxyObj.seek = function()
	end
	proxyObj.size = function()
	end
	proxyObj.isReadOnly = function()
	end
	proxyObj.setLabel = function()
	end
	proxyObj.makeDirectory = function()
	end
	proxyObj.exists = function()
	end
	proxyObj.spaceUsed = function()
	end
	proxyObj.write = function()
	end
	proxyObj.fat = fat_settings
	return proxyObj
end
return fat16