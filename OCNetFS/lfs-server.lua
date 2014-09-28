-- Warning, this makes no attempt to sandbox
-- Best to chroot/limit permissions for this server
local socket = require("socket")
local lfs = require("lfs")

local server, client, totalspace, currspace, label, change
local hndls = {}

local function sanitizePath(path)
	-- TODO: Actually sanitize
	local currentdir = lfs.currentdir()
	if currentdir:sub(-1,-1):find("[\\/]") then
		currentdir = currentdir:sub(1,-2)
	end
	if path:sub(1,1):find("[\\/]") then
		path = path:sub(2)
	end
	return lfs.currentdir() .. "/" .. path
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

local recurseCount
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

totalspace = math.huge
curspace = 0
label = "netfs"
change = false

print("Warning, this server makes no attempt to sandbox\nBest to chroot/limit permissions for this server\n")

print("Calculating current space usage ...")
curspace = recurseCount(sanitizePath("/"))

server = assert(socket.bind("*", 0))
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

local function sendData(msg)
	print(" < " .. msg)
	client:send(msg .. "\n")
end

while true do
	if client == nil then
		client = server:accept()
		if client ~= nil then
			local ci,cp = client:getpeername()
			print("User connected from: " .. ci .. ":" .. cp)
		end
	else
		local line = client:receive()
		local ctrl = line:byte(1,1) - 31
		print(" > " .. ctrl .. "," .. line:sub(2))
		local retfn,err = loadstring("return " .. line:sub(2))
		if retfn == nil then
			print("Bad Input: " .. err)
			sendData("{nil,\"bad input\"}")
			return
		end
		local ret = retfn()
		if type(ret) ~= "table" then
			print("Bad Input (exec): " .. type(ret))
			sendData("{nil,\"bad input\"}")
			return
		end
		if ctrl == 1 then -- size
			local size = lfs.attributes(sanitizePath(ret[1]),"size")
			sendData("{" .. size or 0 .. "}")
		elseif ctrl == 2 then -- seek
			local fd = ret[1]
			if hndls[fd] == nil then
				sendData("{nil, \"bad file descriptor\"}")
			else
				local new = hndls[fd]:seek(ret[2],ret[3])
				sendData("{" .. new .. "}")
			end
		elseif ctrl == 3 then -- read
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
			sendData("{" .. tostring(lfs.attributes(sanitizePath(ret[1]),"mode") == "directory") .. "}")
		elseif ctrl == 5 then -- open
			local mode = ret[2]:sub(1,1)
			if mode == "w" or mode == "a" and not change then
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
			-- TODO: Error to client
			if change then
				label = ret[1]
			end
			sendData("{\"" .. label .. "\"}")
		elseif ctrl == 8 then -- lastModified
			local modtime = lfs.attributes(sanitizePath(ret[1]),"modification")
			sendData("{" .. modtime or 0 .. "}")
		elseif ctrl == 9 then -- close
			local fd = ret[1]
			if hndls[fd] == nil then
				sendData("{nil, \"bad file descriptor\"}")
			else
				hndls[fd]:close()
				hndls[fd] = nil
				sendData("{}")
			end
		elseif ctrl == 10 then -- rename
			-- TODO: Read, Write, Delete
			
		elseif ctrl == 11 then -- isReadOnly
			sendData("{" .. tostring(change) .. "}")
		elseif ctrl == 12 then -- exists
			sendData("{" .. tostring(lfs.attributes(sanitizePath(ret[1]),"mode") ~= nil) .. "}")
		elseif ctrl == 13 then -- getLabel
			sendData("{\"" .. label .. "\"}")
		elseif ctrl == 14 then -- spaceUsed
			-- TODO: Need to update this
			sendData("{" .. curspace .. "}")
		elseif ctrl == 15 then -- makeDirectory
			if change then
				sendData("{" .. tostring(lfs.mkdir(sanitizePath(ret[1]))) .. "}")
			end
		elseif ctrl == 16 then -- list
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
			local fd = ret[1]
			if hndls[fd] == nil then
				sendData("{nil, \"bad file descriptor\"}")
			else
				local success = hndls[fd]:write(ret[2])
				sendData("{" .. tostring(success) .. "}")
			end
		elseif ctrl == 18 then -- remove
			-- TODO: Recursive remove
			if change then
				sendData("{" .. tostring(lfs.rmdir(sanitizePath(ret[1]))) .. "}")
			else
				sendData("{false}")
			end
		else
			print("Unknown control: " .. ctrl)
		end
	end
end
