local fs = require("filesystem")
local shell = require("shell")

local args, options = shell.parse(...)

local operation, filename, label, file
local verbose = false

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
			file, err = io.open(filename,"rb")
		else
			file, err = io.open(filename,"wb")
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
	info.type =   block:sub(157,157):match("(.-)%z")
	info.lname =  block:sub(158,257):match("(.-)%z")
	info.ustar =  block:sub(258,263)
	info.ver =    block:sub(264,265):match("(.-)%z")
	info.uname =  block:sub(266,297):match("(.-)%z")
	info.gname =  block:sub(298,329):match("(.-)%z")
	info.dmaj =   tonumber(block:sub(330,337):match("(.-)[%z ]"),8)
	info.dmin =   tonumber(block:sub(338,345):match("(.-)[%z ]"),8)
	info.prefix = block:sub(346,500):match("(.-)%z")
	
	-- Patches
	info.size = info.size or 0
	
	-- Ustar patches
	if info.ustar == "ustar " then
		info.filename = info.prefix .. info.name
	else
		info.filename = info.name
		info.uname = "ocuser"
		info.gname = "ocuser"
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
	while true do
		local block = file:read(512)
		if block == nil then break end
		local info = decodeBlock(block)
		if verbose then
			print(info.filename)
		else
			print(info.filename)
		end
		local blocks = math.ceil(info.size / 512)
		if blocks > 0 then
			file:seek("cur",blocks * 512)
		end
	end
elseif operation == "tl" then
	print("tar: Operation 'test-label' unimplemented.")
elseif operation == "u" then
	print("tar: Operation 'update' unimplemented.")
elseif operation == "x" then
	print("tar: Operation 'extract' unimplemented.")
end
