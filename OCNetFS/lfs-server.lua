-- Warning, given a bug in this program, the client could potentially access files outside the folder
-- Best to chroot/limit permissions for this server
local server, client, totalspace, curspace, port, label, change, debug, recurseCount
local hndls = {}

-- Configuration
totalspace = math.huge
curspace = 0
port = 14948
label = "netfs"
change = false
debug = false

local socket = require("socket")
local lfs = require("lfs")

local function sanitizePath(path)
	local currentdir = lfs.currentdir()
	if currentdir:sub(-1,-1):find("[\\/]") then
		currentdir = currentdir:sub(1,-2)
	end
	path = ("/" .. path):gsub("\\", "/")
	local tPath = {}
	for part in path:gmatch("[^/]+") do
   		if part ~= "" and part ~= "." then
   			if part == ".." then
   				table.remove(tPath)
   			else
   				table.insert(tPath, part)
   			end
   		end
	end
	local newpath = currentdir .. "/" .. table.concat(tPath, "/")
	return newpath
end

local function getDirectoryItems(path)
	local stat,iter,obj = pcall(lfs.dir,path)
	if not stat then
		print(iter)
		return {}
	end
	local output = {}
	for entry in function() return iter(obj) end do
		if entry ~= "." and entry ~= ".." then
			output[#output + 1] = entry
		end
	end
	return output
end

function recurseCount(path)
	local count = 0
	local list = getDirectoryItems(path)
	for i = 1,#list do
		if lfs.attributes(path .. "/" .. list[i],"mode") == "directory" then
			count = count + 512 + recurseCount(path .. "/" .. list[i])
		else
			local size = lfs.attributes(path .. "/" .. list[i],"size")
			if size == nil then
				print(path .. "/" .. list[i])
				print(lfs.attributes(path .. "/" .. list[i],"mode"))
			end
			count = count + (lfs.attributes(path .. "/" .. list[i],"size") or 0)
		end
	end
	return count
end

local arg = { ... }

print("Warning, I take no responsibility if a bug in this program eats your computer\nIt's your fault for running it under such a permission\nThough, bug reports and fixes are welcomed ;)\n")

if change then
	print("Warning, modification enabled on potentially dangerous program\n")
end

print("Calculating current space usage ...")
curspace = recurseCount(sanitizePath("/"))

local stat
stat, server = pcall(assert,socket.bind("*", port))
if not stat then
	print("Failed to get default port " .. port .. ": " .. server)
	server = assert(socket.bind("*", 0))
end
local sID, sPort = server:getsockname()
server:settimeout(1)

print("Binded to " .. sID .. ":" .. sPort)

local ots = tostring
function tostring(obj)
	if obj == math.huge then
		return "math.huge"
	elseif obj == -math.huge then
		return "-math.huge"
	elseif obj ~= obj then
		return "0/0"
	else
		return ots(obj)
	end
end

-- Unserialize without loadstring, for security purposes.
-- Not very robust but gets the job done.
local unserialize
function unserialize(str)
	if type(str) ~= "string" then
		error("bad argument #1: string expected, got " .. type(str),2)
	end
	if str:sub(1,1) == "{" and str:sub(-1,-1) == "}" then -- table
		local gen = {}
		local block = str:sub(2,-2) .. ","
		for piece in block:gmatch("(.-),") do
			if piece:find("^%[.-%]=.*") then
				local key, value = piece:find("^%[(.-)%]=(.*)")
				gen[unserialize(key)] = unserialize(value)
			else
				gen[#gen + 1] = unserialize(piece)
			end
		end
		return gen
	elseif str:sub(1,1) == "\"" and str:sub(-1,-1) == "\"" then -- string
		return str:sub(2,-2):gsub("\\a","\a"):gsub("\\b","\b"):gsub("\\f","\f"):gsub("\\n","\n"):gsub("\\r","\r"):gsub("\\t","\t"):gsub("\\v","\v"):gsub("\\\"","\""):gsub("\\'","'"):gsub("\\\n","\n"):gsub("\\0","\0"):gsub("\\(%d%d?%d?)",string.char):gsub("\\\\","\\")
	elseif tonumber(str) then
		return tonumber(str)
	elseif str == "0/0" then
		return 0/0
	elseif str == "math.huge" then
		return math.huge
	elseif str == "-math.huge" then
		return -math.huge
	elseif str == "true" then
		return true
	elseif str == "false" then
		return false
	elseif str == "nil" or str == "" then
		return nil
	else
		error("Cannot unserialize " .. str,2)
	end
end

local function sendData(msg)
	if debug then
		print(" < " .. msg)
	end
	client:send(msg .. "\n")
end

local function checkArg(pos,obj,what)
	if type(obj) ~= what then
		sendData("bad argument #" .. pos .. " (" .. what .. " expected, got " .. type(obj) .. ")")
		return false
	end
	return true
end

local function update()
	if client == nil then
		client = server:accept()
		if client ~= nil then
			local ci,cp = client:getpeername()
			print("User connected from: " .. ci .. ":" .. cp)
		end
	else
		local line, err = client:receive()
		if not line then
			print("socket receive gave: " .. err)
			if err ~= "closed" then
				pcall(client.close,client)
			end
			client = nil
			return
		end
		local ctrl = line:byte(1,1) - 31
		if debug then
			print(" > " .. ctrl .. "," .. line:sub(2))
		end
		if ctrl == -1 then
			print("User requested disconnect")
			client:close()
			client = nil
			return
		end
		local stat,ret = pcall(unserialize,line:sub(2))
		if not stat then
			if not debug then
				print(" > " .. ctrl .. "," .. line:sub(2))
			end
			print("Bad Input: " .. ret)
			sendData("{nil,\"bad input\"}")
			return
		end
		if type(ret) ~= "table" then
			if not debug then
				print(" > " .. ctrl .. "," .. line:sub(2))
			end
			print("Bad Input (exec): " .. type(ret))
			sendData("{nil,\"bad input\"}")
			return
		end
		if ctrl == 1 then -- size
			if not checkArg(1,ret[1],"string") then return end
			local size = lfs.attributes(sanitizePath(ret[1]),"size")
			sendData("{" .. (size or 0) .. "}")
		elseif ctrl == 2 then -- seek
			if not checkArg(1,ret[1],"number") then return end
			if not checkArg(2,ret[2],"string") then return end
			if not checkArg(3,ret[3],"number") then return end
			local fd = ret[1]
			if hndls[fd] == nil then
				sendData("{nil, \"bad file descriptor\"}")
			else
				local new = hndls[fd]:seek(ret[2],ret[3])
				sendData("{" .. new .. "}")
			end
		elseif ctrl == 3 then -- read
			if not checkArg(1,ret[1],"number") then return end
			if not checkArg(2,ret[2],"number") then return end
			local fd = ret[1]
			if hndls[fd] == nil then
				sendData("{nil, \"bad file descriptor\"}")
			else
				local data = hndls[fd]:read(ret[2])
				if type(data) == "string" and #data > 0 then
					sendData("{" .. string.format("%q",data):gsub("\\\n","\\n") .. "}")
				else
					sendData("{nil}")
				end
			end
		elseif ctrl == 4 then -- isDirectory
			if not checkArg(1,ret[1],"string") then return end
			sendData("{" .. tostring(lfs.attributes(sanitizePath(ret[1]),"mode") == "directory") .. "}")
		elseif ctrl == 5 then -- open
			if not checkArg(1,ret[1],"string") then return end
			if not checkArg(2,ret[2],"string") then return end
			local mode = ret[2]:sub(1,1)
			if (mode == "w" or mode == "a") and not change then
				sendData("{nil,\"file not found\"}") -- Yes, this is what it returns
			else
				local file, errorstr = io.open(ret[1], ret[2])
				if not file then
					sendData("{nil," .. string.format("%q",errorstr):gsub("\\\n","\\n") .. "}")
				else
					local randhand
					while true do
						randhand = math.random(1000000000,9999999999)
						if not hndls[randhand] then
							hndls[randhand] = file
							break
						end
					end
					sendData("{" .. randhand .. "}")
				end
			end
		elseif ctrl == 6 then -- spaceTotal
			sendData("{" .. tostring(totalspace) .. "}")
		elseif ctrl == 7 then -- setLabel
			if not checkArg(1,ret[1],"string") then return end
			if change then
				label = ret[1]
				sendData("{\"" .. label .. "\"}")
			else
				sendData("label is read only")
			end
		elseif ctrl == 8 then -- lastModified
			if not checkArg(1,ret[1],"string") then return end
			local modtime = lfs.attributes(sanitizePath(ret[1]),"modification")
			sendData("{" .. (modtime or 0) .. "}")
		elseif ctrl == 9 then -- close
			if not checkArg(1,ret[1],"number") then return end
			local fd = ret[1]
			if hndls[fd] == nil then
				sendData("{nil, \"bad file descriptor\"}")
			else
				hndls[fd]:close()
				hndls[fd] = nil
				sendData("{}")
			end
		elseif ctrl == 10 then -- rename
			if not checkArg(1,ret[1],"string") then return end
			if not checkArg(2,ret[2],"string") then return end
			if change then
				sendData("{" .. tostring(os.rename(sanitizePath(ret[1]),sanitizePath(ret[2])) == true) .. "}")
			else
				sendData("{false}")
			end
		elseif ctrl == 11 then -- isReadOnly
			sendData("{" .. tostring(not change) .. "}")
		elseif ctrl == 12 then -- exists
			if not checkArg(1,ret[1],"string") then return end
			sendData("{" .. tostring(lfs.attributes(sanitizePath(ret[1]),"mode") ~= nil) .. "}")
		elseif ctrl == 13 then -- getLabel
			sendData("{\"" .. label .. "\"}")
		elseif ctrl == 14 then -- spaceUsed
			-- TODO: Need to update this
			sendData("{" .. curspace .. "}")
		elseif ctrl == 15 then -- makeDirectory
			if not checkArg(1,ret[1],"string") then return end
			if change then
				sendData("{" .. tostring(lfs.mkdir(sanitizePath(ret[1]))) .. "}")
			else
				sendData("{false}")
			end
		elseif ctrl == 16 then -- list
			if not checkArg(1,ret[1],"string") then return end
			ret[1] = sanitizePath(ret[1])
			local list = getDirectoryItems(ret[1])
			local out = ""
			for i = 1,#list do
				if lfs.attributes(ret[1] .. "/" .. list[i],"mode") == "directory" then
					list[i] = list[i] .. "/"
				end
				out = out .. string.format("%q",list[i]):gsub("\\\n","\\n")
				if i < #list then
					out = out .. ","
				end
			end
			sendData("{{" .. out .. "}}")
		elseif ctrl == 17 then -- write
			if not checkArg(1,ret[1],"number") then return end
			if not checkArg(2,ret[2],"string") then return end
			local fd = ret[1]
			if hndls[fd] == nil then
				sendData("{nil, \"bad file descriptor\"}")
			else
				local success = hndls[fd]:write(ret[2])
				sendData("{" .. tostring(success) .. "}")
			end
		elseif ctrl == 18 then -- remove
			-- TODO: Recursive remove
			if not checkArg(1,ret[1],"string") then return end
			if change then
				if lfs.attributes(sanitizePath(ret[1]),"mode") == "directory" then
					sendData("{" .. tostring(lfs.rmdir(sanitizePath(ret[1]))) .. "}")
				else
					os.remove(sanitizePath(ret[1]))
				end
			else
				sendData("{false}")
			end
		else
			print("Unknown control: " .. ctrl)
		end
	end
end

while true do
	update()
end
