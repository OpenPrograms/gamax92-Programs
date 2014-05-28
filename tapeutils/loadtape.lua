local fs = require("filesystem")
local component = require("component")
local term = require("term")
local shell = require("shell")

local arg, options = shell.parse(...)
if #arg < 1 then
	print("Usage: loadtape filename")
	print("Options:")
	print(" --speed=n       set playback speed")
	print(" --address=addr  use tapedrive at address")
	return
end
arg[1] = shell.resolve(arg[1])
if not fs.exists(arg[1]) then
	error("No such file", 2)
end
if options.speed and (tonumber(options.speed) == nil or tonumber(options.speed) < 0.25 or tonumber(options.speed) > 2) then
	error("Invalid speed", 2)
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
	error("No tape present", 2)
end
local filesize = fs.size(arg[1])
if td.getSize() < filesize then
	print("File is too large for tape, truncating")
	filesize = td.getSize()
end
local file = fs.open(arg[1],"rb")
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
if options.speed then
	local speed = tonumber(options.speed)
	td.setSpeed(speed)
	print("Tape playback speed set to " .. speed .. ", " .. speed * 32768 .. "Hz")
end
