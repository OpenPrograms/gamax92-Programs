-- Configuration
local totalspace = math.huge
local curspace = 0
local port = 14948
local label = "netfs"
local change = false
local debug = false
-- End of Configuration

local socket = require("socket")

local recurseCount
function recurseCount(path)
	local count = 0
	local list = love.filesystem.getDirectoryItems(path)
	for i = 1,#list do
		if love.filesystem.isDirectory(path .. "/" .. list[i]) then
			count = count + 512 + recurseCount(path .. "/" .. list[i])
		else
			count = count + love.filesystem.getSize(path .. "/" .. list[i])
		end
	end
	return count
end

local recursiveDestroy
function recursiveDestroy(path)
	local state = true
	local list = love.filesystem.getDirectoryItems(path)
	for i = 1,#list do
		if love.filesystem.isDirectory(path .. "/" .. list[i]) then
			state = state and recursiveDestroy(path .. "/" .. list[i])
		else
			state = state and love.filesystem.remove(path .. "/" .. list[i])
		end
	end
	return state
end


if change then
	print("Modification enabled\n")
end

print("Calculating current space usage ...")
curspace = recurseCount("/")

local stat, server = pcall(assert,socket.bind("*", port))
if not stat then
	print("Failed to get default port " .. port .. ": " .. server)
	server = assert(socket.bind("*", 0))
end
local sID, sPort = server:getsockname()
server:settimeout(0)

print("Listening on " .. sID .. ":" .. sPort)

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
	if str:sub(1,1) == "{" and str:sub(-1,-1) == "}" then
		local i = 1
		local gen = {}
		local block = str:sub(2,-2) .. ","
		local piece = ""
		for part in block:gmatch("(.-),") do
			piece = piece .. part
			if (piece:sub(1,1) == "\"" and piece:sub(-1,-1) == "\"") or piece:sub(1,1) ~= "\"" then
				if piece:find("^%[.-%]=.*") then
					local key, value = piece:match("^%[(.-)%]=(.*)")
					gen[unserialize(key)] = unserialize(value)
				else
					gen[i] = unserialize(piece)
					i = i + 1
				end
				piece = ""
			else
				piece = piece .. ","
			end
		end
		if piece ~= "" then
			error("Cannot unserialize " .. piece,2)
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

local curclient
local function sendData(msg)
	if debug then
		local ip,port = curclient:getpeername()
		print(ip .. ":" .. port .. " < " .. msg)
	end
	curclient:send(msg .. "\n")
end

local function checkArg(pos,obj,what)
	if type(obj) ~= what then
		sendData("bad argument #" .. pos .. " (" .. what .. " expected, got " .. type(obj) .. ")")
		return false
	end
	return true
end

local function dprint(ctrl, line)
	print(" > " .. ctrl .. "," .. line:gsub("[^\32-\126]", function(a) return "\\"..a:byte() end))
end

-- do not change order
local ops={"size","seek","read","isDirectory","open","spaceTotal","setLabel","lastModified","close","rename","isReadOnly","exists","getLabel","spaceUsed","makeDirectory","list","write","remove"}

local sockets = {server}
local hndls = {}
function love.update()
	-- Check for new data or new clients
	local ready, _, err = socket.select(sockets,nil)
	if not ready then
		print("select gave " .. tostring(err))
		return
	end
	for _, client in ipairs(ready) do
		if client == server then
			client = server:accept()
			if client ~= nil then
				local ci,cp = client:getpeername()
				print("User connected from: " .. ci .. ":" .. cp)
				sockets[#sockets + 1] = client
				client:settimeout(0)
			end
			break
		end
		curclient = client
		local line, err = client:receive()
		if not line then
			print("socket receive gave: " .. err)
			if err ~= "closed" then
				pcall(client.close,client)
			end
			for i = 1,#sockets do
				if sockets[i] == client then
					table.remove(sockets, i)
					break
				end
			end
			break
		end
		local ctrl = line:byte(1,1) - 31
		ctrl = ops[ctrl] or ctrl
		local line = line:sub(2)
		if debug then
			dprint(ctrl, line)
		end
		local stat,ret = pcall(unserialize, line)
		if not stat then
			if not debug then
				dprint(ctrl, line)
			end
			print("Bad Input: " .. ret)
			sendData("{nil,\"bad input\"}")
			return
		end
		if type(ret) ~= "table" then
			if not debug then
				dprint(ctrl, line)
			end
			print("Bad Input (exec): " .. type(ret))
			sendData("{nil,\"bad input\"}")
			return
		end
		if ctrl == "size" then
			if not checkArg(1,ret[1],"string") then return end
			local size = love.filesystem.getSize(ret[1])
			sendData("{" .. (size or 0) .. "}")
		elseif ctrl == "seek" then
			if not checkArg(1,ret[1],"number") then return end
			if not checkArg(2,ret[2],"string") then return end
			if not checkArg(3,ret[3],"number") then return end
			local fd = ret[1]
			if hndls[fd] == nil then
				sendData("{nil, \"bad file descriptor\"}")
			else
				if ret[2] == "set" then
					hndls[fd]:seek(ret[3])
				elseif ret[2] == "cur" then
					hndls[fd]:seek(hndls[fd]:tell() + ret[3])
				elseif ret[2] == "end" then
					hndls[fd]:seek(hndls[fd]:getSize() + ret[3])
				end
				sendData("{" .. hndls[fd]:tell() .. "}")
			end
		elseif ctrl == "read" then
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
		elseif ctrl == "isDirectory" then
			if not checkArg(1,ret[1],"string") then return end
			sendData("{" .. tostring(love.filesystem.isDirectory(ret[1])) .. "}")
		elseif ctrl == "open" then
			if not checkArg(1,ret[1],"string") then return end
			if not checkArg(2,ret[2],"string") then return end
			local mode = ret[2]:sub(1,1)
			if (mode == "w" or mode == "a") and not change then
				sendData("{nil,\"file not found\"}") -- Yes, this is what it returns
			else
				local file, errorstr = love.filesystem.newFile(ret[1], mode)
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
		elseif ctrl == "spaceTotal" then
			sendData("{" .. tostring(totalspace) .. "}")
		elseif ctrl == "setLabel" then
			if not checkArg(1,ret[1],"string") then return end
			if change then
				label = ret[1]
				sendData("{\"" .. label .. "\"}")
			else
				sendData("label is read only")
			end
		elseif ctrl == "lastModified" then
			if not checkArg(1,ret[1],"string") then return end
			local modtime = love.filesystem.getLastModified(ret[1])
			sendData("{" .. (modtime or 0) .. "}")
		elseif ctrl == "close" then
			if not checkArg(1,ret[1],"number") then return end
			local fd = ret[1]
			if hndls[fd] == nil then
				sendData("{nil, \"bad file descriptor\"}")
			else
				hndls[fd]:close()
				hndls[fd] = nil
				sendData("{}")
			end
		elseif ctrl == "rename" then
			if not checkArg(1,ret[1],"string") then return end
			if not checkArg(2,ret[2],"string") then return end
			if change then
				local data = love.filesystem.read(ret[1])
				if not data then
					sendData("{false}")
				else
					local succ = love.filesystem.write(ret[2],data)
					if not succ then
						sendData("{false}")
					else
						local succ = love.filesystem.remove(ret[1])
						if not succ then
							local succ = love.filesystem.remove(ret[2])
							if not succ then
								print("WARNING: two copies of " .. ret[1] .. " now exist")
							end
							sendData("{false}")
						else
							sendData("{true}")
						end
					end
				end
			else
				sendData("{false}")
			end
		elseif ctrl == "isReadOnly" then
			sendData("{" .. tostring(not change) .. "}")
		elseif ctrl == "exists" then
			if not checkArg(1,ret[1],"string") then return end
			sendData("{" .. tostring(love.filesystem.exists(ret[1])) .. "}")
		elseif ctrl == "getLabel" then
			sendData("{\"" .. label .. "\"}")
		elseif ctrl == "spaceUsed" then
			-- TODO: Need to update this
			sendData("{" .. curspace .. "}")
		elseif ctrl == "makeDirectory" then
			if not checkArg(1,ret[1],"string") then return end
			if change then
				sendData("{" .. tostring(love.filesystem.createDirectory(ret[1])) .. "}")
			else
				sendData("{false}")
			end
		elseif ctrl == "list" then
			if not checkArg(1,ret[1],"string") then return end
			local list = love.filesystem.getDirectoryItems(ret[1])
			local out = ""
			for i = 1,#list do
				if love.filesystem.isDirectory(ret[1] .. "/" .. list[i]) then
					list[i] = list[i] .. "/"
				end
				out = out .. string.format("%q",list[i]):gsub("\\\n","\\n")
				if i < #list then
					out = out .. ","
				end
			end
			sendData("{{" .. out .. "}}")
		elseif ctrl == "write" then
			if not checkArg(1,ret[1],"number") then return end
			if not checkArg(2,ret[2],"string") then return end
			local fd = ret[1]
			if hndls[fd] == nil then
				sendData("{nil, \"bad file descriptor\"}")
			else
				local success = hndls[fd]:write(ret[2])
				sendData("{" .. tostring(success) .. "}")
			end
		elseif ctrl == "remove" then
			if not checkArg(1,ret[1],"string") then return end
			if change then
				sendData("{" .. tostring(recursiveDestroy(ret[1])) .. "}")
			else
				sendData("{false}")
			end
		else
			print("Unknown control: " .. ctrl)
		end
	end
end
