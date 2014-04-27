local component = require("component")
local term = require("term")
local shell = require("shell")
local arg, options = shell.parse(...)

if #arg > 0 then
	print("Usage: formattape")
	print("Options:")
	print(" --address=addr  use tapedrive at address")
	return
end
local td
if options.address then
	if type(options.address) ~= "string" or options.address == "" then
		error("Invalid address", 2)
	end
	local fulladdr = component.get(options.address)
	if fulladdr == nil then
		error("No component at address", 2)
	elseif component.type(fulladdr) ~= "tape_drive" then
		error("Component specified is a " .. component.type(fulladdr), 2)
	end
	td = component.proxy(fulladdr)
else
	td = component.tape_drive
end
if not td.isReady() then
	error("No tape present",2)
end
local tapeSize = td.getSize()
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
