local arg = { ... }
if #arg < 1 then
	print("Usage: setspeed speed [address]")
	return
end
if tonumber(arg[1]) == nil or tonumber(arg[1]) < 0.25 or tonumber(arg[1]) > 2 then
	error("Invalid speed", 2)
end
local component = require("component")
if #arg >= 2 then
	local found = false
	for k,v in component.list("tape_drive") do
		if v == "tape_drive" and k == arg[2] then
			found = true
			break
		end
	end
	if not found then
		error("No such tape drive", 2)
	end
end
local speed = tonumber(arg[1])
local td
if #arg >= 2 then
	td = component.proxy(arg[2])
else
	td = component.tape_drive
end
if not td.isReady() then
	error("No tape present",2)
end
td.setSpeed(speed)
print("Tape playback speed set to " .. speed .. ", " .. speed * 32768 .. "Hz")
