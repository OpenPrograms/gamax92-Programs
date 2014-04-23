local arg = { ... }
if #arg > 1 then
	print("Usage: formattape [address]")
	return
end
local component = require("component")
if #arg == 1 then
	local found = false
	for k,v in component.list("tape_drive") do
		if v == "tape_drive" and k == arg[1] then
			found = true
			break
		end
	end
	if not found then
		error("No such tape drive", 2)
	end
end
local td
if #arg == 1 then
	td = component.proxy(arg[1])
else
	td = component.tape_drive
end
if not td.isReady() then
	error("No tape present",2)
end
local tapeSize = td.getSize()
local term = require("term")
local counter = 0
if td.getState() ~= "STOPPED" then
	print("Stopping tape ...")
	td.stop()
end
print("Rewinding tape ...")
td.seek(-math.huge)
while true do
	local x,y = term.getCursor()
	term.setCursor(1, y)
	term.write("Written " .. counter .. "/" .. tapeSize .. " (" .. math.ceil(counter/tapeSize*100) .. "%) bytes")
	local written = td.write(string.rep(string.char(0), 8192))
	counter = counter + 8192
	if counter >= tapeSize then break end
end
print("\nRewinding tape ...")
td.seek(-math.huge)
