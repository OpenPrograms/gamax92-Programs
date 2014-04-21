-- Uncomplete
local fs = require("filesystem")
local io = require("io")

local fat16 = {}
local _fat16 = {}

function _fat16.seekSector(file, sector, size)
	file:seek("set", sector * size)
end
function _fat16.readRawString(file, size)
	local str = ""
	while #str < size do
		str = str .. file:read(size - #str)
	end
	return str
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

function _fat16.string2number(data)
	local count = 0
	for i = 1,#data do
		count = count + bit32.lshift(data:byte(i,i),(i - 1) * 8)
	end
	return count
end

function _fat16.readDirEntry(fatset,block,count)
	local entry = {}
	local function spacetrim(data)
		while true do
			if data:sub(-1,-1) ~= " " then
				break
			end
			data = data:sub(1,-2)
		end
		return data
	end
	local filename = spacetrim(block:sub(1,8))
	local ext = spacetrim(block:sub(9,11))
	entry.filename = string.lower(filename .. (ext ~= "" and "." or "") .. ext)
	entry.attrib = _fat16.string2number(block:sub(12,12))
	entry.reserved = _fat16.string2number(block:sub(13,22))
	entry.modifyT = _fat16.string2number(block:sub(23,24))
	entry.modifyD = _fat16.string2number(block:sub(25,26))
	entry.cluster = _fat16.string2number(block:sub(27,28))
	entry.size = _fat16.string2number(block:sub(29,32))
	return entry
end

function _fat16.readDirBlock(fatset, file, addr)
	local list = {}
	file:seek("set", addr)
	local block = _fat16.readRawString(file, fatset.rdec * 32)
	for i = 0, fatset.rdec - 1 do
		local data = _fat16.readDirEntry(fatset,block:sub(i * 32 + 1, (i + 1) * 32),i)
		table.insert(list, data)
	end
	return list
end

function fat16.proxy(fatfile)
	if not fs.exists(fatfile) then
		error("No such file.",2)
	end
	local file = io.open(fatfile,"rb")
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
	proxyObj.address = string.format("%08X",fat_settings.vsn) -- FAT Serial Number
	proxyObj.isDirectory = function(path)
		if type(path) ~= "string" then
			error("bad arguments #1 (string expected, got " .. type(path) .. ")", 2)
		end
		path = fs.canonical(path)
		return nil, "file not found"
	end
	proxyObj.lastModified = function(path)
		if type(path) ~= "string" then
			error("bad arguments #1 (string expected, got " .. type(path) .. ")", 2)
		end
	end
	proxyObj.list = function(path)
		if type(path) ~= "string" then
			error("bad arguments #1 (string expected, got " .. type(path) .. ")", 2)
		end
		path = fs.canonical(path)
		local fslist = {}
		local file = io.open(fatfile,"rb")
		local dirlist = _fat16.readDirBlock(fat_settings, file, fat_settings.bps * (fat_settings.rb + (fat_settings.fatc * fat_settings.fatbc)))
		for i = 1,#dirlist do
			local data = dirlist[i]
			local fileflag = data.filename:sub(1,1)
			if fileflag ~= string.char(0x00) and fileflag ~= string.char(0xe5) and bit32.band(data.attrib,0x08) == 0 then
				table.insert(fslist, data.filename)
			end
		end
		fslist.n = #fslist
		return fslist
	end
	proxyObj.spaceTotal = function()
	end
	proxyObj.open = function(path,mode)
		if type(path) ~= "string" then
			error("bad arguments #1 (string expected, got " .. type(path) .. ")", 2)
		elseif type(mode) ~= "string" and type(mode) ~= "nil" then
			error("bad arguments #2 (string expected, got " .. type(mode) .. ")", 2)
		end
		if true then -- Check for existance
			return nil, "file not found"
		end
		if mode ~= "r" and mode ~= "rb" and mode ~= "w" and mode ~= "b" and mode ~= "a" and mode ~= "ab" then
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
		if type(path) ~= "string" then
			error("bad arguments #1 (string expected, got " .. type(path) .. ")", 2)
		end
	end
	proxyObj.rename = function(path, newpath)
		if type(path) ~= "string" then
			error("bad arguments #1 (string expected, got " .. type(path) .. ")", 2)
		elseif type(newpath) ~= "string" then
			error("bad arguments #2 (string expected, got " .. type(newpath) .. ")", 2)
		end
	end
	proxyObj.read = function(fd, count)
		count = count or 1
		if type(fd) ~= "number" then
			error("bad arguments #1 (number expected, got " .. type(fd) .. ")", 2)
		elseif type(count) ~= "number" then
			error("bad arguments #2 (number expected, got " .. type(count) .. ")", 2)
		end
		if filedescript[fd] == nil or filedescript[fd].mode ~= "r" then
			return nil, "bad file descriptor"
		end
	end
	proxyObj.close = function(fd)
		if type(fd) ~= "number" then
			error("bad arguments #1 (number expected, got " .. type(fd) .. ")", 2)
		end
		if filedescript[fd] == nil then
			return nil, "bad file descriptor"
		end
		filedescript[fd] = nil
	end
	proxyObj.getLabel = function()
		return fat_settings.label
	end
	proxyObj.seek = function(fd,kind,offset)
		if type(fd) ~= "number" then
			error("bad arguments #1 (number expected, got " .. type(fd) .. ")", 2)
		elseif type(kind) ~= "string" then
			error("bad arguments #2 (string expected, got " .. type(kind) .. ")", 2)
		elseif type(offset) ~= "number" then
			error("bad arguments #3 (number expected, got " .. type(kind) .. ")", 2)
		end
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
			newpos = component.invoke(address, "getSize") + offset - 1 -- Get size of file
		end
		filedescript[fd].seek = math.min(math.max(newpos, 0), component.invoke(address, "getSize") - 1) -- size of file
		return filedescript[fd].seek
	end
	proxyObj.size = function(path)
		if type(path) ~= "string" then
			error("bad arguments #1 (string expected, got " .. type(path) .. ")", 2)
		end
		path = fs.canonical(path)
	end
	proxyObj.isReadOnly = function()
	end
	proxyObj.setLabel = function(newlabel)
	end
	proxyObj.makeDirectory = function(path)
		if type(path) ~= "string" then
			error("bad arguments #1 (string expected, got " .. type(path) .. ")", 2)
		end
	end
	proxyObj.exists = function(path)
		if type(path) ~= "string" then
			error("bad arguments #1 (string expected, got " .. type(path) .. ")", 2)
		end
		path = fs.canonical(path)
	end
	proxyObj.spaceUsed = function()
	end
	proxyObj.write = function(fd,data)
		if type(fd) ~= "number" then
			error("bad arguments #1 (number expected, got " .. type(fd) .. ")", 2)
		elseif type(data) ~= "string" then
			error("bad arguments #2 (string expected, got " .. type(data) .. ")", 2)
		end
		if filedescript[fd] == nil or filedescript[fd].mode ~= "w" then
			return nil, "bad file descriptor"
		end
	end
	proxyObj.fat = fat_settings
	return proxyObj
end
return fat16