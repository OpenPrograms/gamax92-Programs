local arg = { ... }
if #arg < 1 then
	print("Usage: dumptape filename [address]")
	return
end
local fs = require("filesystem")
if fs.exists(arg[1]) then
	error("File exists", 2)
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
local td
if #arg >= 2 then
	td = component.proxy(arg[2])
else
	td = component.tape_drive
end
if not td.isReady() then
	error("No tape present",2)
end
local tapesize = td.getSize()
local file = fs.open(arg[1],"wb")
if file == nil then
	error("Could not open file",2)
end
local term = require("term")
local counter = 0
if td.getState() ~= "STOPPED" then
	print("Stopping tape ...")
	td.stop()
end
print("Rewinding tape ...")
td.seek(-math.huge)
while true do
	local data = td.read(8192)
	if data == nil then break end
	counter = counter + #data
	local x,y = term.getCursor()
	term.setCursor(1, y)
	term.write("Read " .. counter .. "/" .. tapesize .. " (" .. math.ceil(counter/tapesize*100) .. "%) bytes")
	local stat = file:write(data)
	if stat ~= true then
		file:close()
		print("\nRewinding tape ...")
		td.seek(-math.huge)
		error("Failed to write to file",2)
	end
	if counter >= tapesize then break end
end
file:close()
print("\nRewinding tape ...")
td.seek(-math.huge)
