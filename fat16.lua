-- Uncomplete
local fs = require("filesystem")
local io = require("io")

local fat16 = {}
local _fat16 = {}

function _fat16.readRawString(file, size)
	local str = ""
	while #str < size do
		str = str .. file:read(size - #str)
	end
	return str
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

function _fat16.readDirBlock(fatset, block)
	local list = {}
	for i = 0, (#block / 32) - 1 do
		local data = _fat16.readDirEntry(fatset, block:sub(i * 32 + 1, (i + 1) * 32),i)
		table.insert(list, data)
	end
	return list
end

function _fat16.cluster2block(fatset, cluster)
	return fatset.rb + (fatset.fatc * fatset.fatbc) + (fatset.rdec * 32 / fatset.bps) + ((cluster - 2) * fatset.spc)
end

function _fat16.fatclusterlookup(fatset, cluster)
	return (fatset.bps * fatset.rb) + (cluster * 2)
end

function _fat16.nextcluster2block(fatset, file, cluster)
	file:seek("set", _fat16.fatclusterlookup(fatset, cluster))
	return _fat16.string2number(file:read(2))
end

function _fat16.getclusterchain(fatset, file, startcluster)
	local cache = {[startcluster] = true}
	local chain = {startcluster}
	local nextcluster = startcluster
	while true do 
		local nextcluster = _fat16.nextcluster2block(fatset, file, nextcluster)
		table.insert(chain, nextcluster)
		if nextcluster <= 0x0002 or nextcluster >= 0xfff7 or cache[nextcluster] == true then
			break
		end
		cache[nextcluster] = true
	end
	return chain
end

function _fat16.readEntireEntry(fatset, file, startcluster)
	local list = _fat16.getclusterchain(fatset, file, startcluster)
	if list[#list] <= 0xfff7 then
		print("fat16: Bad cluster chain, " .. startcluster)
	end
	local data = ""
	for i = 1,#list - 1 do
		file:seek("set", _fat16.cluster2block(fatset, list[i]) * fatset.bps)
		data = data .. _fat16.readRawString(file, fatset.bps * fatset.spc)
	end
	return data
end

function _fat16.searchDirectoryLists(fatset, file, path)
	local pathsplit = {}
	for dir in path:gmatch("[^/]+") do
		table.insert(pathsplit, dir)
	end
	local blockpos = (fatset.rb + (fatset.fatc * fatset.fatbc))
	local entrycluster
	local found = true
	for i = 1,#pathsplit do
		local block
		file:seek("set", fatset.bps * blockpos)
		if i == 1 then
			file:seek("set", fatset.bps * blockpos)
			block = _fat16.readRawString(file, fatset.rdec * 32)				
		else
			block = _fat16.readEntireEntry(fatset, file, entrycluster)
		end
		local dirlist = _fat16.readDirBlock(fatset, block)	
		found = false
		for _,data in ipairs(dirlist) do
			local fileflag = data.filename:sub(1,1) or 0
			if fileflag ~= string.char(0x00) and fileflag ~= string.char(0xe5) and bit32.band(data.attrib,0x08) == 0 and data.filename ~= "." and data.filename ~= ".." then
				if data.filename == pathsplit[i] then
					blockpos = _fat16.cluster2block(fatset, data.cluster)
					entrycluster = data.cluster
					found = true
					break
				end
			end
		end
		if found == false then
			break
		end
	end
	return found, blockpos, entrycluster
end

function _fat16.doSomethingForFile(fatset, file, path, something)
	local _, name, _ = path:match("(.-)([^\\/]-%.?([^%.\\/]*))$")
	path = fs.canonical(path .. "/..")
	found, blockpos, entrycluster = _fat16.searchDirectoryLists(fatset, file, path)
	if found == false then
		return false
	end
	file:seek("set", fatset.bps * blockpos)
	local block
	if entrycluster == nil then
		block = _fat16.readRawString(file, fatset.rdec * 32)
	else
		block = _fat16.readEntireEntry(fatset, file, entrycluster)
	end
	local dirlist = _fat16.readDirBlock(fatset, block)
	for _,data in ipairs(dirlist) do
		local fileflag = data.filename:sub(1,1) or 0
		if fileflag ~= string.char(0x00) and fileflag ~= string.char(0xe5) and bit32.band(data.attrib,0x08) == 0 and data.filename ~= "." and data.filename ~= ".." then
			if name == data.filename then
				something(data)
				return true
			end
		end
	end
	return false
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
	local bbs = _fat16.string2number(_fat16.readRawString(file, 2))
	if bbs ~= 0xaa55 then
		file:close()
		error("Bad boot block signature " .. string.format("%04X",bbs),2)
	end
	local fatset = {}
	file:seek("set", 0)
	local boot_block = _fat16.readRawString(file, 62)
	fatset.omd = boot_block:sub(0x04, 0x0b)
	fatset.bps = _fat16.string2number(boot_block:sub(0x0c, 0x0d))
	fatset.spc = _fat16.string2number(boot_block:sub(0x0e, 0x0e))
	fatset.rb = _fat16.string2number(boot_block:sub(0x0f, 0x10))
	fatset.fatc = _fat16.string2number(boot_block:sub(0x11, 0x11))
	fatset.rdec = _fat16.string2number(boot_block:sub(0x12, 0x13))
	fatset.tnobw = _fat16.string2number(boot_block:sub(0x14, 0x15))
	fatset.fatbc = _fat16.string2number(boot_block:sub(0x17, 0x18))
	fatset.hbc = _fat16.string2number(boot_block:sub(0x1d, 0x20))
	fatset.tnobdw = _fat16.string2number(boot_block:sub(0x21, 0x24))
	fatset.vsn = _fat16.string2number(boot_block:sub(0x28, 0x2B))
	fatset.label = boot_block:sub(0x2c, 0x36)
	fatset.ident = boot_block:sub(0x37, 0x3e)
	file:close()
	local proxyObj = {}
	proxyObj.type = "filesystem"
	proxyObj.address = string.format("%08X",fatset.vsn) -- FAT Serial Number
	proxyObj.isDirectory = function(path)
		if type(path) ~= "string" then
			error("bad arguments #1 (string expected, got " .. type(path) .. ")", 2)
		end
		path = fs.canonical(path):lower()
		if path == "" then
			return true
		end
		local file = io.open(fatfile,"rb")
		local isDirectory
		local function something(data)
			isDirectory = bit32.band(data.attrib,0x10) ~= 0
		end
		local found = _fat16.doSomethingForFile(fatset, file, path, something)
		if not found then
			return nil, "no such file or directory"
		end
		return isDirectory
	end
	proxyObj.lastModified = function(path)
		if type(path) ~= "string" then
			error("bad arguments #1 (string expected, got " .. type(path) .. ")", 2)
		end
		path = fs.canonical(path):lower()
		if path == "" then
			-- No modification date for root directory
			return 0
		end
		local file = io.open(fatfile,"rb")
		local modifyT, modifyD
		local function something(data)
			modifyT, modifyD = data.modifyT, data.modifyD
		end
		local found = _fat16.doSomethingForFile(fatset, file, path, something)
		if not found then
			return 0
		end
		local year = bit32.rshift(bit32.band(modifyD, 0xFE00), 9) + 10
		local month = bit32.rshift(bit32.band(modifyD, 0x1E0), 5)
		local day = bit32.band(modifyD, 0x001F) 
		local hour = bit32.rshift(bit32.band(modifyT, 0xF800), 11)
		local min = bit32.rshift(bit32.band(modifyT, 0x07E0), 5)
		local sec = bit32.band(modifyT, 0x001F) * 2
		local modification = year * 31556940 + month * 2629746 + day * 86400 + hour * 3600 + min * 60 + sec
		return modification
	end
	proxyObj.list = function(path)
		if type(path) ~= "string" then
			error("bad arguments #1 (string expected, got " .. type(path) .. ")", 2)
		end
		path = fs.canonical(path):lower()
		local file = io.open(fatfile,"rb")
		found, blockpos, entrycluster = _fat16.searchDirectoryLists(fatset, file, path)
		if found == false then
			return nil, "no such file or directory"
		end
		file:seek("set", fatset.bps * blockpos)
		local block
		if entrycluster == nil then
			block = _fat16.readRawString(file, fatset.rdec * 32)
		else
			block = _fat16.readEntireEntry(fatset, file, entrycluster)
		end
		local dirlist = _fat16.readDirBlock(fatset, block)
		local fslist = {}
		for _,data in ipairs(dirlist) do
			local fileflag = data.filename:sub(1,1) or 0
			if fileflag ~= string.char(0x00) and fileflag ~= string.char(0xe5) and bit32.band(data.attrib,0x08) == 0 and data.filename ~= "." and data.filename ~= ".." then
				if bit32.band(data.attrib,0x10) ~= 0 then
					table.insert(fslist, data.filename .. "/")
				else
					table.insert(fslist, data.filename)
				end
			end
		end
		file:close()
		fslist.n = #fslist
		return fslist
	end
	proxyObj.spaceTotal = function()
	end
	proxyObj.open = function(path, mode)
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
					mode = mode:sub(1,1) == "r" and "r" or "w",
					buffer = ""
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
		return fatset.label
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
		path = fs.canonical(path):lower()
		if path == "" then
			return true
		end
		local _, name, _ = path:match("(.-)([^\\/]-%.?([^%.\\/]*))$")
		path = fs.canonical(path .. "/..")
		local file = io.open(fatfile,"rb")
		found, blockpos, entrycluster = _fat16.searchDirectoryLists(fatset, file, path)
		if found == false then
			return false
		end
		file:seek("set", fatset.bps * blockpos)
		local block
		if entrycluster == nil then
			block = _fat16.readRawString(file, fatset.rdec * 32)
		else
			block = _fat16.readEntireEntry(fatset, file, entrycluster)
		end
		local dirlist = _fat16.readDirBlock(fatset, block)
		for _,data in ipairs(dirlist) do
			local fileflag = data.filename:sub(1,1) or 0
			if fileflag ~= string.char(0x00) and fileflag ~= string.char(0xe5) and bit32.band(data.attrib,0x08) == 0 then
				if name == data.filename then
					return true
				end
			end
		end
		return false
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
	proxyObj.fat = fatset
	return proxyObj
end
return fat16
