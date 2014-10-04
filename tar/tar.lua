local fs = require("filesystem")
local shell = require("shell")

local format = require("format")

local args, options = shell.parse(...)

local operation, filename, label, file
local verbose, zblock = false, false
local cblock = 0

-- TODO: This usage is bland.
local usage =
[[Usage: tar [OPTION...] [FILE]...
tar saves many files together into a single tape or disk archive, and can restore individual files from the archive.]]

local function setOp(set)
	if operation ~= nil and operation ~= set then
		print("tar: You may not specify more than one '-Acdtrux', '--delete' or  '--test-label' option")
		os.exit()
	else
		operation = set
	end
end

local function printTryDie(msg)
	print(msg)
	print("Try 'tar --help' or 'tar --usage' for more information.")
	os.exit()
end

local function printFail(msg)
	print(msg)
	print("tar: Error is not recoverable: exiting now")
	os.exit()
end

local function validateArgument(k,v)
	if v == true then
		printTryDie("tar: option '--" .. k .. "' requires an argument")
	end
end

local function validateNoArgument(k,v)
	if v ~= true then
		printTryDie("tar: option '--" .. k .. "' doesn't allow an argument")
	end
end

for k,v in pairs(options) do
	if k == "help" or k == "usage" then
		print(usage)
		return
	elseif k == "A" or k == "catenate" or k == "concatenate" then
		setOp("A")
	elseif k == "c" or k == "create" then
		setOp("c")
	elseif k == "d" or k == "diff" or k == "compare" then
		setOp("d")
	elseif k == "delete" then
		setOp("del")
	elseif k == "r" or k == "append" then
		setOp("r")
	elseif k == "t" or k == "list" then
		setOp("t")
	elseif k == "test-label" then
		setOp("tl")
	elseif k == "u" or k == "update" then
		setOp("u")
	elseif k == "x" or k == "extract" or k == "get" then
		setOp("x")
	elseif k == "f" or k == "file" then
		filename = v
	elseif k == "v" or k == "verbose" then
		validateNoArgument(k,v)
		verbose = true
	elseif k == "label" then
		validateArgument(k,v)
		label = v
	else
		printTryDie("tar: unrecognized option '--" .. k .. "'")
	end
end

if filename == true then
	if #args == 0 then
		printTryDie("tar: option '-f' or '--file' requires an argument")
	end
	filename = args[1]
	table.remove(args,1)
end

local function openFile(mode)
	local err
	if filename then
		if mode == "r" then
			file, err = io.open(shell.resolve(filename),"rb")
		else
			file, err = io.open(shell.resolve(filename),"wb")
		end
	else
		if mode == "r" then
			file = io.stdin
		else
			file = io.stdout
		end
	end
	if not file then
		printFail("tar: " .. (filename or "(no filename)") .. ": Cannot open: " .. err)
	end
end

local function decodeBlock(block)
	local info = {}
	-- Decode
	info.name =   block:sub(  1,100):match("(.-)%z")
	info.mode =   tonumber(block:sub(101,108):match("(.-)[%z ]"),8)
	info.uid =    tonumber(block:sub(108,116):match("(.-)[%z ]"),8)
	info.gid =    tonumber(block:sub(117,124):match("(.-)[%z ]"),8)
	info.size =   tonumber(block:sub(125,136):match("(.-)[%z ]") or "0",8)
	info.time =   tonumber(block:sub(137,148):match("(.-)[%z ]"),8)
	info.chksum = tonumber(block:sub(149,156):match("(.-)[%z ]"),8)
	info.type =   block:sub(157,157)
	info.lname =  block:sub(158,257):match("(.-)%z")
	info.ustar =  block:sub(258,263)
	info.ver =    block:sub(264,265):match("(.-)%z")
	info.uname =  block:sub(266,297):match("(.-)%z")
	info.gname =  block:sub(298,329):match("(.-)%z")
	info.dmaj =   tonumber(block:sub(330,337):match("(.-)[%z ]"),8)
	info.dmin =   tonumber(block:sub(338,345):match("(.-)[%z ]"),8)
	info.prefix = block:sub(346,500):match("(.-)%z")
	
	-- Patches
	info.mode = info.mode or 0
	info.size = info.size or 0
	info.type = info.type
	
	-- Ustar patches
	if info.ustar == "ustar " then
		info.filename = info.prefix .. info.name
	else
		info.filename = info.name
		info.uname = "ocuser"
		info.gname = "ocuser"
		if info.filename:sub(-1,-1) == "/" then
			info.type = "5"
		end
	end
	
	return info
end

local zeroblock = string.rep("\0",512)

if operation == nil then
	printTryDie("tar: You must specify one of the '-Acdtrux', '--delete' or '--test-label' options")
elseif operation == "A" then
	-- TODO: How to handle multiple labels?
	print("tar: Operation 'concatenate' unimplemented.")
elseif operation == "c" then
	print("tar: Operation 'create' unimplemented.")
elseif operation == "d" then
	print("tar: Operation 'compare' unimplemented.")
elseif operation == "del" then
	print("tar: Operation 'delete' unimplemented.")
elseif operation == "r" then
	print("tar: Operation 'append' unimplemented.")
elseif operation == "t" then
	openFile("r")
	local toformat = {}
	local map = {
		["0"]="-",
		["1"]="h",
		["2"]="l",
		["3"]="c",
		["4"]="b",
		["5"]="d",
		["6"]="p",
		["7"]="C",
		["V"]="V",
	}
	while true do
		local block = file:read(512)
		if block == nil then break end
		cblock = cblock + 1
		if block == zeroblock then
			if zblock then
				zblock = false
				break
			else
				zblock = true
			end
		else
			if zblock then
				print("tar: A lone zero block at " .. cblock - 1)
				zblock = false
			end
			local info = decodeBlock(block)
			if verbose then
				local mode = map[info.type] or "?"
				for i = 8, 0, -1 do
					local bit = math.floor(info.mode / (2^i))%2
					mode = mode .. (bit == 1 and (i%3 == 0 and "x" or (i%3 == 1 and "w" or "r")) or "-")
				end
				local date = os.date("%Y-%m-%d %H:%M", info.time)
				table.insert(toformat, {mode, info.uname .. "/" .. info.gname, info.size, date, info.filename .. (info.type == "V" and "--Volume Header--" or "")})
			else
				print(info.filename)
			end
			local blocks = math.ceil(info.size / 512)
			if blocks > 0 then
				cblock = cblock + blocks
				file:seek("cur",blocks * 512)
			end
		end
	end
	if verbose then
		format.tabulate(toformat, {0,0,1,0,2})
		for j, entry in ipairs(toformat) do
			for i = 1, 5 do
				io.write(entry[i])
				if i < 5 then
					io.write(" ")
				end
			end
			io.write("\n")
		end
	end
	if zblock then
		print("tar: Archive ends in a lone zero block")
		zblock = false
	end
elseif operation == "tl" then
	print("tar: Operation 'test-label' unimplemented.")
elseif operation == "u" then
	print("tar: Operation 'update' unimplemented.")
elseif operation == "x" then
	openFile("r")
	while true do
		local block = file:read(512)
		if block == nil then break end
		cblock = cblock + 1
		if block == zeroblock then
			if zblock then
				zblock = false
				break
			else
				zblock = true
			end
		else
			if zblock then
				print("tar: A lone zero block at " .. cblock - 1)
				zblock = false
			end
			local info = decodeBlock(block)
			local blocks = math.ceil(info.size / 512)
			if verbose then
				print(info.filename)
			end
			if info.type == "0" then
				local ofile,err = io.open(shell.resolve(info.filename),"wb")
				if ofile then
					for i = 1,blocks do
						local block = file:read(512)
						local get = math.min(512, info.size - (i - 1)*512)
						ofile:write(block:sub(1,get))
					end
					ofile:close()
				else
					print("tar: Failed to open " .. info.filename .. ": " .. err)
					if blocks > 0 then
						file:seek("cur",blocks * 512)
					end
				end
			elseif info.type == "1" or info.type == "2" then
				local stat, err = fs.link(shell.resolve(info.lname), shell.resolve(info.filename))
				if not stat then
					print("tar: Failed to link " .. info.filename .. ": " .. err)
				end
			elseif info.type == "5" then
				local stat, err = fs.makeDirectory(shell.resolve(info.filename))
				if not stat then
					print("tar: Failed to create " .. info.filename .. ": " .. err)
				end
			else
				print("tar: Not extracting " .. info.filename .. " of type " .. info.type)
			end
			if blocks > 0 then
				cblock = cblock + blocks
			end
		end
	end
	if zblock then
		print("tar: Archive ends in a lone zero block")
		zblock = false
	end
end
