local arg = { ... }
if #arg < 1 then
	print("Usage: loadtape filename [speed] [address]")
	return
end
local fs = require("filesystem")
if not fs.exists(arg[1]) then
	error("No such file", 2)
end
if #arg >= 2 and (tonumber(arg[2]) == nil or tonumber(arg[2]) < 0.25 or tonumber(arg[2]) > 2) then
	error("Invalid speed", 2)
end
local component = require("component")
if #arg >= 3 then
	local found = false
	for k,v in component.list("tape_drive") do
		if v == "tape_drive" and k == arg[3] then
			found = true
			break
		end
	end
	if not found then
		error("No such tape drive", 2)
	end
end
local speed = tonumber(arg[2]) or 1
local td
if #arg >= 3 then
	td = component.proxy(arg[3])
else
	td = component.tape_drive
end
if not td.isReady() then
	error("No tape present",2)
end
local filesize = fs.size(arg[1])
if td.getSize() < filesize then
	print("File is too large for tape, truncating")
	filesize = td.getSize()
end
local file = fs.open(arg[1],"rb")
local term = require("term")
local counter = 0
if td.getState() ~= "STOPPED" then
	print("Stopping tape ...")
	td.stop()
end
print("Rewinding tape ...")
td.seek(-math.huge)
while true do
	local data = file:read(math.min(filesize - counter, 8192))
	if data == nil then break end
	counter = counter + #data
	local x,y = term.getCursor()
	term.setCursor(1, y)
	term.write("Loaded " .. counter .. "/" .. filesize .. " (" .. math.ceil(counter/filesize*100) .. "%) bytes")
	td.write(data)
	if counter >= filesize then break end
end
file:close()
print("\nRewinding tape ...")
td.seek(-math.huge)
td.setSpeed(speed)
print("Tape speed set to " .. speed .. ", " .. speed * 32768 .. "Hz")
