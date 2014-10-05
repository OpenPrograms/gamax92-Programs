local component = require("component")
if not component.isAvailable("debug") then
	errprint("Debug card is required")
	return
end

local player, username
io.stdout:write("Input player name: ")
while true do
	player = io.read()
	local health,err = component.debug.getPlayer(player).getHealth()
	if not health or err == "player is offline" then
		print("No such player")
		io.stdout:write("Input player name: ")
	else
		print("Bound OCWE to " .. player)
		username = player
		player = component.debug.getPlayer(player)
		break
	end
end

local world = component.debug.getWorld()

local info = {}

local function decodeBlock(block)
	if block:match(".*:.+") then
		local id,damage = block:match("(.*):(.+)")
		if tonumber(id) ~= nil and tonumber(damage) ~= nil then
			return tonumber(id), tonumber(damage)
		end
	else
		if tonumber(block) ~= nil then
			return tonumber(block), 0
		end
	end
end

while true do
	io.stdout:write("> ")
	local line = io.read()
	if not line then break end
	local parse = {}
	for item in (line .. " "):gmatch("(.-) ") do
		if item ~= "" then
			parse[#parse + 1] = item
		end
	end
	if parse[1] == nil then
	elseif parse[1] == "pos1" then
		local pX,pY,pZ = player.getPosition()
		if not pX then
			print("Unexpected error: " .. pY)
		else
			pX,pY,pZ = math.floor(pX),math.floor(pY),math.floor(pZ)
			if info.pos1 == nil then
				info.pos1 = {}
			end
			info.pos1[1] = pX
			info.pos1[2] = pY
			info.pos1[3] = pZ
			local size
			if info.pos1 and info.pos2 then
				size = (math.abs(info.pos1[1]-info.pos2[1])+1) * (math.abs(info.pos1[2]-info.pos2[2])+1) * (math.abs(info.pos1[3]-info.pos2[3])+1)
			end
			print("Set pos1 to (" .. pX .. "," .. pY .. "," .. pZ .. ")" .. (size and (" (" .. size .. " blocks)") or ""))
		end
	elseif parse[1] == "pos2" then
		local pX,pY,pZ = player.getPosition()
		if not pX then
			print("Unexpected error: " .. pY)
		else
			pX,pY,pZ = math.floor(pX),math.floor(pY),math.floor(pZ)
			if info.pos2 == nil then
				info.pos2 = {}
			end
			info.pos2[1] = pX
			info.pos2[2] = pY
			info.pos2[3] = pZ
			local size
			if info.pos1 and info.pos2 then
				size = (math.abs(info.pos1[1]-info.pos2[1])+1) * (math.abs(info.pos1[2]-info.pos2[2])+1) * (math.abs(info.pos1[3]-info.pos2[3])+1)
			end
			print("Set pos2 to (" .. pX .. "," .. pY .. "," .. pZ .. ")" .. (size and (" (" .. size .. " blocks)") or ""))
		end
	elseif parse[1] == "set" then
		local id, damage = decodeBlock(parse[2])
		if parse[2] == nil then
			print("Invalid argument, Expected: set block")
		elseif not id or not damage then
			print("Invalid block code")
		elseif not info.pos1 then
			print("Please set pos1")
		elseif not info.pos2 then
			print("Please set pos2")
		else
			local size = (math.abs(info.pos1[1]-info.pos2[1])+1) * (math.abs(info.pos1[2]-info.pos2[2])+1) * (math.abs(info.pos1[3]-info.pos2[3])+1)
			print("Setting " .. size .. " block" .. (size == 1 and "" or "s"))
			world.setBlocks(info.pos1[1],info.pos1[2],info.pos1[3],info.pos2[1],info.pos2[2],info.pos2[3],id,damage)
		end
	elseif parse[1] == "replace" then
		local fid, fdamage = decodeBlock(parse[2])
		local tid, tdamage = decodeBlock(parse[3])
		if parse[2] == nil or parse[3] == nil then
			print("Invalid argument, Expected: replace from-block to-block")
		elseif not fid or not fdamage then
			print("Invalid from-block code")
		elseif not tid or not tdamage then
			print("Invalid to-block code")
		elseif not info.pos1 then
			print("Please set pos1")
		elseif not info.pos2 then
			print("Please set pos2")
		else
			local blocks = 0
			
			local x1,x2 = math.min(info.pos1[1],info.pos2[1]),math.max(info.pos1[1],info.pos2[1])
			local y1,y2 = math.min(info.pos1[2],info.pos2[2]),math.max(info.pos1[2],info.pos2[2])
			local z1,z2 = math.min(info.pos1[3],info.pos2[3]),math.max(info.pos1[3],info.pos2[3])
			
			for y = y1,y2 do
				for x = x1,x2 do
					for z = z1,z2 do
						local cid = world.getBlockId(x,y,z)
						local cdamage = world.getMetadata(x,y,z)
						if cid == fid and cdamage == fdamage then
							world.setBlock(x,y,z,tid,tdamage)
							blocks = blocks + 1
						end
					end
				end
			end
			print("Replaced " .. blocks .. " block" .. (blocks == 1 and "" or "s"))
		end
	elseif parse[1] == "distr" then
		if not info.pos1 then
			print("Please set pos1")
		elseif not info.pos2 then
			print("Please set pos2")
		else
			local size = (math.abs(info.pos1[1]-info.pos2[1])+1) * (math.abs(info.pos1[2]-info.pos2[2])+1) * (math.abs(info.pos1[3]-info.pos2[3])+1)
		
			local x1,x2 = math.min(info.pos1[1],info.pos2[1]),math.max(info.pos1[1],info.pos2[1])
			local y1,y2 = math.min(info.pos1[2],info.pos2[2]),math.max(info.pos1[2],info.pos2[2])
			local z1,z2 = math.min(info.pos1[3],info.pos2[3]),math.max(info.pos1[3],info.pos2[3])

			local stats = {}
			
			for y = y1,y2 do
				for x = x1,x2 do
					for z = z1,z2 do
						local cid = world.getBlockId(x,y,z)
						local cdamage = world.getMetadata(x,y,z)
						local id = cid .. ":" .. cdamage
						if stats[id] == nil then
							stats[id] = 0
						end
						stats[id] = stats[id] + 1
					end
				end
			end
			local stats2 = {}
			for k,v in pairs(stats) do	
				stats2[#stats2 + 1] = {k,v}
			end
			table.sort(stats2,function(a,b) return a[2] < b[2] end)
			for i = 1,#stats2 do
				print(string.format("%-8d%s",stats2[i][2],stats2[i][1]))
			end
		end
	elseif parse[1] == "walls" then
		local id, damage = decodeBlock(parse[2])
		if parse[2] == nil then
			print("Invalid argument, Expected: walls block")
		elseif not id or not damage then
			print("Invalid block code")
		elseif not info.pos1 then
			print("Please set pos1")
		elseif not info.pos2 then
			print("Please set pos2")
		else
			local size = "NaN" -- >_> why is this confusing.
			print("Setting " .. size .. " block" .. (size == 1 and "" or "s"))
			world.setBlocks(info.pos1[1],info.pos1[2],info.pos1[3],info.pos1[1],info.pos2[2],info.pos2[3],id,damage)
			world.setBlocks(info.pos2[1],info.pos1[2],info.pos1[3],info.pos2[1],info.pos2[2],info.pos2[3],id,damage)
			world.setBlocks(info.pos1[1],info.pos1[2],info.pos1[3],info.pos2[1],info.pos2[2],info.pos1[3],id,damage)
			world.setBlocks(info.pos1[1],info.pos1[2],info.pos2[3],info.pos2[1],info.pos2[2],info.pos2[3],id,damage)
		end
	elseif parse[1] == "tp" then
		if parse[2] == nil then
			print("Invalid argument, Expected: tp player")
		else
			local top = component.debug.getPlayer(parse[2])
			local health,err = top.getHealth()
			if not health or err == "player is offline" then
				print("No such player")
			else
				print("Teleporting " .. username .. " to " .. parse[2])
				tX,tY,tZ = top.getPosition()
				player.setPosition(tX,tY,tZ)
			end
		end
	elseif parse[1] == "kill" then
		if parse[2] == nil then
			print("Invalid argument, Expected: kill player")
		else
			local top = component.debug.getPlayer(parse[2])
			local health,err = top.getHealth()
			if not health or err == "player is offline" then
				print("No such player")
			else
				print("Killing " .. parse[2])
				top.setHealth(-1)
			end
		end
	elseif parse[1] == "quit" then
		print("Goodbye!")
		return
	else
		print("Unknown command: " .. parse[1])
	end
end
