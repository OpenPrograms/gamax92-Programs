local component = require("component")
if not component.isAvailable("debug") then
	errprint("Debug card is required")
	return
end

local player
io.stdout:write("Input player name: ")
while true do
	player = io.read()
	local health,err = component.debug.getPlayer(player).getHealth()
	if not health or err == "player is offline" then
		print("No such player")
	else
		print("Bound OCWE to " .. player)
		player = component.debug.getPlayer(player)
		break
	end
end

local world = component.debug.getWorld()

local info = {}

while true do
	io.stdout:write("> ")
	local line = io.read()
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
		parse[3] = parse[3] or "0"
		if not tonumber(parse[2]) or not tonumber(parse[3]) then
			print("Invalid argument, Expected: set ID [damage]")
		else
			local id = tonumber(parse[2])
			local damage = tonumber(parse[2])
			if not info.pos1 then
				print("Please set pos1")
			elseif not info.pos2 then
				print("Please set pos2")
			else
				local size = (math.abs(info.pos1[1]-info.pos2[1])+1) * (math.abs(info.pos1[2]-info.pos2[2])+1) * (math.abs(info.pos1[3]-info.pos2[3])+1)
				print("Setting " .. size .. " block" .. (size == 1 and "" or "s"))
				world.setBlocks(info.pos1[1],info.pos1[2],info.pos1[3],info.pos2[1],info.pos2[2],info.pos2[3],id,damage)
			end
		end
	else
		print("Unknown command: " .. parse[1])
	end
end
