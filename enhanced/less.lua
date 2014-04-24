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
local function drawPage()
	term.setCursor(1, 1)
	local buffer = ""
	for j = i, i + h - 2 do
		buffer = buffer .. (lines[j] or "~") .. "\n"
	end
	term.clear()
	io.write(buffer)
end
while true do
	w, h = component.gpu.getResolution()
	if operation == "none" then
		drawPage()
	elseif operation == "page" then
		local old = i
		i = math.min(i + h - 1, #lines - h + 2)
		if i ~= old then
			drawPage()
		end
	elseif operation == "down" then
		if i < #lines - h + 2 then
			i = i + 1
			component.gpu.copy(0, 1, w, h - 1, 0, -1)
			term.setCursor(1, h - 1)
			term.clearLine()
			io.write((lines[i + h - 2] or "~") .. "\n")
		end
	elseif operation == "up" then
		if i > 1 then
			i = i - 1
			component.gpu.copy(0, 0, w, h - 1, 0, 1)
			term.setCursor(1, 1)
			term.clearLine()
			io.write((lines[i] or "~") .. "\n")
		end
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
