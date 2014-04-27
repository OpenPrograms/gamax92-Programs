local fs = require("filesystem")
local component = require("component")
local term = require("term")
local shell = require("shell")

local arg, options = shell.parse(...)
if #arg < 1 then
	print("Usage: dumptape filename")
	print("Options:")
	print(" --address=addr  use tapedrive at address")
	return
end
if fs.exists(arg[1]) then
	error("File exists", 2)
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
local tapesize = td.getSize()
local file = fs.open(arg[1],"wb")
if file == nil then
	error("Could not open file",2)
end
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
