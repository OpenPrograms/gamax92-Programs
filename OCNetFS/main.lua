local socket = require("socket")

local server, client, totalspace, currspace, label, change
local hndls = {}

local recurseCount
function recurseCount(path)
end

function love.load(arg)
	totalspace = math.huge
	curspace = 0
	label = "netfs"
	change = false
	
	print("Calculating current space usage ...")
	curspace = recurseCount("/")

	server = assert(socket.bind("*", 0))
	local sID, sPort = server:getsockname()
	server:settimeout(1)

	print("Binded to " .. sID .. ":" .. sPort)
end

local ots = tostring
function tostring(obj)
	if obj == math.huge then
		return "math.huge"
	elseif obj == -math.huge then
		return "math.huge"
	elseif obj ~= obj then
		return "0/0"
	else
		return ots(obj)
	end
end

function love.update()
	if client == nil then
		client = server:accept()
		if client ~= nil then
			local ci,cp = client:getpeername()
			print("User connected from: " .. ci .. ":" .. cp)
		end
	else
		local line = client:receive()
		local ctrl = line:byte(1,1)
		print(" > " .. ctrl .. "," .. line:sub(2))
		local retfn,err = loadstring("return " .. line:sub(2))
		if retfn == nil then
			print("Bad Input: " .. err)
			client:send("{nil,\"bad input\"}\n")
			return
		end
		local ret = retfn()
		if type(ret) ~= "table" then
			print("Bad Input (exec): " .. type(ret))
			client:send("{nil,\"bad input\"}\n")
			return
		end
		if ctrl == 1 then -- size
			local size = love.filesystem.getSize(ret[1])
			client:send("{" .. size or 0 .. "}\n")
		elseif ctrl == 2 then -- seek
			local fd = ret[1]
			if hndls[fd] == nil then
				client:send("{nil, \"bad file descriptor\"}\n")
			else
				if ret[2] == "set" then
					hndls[fd]:seek(ret[3])
				elseif ret[2] == "cur" then
					hndls[fd]:seek(hndls[fd]:tell() + ret[3])
				elseif ret[2] == "end" then
					hndls[fd]:seek(hndls[fd]:getSize() + ret[3])
				end
				client:send("{" .. hndls[fd]:tell() .. "}\n")
			end
		elseif ctrl == 3 then -- read
			local fd = ret[1]
			if hndls[fd] == nil then
				client:send("{nil, \"bad file descriptor\"}\n")
			else
				local data = hndls[fd]:read(ret[2])
				if type(data) == "string" and #data > 0 then
					client:send("{" .. string.format("%q",data):gsub("\\\n","\\n") .. "}\n")
				else
					client:send("{nil}\n")
				end
			end
		elseif ctrl == 4 then -- isDirectory
			client:send("{" .. tostring(love.filesystem.isDirectory(ret[1])) .. "}\n")
		elseif ctrl == 5 then -- open
			local mode = ret[2]:sub(1,1)
			if mode == "w" or mode == "a" and not change then
				client:send("{nil,\"file not found\"}\n") -- Yes, this is what it returns
			else
				local file, errorstr = love.filesystem.newFile(ret[1], ret[2])
				if not file then
					client:send("{nil," .. string.format("%q",errorstr):gsub("\\\n","\\n") .. "}\n")
				else
					local randhand
					while true do
						randhand = math.random(1000000000,9999999999)
						if not hndls[randhand] then
							hndls[randhand] = file
							break
						end
					end
					client:send("{" .. randhand .. "}\n")
				end
			end
		elseif ctrl == 6 then -- spaceTotal
			client:send("{" .. totalspace .. "}\n")
		elseif ctrl == 7 then -- setLabel
			-- TODO: Error to client
			if change then
				label = ret[1]
			end
			client:send("{\"" .. label .. "\"}\n")
		elseif ctrl == 8 then -- lastModified
			local modtime = love.filesystem.getLastModified(ret[1])
			client:send("{" .. modtime or 0 .. "}\n")
		elseif ctrl == 9 then -- close
			local fd = ret[1]
			if hndls[fd] == nil then
				client:send("{nil, \"bad file descriptor\"}\n")
			else
				hndls[fd]:close()
				hndls[fd] = nil
				client:send("{}\n")
			end
		elseif ctrl == 10 then -- rename
			-- TODO: Read, Write, Delete
			
		elseif ctrl == 11 then -- isReadOnly
			client:send("{" .. tostring(change) .. "}\n")
		elseif ctrl == 12 then -- exists
			client:send("{" .. tostring(love.filesystem.exists(ret[1])) .. "}\n")
		elseif ctrl == 13 then -- getLabel
			client:send("{\"" .. label .. "\"}\n")
		elseif ctrl == 14 then -- spaceUsed
			client:send("{" .. curspace .. "}\n")
		elseif ctrl == 15 then -- makeDirectory
			client:send("{" .. tostring(love.filesystem.mkdir(ret[1])) .. "}\n")
		elseif ctrl == 16 then -- list
			local list = love.filesystem.getDirectoryItems(ret[1])
			local out = ""
			for i = 1,#list do
				out = out .. string.format("%q",list[i]):gsub("\\\n","\\n")
				if i < #list then
					out = out .. ","
				end
			end
			client:send("{{" .. out .. "}}\n")
		elseif ctrl == 17 then -- write
			local fd = ret[1]
			if hndls[fd] == nil then
				client:send("{nil, \"bad file descriptor\"}\n")
			else
				local success = hndls[fd]:write(ret[2])
				client:send("{" .. tostring(success) .. "}\n")
			end
		elseif ctrl == 18 then -- remove
			-- TODO: Recursive remove
			if change then
				client:send("{" .. tostring(love.filesystem.remove(ret[1])) .. "}\n")
			else
				client:send("{false}\n")
			end
		else
			print("Unknown control: " .. ctrl)
		end
	end
end
