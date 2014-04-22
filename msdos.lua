-- Uncomplete
local fs = require("filesystem")
local io = require("io")

local filedescript = {}

local msdos = {}
local _msdos = {}

function _msdos.readRawString(file, size)
	local str = ""
	while #str < size do
		str = str .. file:read(size - #str)
	end
	return str
end

function _msdos.string2number(data)
	local count = 0
	for i = 1,#data do
		count = count + bit32.lshift(data:byte(i,i),(i - 1) * 8)
	end
	return count
end

function _msdos.readDirEntry(fatset,block,count)
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
	entry.rawfilename = filename .. (ext ~= "" and "." or "") .. ext
	entry.filename = string.lower(entry.rawfilename)
	entry.attrib = _msdos.string2number(block:sub(12,12))
	entry.createT = _msdos.string2number(block:sub(15,16))
	entry.createD = _msdos.string2number(block:sub(17,18))
	entry.accessD = _msdos.string2number(block:sub(19,20))
	entry.modifyT = _msdos.string2number(block:sub(23,24))
	entry.modifyD = _msdos.string2number(block:sub(25,26))
	local cluster
	if fatset.fatsize == 12 then
		cluster = bit32.band(_msdos.string2number(block:sub(27,28)),0x0FFF)
	elseif fatset.fatsize == 16 then
		cluster = _msdos.string2number(block:sub(27,28))
	else
		cluster = bit32.lshift(_msdos.string2number(block:sub(20,21)), 16) + _msdos.string2number(block:sub(27,28))
	end
	entry.cluster = cluster
	entry.size = _msdos.string2number(block:sub(29,32))
	return entry
end

function _msdos.readDirBlock(fatset, block)
	local list = {}
	for i = 0, (#block / 32) - 1 do
		local data = _msdos.readDirEntry(fatset, block:sub(i * 32 + 1, (i + 1) * 32),i)
		table.insert(list, data)
	end
	return list
end

function _msdos.cluster2block(fatset, cluster)
	return fatset.rb + (fatset.fatc * fatset.fatbc) + (fatset.rdec * 32 / fatset.bps) + ((cluster - 2) * fatset.spc)
end

function _msdos.fatclusterlookup(fatset, cluster)
	return (fatset.bps * fatset.rb) + (cluster * 2)
end

function _msdos.getNextCluster12(fatset, file, cluster)
	if cluster % 2 == 0 then
		file:seek("set", (fatset.bps * fatset.rb) + (cluster * 1.5))
		return bit32.band(_msdos.string2number(file:read(2)), 0x0FFF)
	else
		file:seek("set", (fatset.bps * fatset.rb) + math.floor(cluster * 1.5))
		return bit32.rshift(_msdos.string2number(file:read(2)), 4)
	end
end

function _msdos.getNextCluster16(fatset, file, cluster)
	file:seek("set", (fatset.bps * fatset.rb) + (cluster * 2))
	return _msdos.string2number(file:read(2))
end

function _msdos.getNextCluster32(fatset, file, cluster)
	file:seek("set", (fatset.bps * fatset.rb) + (cluster * 4))
	return bit32.band(_msdos.string2number(file:read(4)), 0x0FFFFFFF)
end

function _msdos.getClusterChain(fatset, file, startcluster)
	local cache = {[startcluster] = true}
	local chain = {startcluster}
	local nextcluster = startcluster
	local highcluster
	if fatset.fatsize == 12 then
		highcluster = 0x0FF7
	elseif fatset.fatsize == 16 then
		highcluster = 0xFFF7
	else
		highcluster = 0x0FFFFFF7
	end
	while true do
		if fatset.fatsize == 12 then
			nextcluster = _msdos.getNextCluster12(fatset, file, nextcluster)
		elseif fatset.fatsize == 16 then
			nextcluster = _msdos.getNextCluster16(fatset, file, nextcluster)
		else
			nextcluster = _msdos.getNextCluster32(fatset, file, nextcluster)
		end
		table.insert(chain, nextcluster)
		if nextcluster <= 0x0002 or nextcluster >= highcluster or cache[nextcluster] == true then
			if nextcluster <= highcluster then
				error("msdos: Bad cluster chain, " .. startcluster)
				print(table.concat(chain, ","))
			end
			break
		end
		cache[nextcluster] = true
	end
	return chain
end

function _msdos.readEntireEntry(fatset, file, startcluster)
	local list = _msdos.getClusterChain(fatset, file, startcluster)
	local data = ""
	for i = 1,#list - 1 do
		file:seek("set", _msdos.cluster2block(fatset, list[i]) * fatset.bps)
		data = data .. _msdos.readRawString(file, fatset.bps * fatset.spc)
	end
	return data
end

function _msdos.searchDirectoryLists(fatset, file, path)
	local pathsplit = {}
	for dir in path:gmatch("[^/]+") do
		if #dir > 12 then
			return false
		end
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
			block = _msdos.readRawString(file, fatset.rdec * 32)				
		else
			block = _msdos.readEntireEntry(fatset, file, entrycluster)
		end
		local dirlist = _msdos.readDirBlock(fatset, block)	
		found = false
		for _,data in ipairs(dirlist) do
			local fileflag = data.filename:sub(1,1) or 0
			if fileflag ~= string.char(0x00) and fileflag ~= string.char(0xe5) and bit32.band(data.attrib,0x08) == 0 and data.filename ~= "." and data.filename ~= ".." then
				if data.filename == pathsplit[i] then
					blockpos = _msdos.cluster2block(fatset, data.cluster)
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

function _msdos.doSomethingForFile(fatset, file, path, something)
	local _, name, _ = path:match("(.-)([^\\/]-%.?([^%.\\/]*))$")
	if #name > 12 then
		return false
	end
	path = fs.canonical(path .. "/..")
	found, blockpos, entrycluster = _msdos.searchDirectoryLists(fatset, file, path)
	if found == false then
		return false
	end
	file:seek("set", fatset.bps * blockpos)
	local block
	if entrycluster == nil then
		block = _msdos.readRawString(file, fatset.rdec * 32)
	else
		block = _msdos.readEntireEntry(fatset, file, entrycluster)
	end
	local dirlist = _msdos.readDirBlock(fatset, block)
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

function msdos.proxy(fatfile, fatsize)
	if not fs.exists(fatfile) then
		error("No such file.",2)
	end
	local file = io.open(fatfile,"rb")
	local pos, err = file:seek("set", 0x36)
	if pos == nil then
		error("Seeking failed: " .. err)
	end
	local bbs = _msdos.readRawString(file, 8)
	if fatsize == 28 then fatsize = 32 end -- Allow for FAT28
	if fatsize ~= nil and fatsize ~= 12 and fatsize ~= 16 and fatsize ~= 32 then
		error("Invalid FAT size")
	end
	local fatset = {}
	file:seek("set", 0)
	local boot_block = _msdos.readRawString(file, 62)
	fatset.bps = _msdos.string2number(boot_block:sub(0x0c, 0x0d))
	fatset.spc = _msdos.string2number(boot_block:sub(0x0e, 0x0e))
	fatset.rb = _msdos.string2number(boot_block:sub(0x0f, 0x10))
	fatset.fatc = _msdos.string2number(boot_block:sub(0x11, 0x11))
	fatset.rdec = _msdos.string2number(boot_block:sub(0x12, 0x13))
	fatset.fatbc = _msdos.string2number(boot_block:sub(0x17, 0x18))
	fatset.hbc = _msdos.string2number(boot_block:sub(0x1d, 0x20))
	fatset.vsn = _msdos.string2number(boot_block:sub(0x28, 0x2B))
	fatset.label = boot_block:sub(0x2c, 0x36)
	fatset.ident = boot_block:sub(0x37, 0x3e)
	local tnos = _msdos.string2number(boot_block:sub(0x14, 0x15))
	if tnos == 0 then
		tnos = _msdos.string2number(boot_block:sub(0x21, 0x24))
	end
	fatset.tnos = tnos
	fatset.tnoc = math.floor(tnos / fatset.spc)
	if fatsize == nil then
		print("msdos: Detecting FAT size ...")
		print("msdos: Ident suggests: " .. fatset.ident)
		if fatset.tnoc < 4085 then
			print("msdos: Detected FAT size as FAT12")
			fatsize = 12
		elseif fatset.tnoc < 65525 then
			print("msdos: Detected FAT size as FAT16")
			fatsize = 16
		else
			print("msdos: Detected FAT size as FAT32")
			fatsize = 32
		end
	end
	if fatsize == 32 then
		error("FAT" .. fatsize .. " currently unsupported.")
	end
	fatset.fatsize = fatsize
	file:seek("set", fatset.bps * (fatset.rb + (fatset.fatc * fatset.fatbc)))
	local block = _msdos.readRawString(file, fatset.rdec * 32)
	file:close()
	local dirlist = _msdos.readDirBlock(fatset, block)
	for _,data in ipairs(dirlist) do
		if bit32.band(data.attrib,0x08) ~= 0 then
			fatset.label = data.rawfilename:gsub("%.","")
			break
		end
	end
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
		local isDirectory
		local file = io.open(fatfile,"rb")
		local found = _msdos.doSomethingForFile(fatset, file, path, function(data) isDirectory = bit32.band(data.attrib,0x10) ~= 0 end)
		file:close()
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
		local modifyT, modifyD
		local file = io.open(fatfile,"rb")
		local found = _msdos.doSomethingForFile(fatset, file, path, function(data) modifyT, modifyD = data.modifyT, data.modifyD end)
		file:close()
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
		found, blockpos, entrycluster = _msdos.searchDirectoryLists(fatset, file, path)
		if found == false then
			return nil, "no such file or directory"
		end
		file:seek("set", fatset.bps * blockpos)
		local block
		if entrycluster == nil then
			block = _msdos.readRawString(file, fatset.rdec * 32)
		else
			block = _msdos.readEntireEntry(fatset, file, entrycluster)
		end
		file:close()
		local dirlist = _msdos.readDirBlock(fatset, block)
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
		fslist.n = #fslist
		return fslist
	end
	proxyObj.spaceTotal = function()
	end
	proxyObj.exists = function(path)
		if type(path) ~= "string" then
			error("bad arguments #1 (string expected, got " .. type(path) .. ")", 2)
		end
		path = fs.canonical(path):lower()
		if path == "" then
			return true
		end
		local file = io.open(fatfile,"rb")
		local found = _msdos.doSomethingForFile(fatset, file, path, function() end)
		file:close()
		return found
	end
	proxyObj.open = function(path, mode)
		if type(path) ~= "string" then
			error("bad arguments #1 (string expected, got " .. type(path) .. ")", 2)
		elseif type(mode) ~= "string" and type(mode) ~= "nil" then
			error("bad arguments #2 (string expected, got " .. type(mode) .. ")", 2)
		end
		if mode ~= "r" and mode ~= "rb" and mode ~= "w" and mode ~= "b" and mode ~= "a" and mode ~= "ab" then
			error("unsupported mode",2)
		end
		path = fs.canonical(path):lower()
		if path == "" then
			return nil
		end
		local filecluster, filesize
		local file = io.open(fatfile,"rb")
		local found = _msdos.doSomethingForFile(fatset, file, path, function(data) filecluster, filesize = data.cluster, data.size end)
		if not found then
			file:close()
			return nil, "file not found"
		end
		while true do
			local rnddescrpt = math.random(1000000000,9999999999)
			if filedescript[rnddescrpt] == nil then
				filedescript[rnddescrpt] = {
					seek = 0,
					mode = mode:sub(1,1) == "r" and "r" or "w",
					buffer = "",
					chain = _msdos.getClusterChain(fatset, file, filecluster),
					size = filesize
				}
				file:close()
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
		if #filedescript[fd].buffer >= filedescript[fd].size and filedescript[fd].seek > filedescript[fd].size then
			return nil
		end
		count = math.min(count,8192)
		if filedescript[fd].seek + count > filedescript[fd].size then
			count = filedescript[fd].size - filedescript[fd].seek
		end
		if count == 0 then
			return nil
		end
		while #filedescript[fd].buffer < filedescript[fd].seek + count do
			local nextchain = (#filedescript[fd].buffer / fatset.bps / fatset.spc) + 1
			if filedescript[fd].chain[nextchain] == nil then
				return nil
			end
			local block = _msdos.cluster2block(fatset, filedescript[fd].chain[nextchain])
			local file = io.open(fatfile,"rb")
			file:seek("set", block * fatset.bps)
			local data = _msdos.readRawString(file, fatset.bps * fatset.spc)
			file:close()
			filedescript[fd].buffer = filedescript[fd].buffer .. data
		end
		filedescript[fd].buffer = filedescript[fd].buffer:sub(1,filedescript[fd].size)
		local data = filedescript[fd].buffer:sub(filedescript[fd].seek + 1, filedescript[fd].seek + count)
		filedescript[fd].seek = filedescript[fd].seek + #data
		return data
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
		path = fs.canonical(path):lower()
		if path == "" then
			return 0
		end
		local filesize
		local file = io.open(fatfile,"rb")
		local found = _msdos.doSomethingForFile(fatset, file, path, function(data) filesize = data.size end)
		file:close()
		if not found then
			return 0
		end
		return filesize
	end
	proxyObj.isReadOnly = function()
		return false
	end
	proxyObj.setLabel = function(newlabel)
	end
	proxyObj.makeDirectory = function(path)
		if type(path) ~= "string" then
			error("bad arguments #1 (string expected, got " .. type(path) .. ")", 2)
		end
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
return msdos
