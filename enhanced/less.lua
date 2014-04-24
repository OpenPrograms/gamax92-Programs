local component = require("component")
local keyboard = require("keyboard")
local shell = require("shell")
local term = require("term")
local text = require("text")
local unicode = require("unicode")

local args = shell.parse(...)
if #args == 0 then
	io.write("Usage: less <filename>")
	return
end

local file, reason = io.open(shell.resolve(args[1]))
if not file then
	io.stderr:write(reason)
	return
end

local lines = {}
local line = nil
local w, h = component.gpu.getResolution()
term.clear()
term.setCursorBlink(false)
while true do
	if not line then
		line = file:read("*l")
		if not line then
			break 
		end
	end
	local wrapped
	wrapped, line = text.wrap(text.detab(line), w, w)
	table.insert(lines, wrapped)
end

local i = 1
local operation = "none"
while true do
	if operation == "page" then
		i = math.min(i + h - 1, #lines - h + 2)
	elseif operation == "down" then
		if i < #lines - h + 2 then
			i = i + 1
		end
	elseif operation == "up" then
		if i > 1 then
			i = i - 1
		end
	end
	w, h = component.gpu.getResolution()
	term.setCursor(1, 1)
	for j = i, i + h - 2 do
		term.clearLine()
		io.write((lines[j] or "~") .. "\n")
	end
	term.setCursor(1, h)
	term.write(":")
	term.setCursorBlink(true)
	while true do
		local event, address, char, code = coroutine.yield("key_down")
		if component.isPrimary(address) then
			if code == keyboard.keys.q then
				term.setCursorBlink(false)
				term.clearLine()
				return
			elseif code == keyboard.keys.space then
				operation = "page"
				break
			elseif code == keyboard.keys.up then
				operation = "up"
				break
			elseif code == keyboard.keys.down or code == keyboard.keys.enter then
				operation = "down"
				break
			end
		end
	end
end