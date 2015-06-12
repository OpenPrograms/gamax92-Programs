--[[
nano clone based off GNU nano for OpenComputers
by Gamax92
--]]

local component = require("component")
local kbd = require("keyboard")
local keys = kbd.keys
local fs = require("filesystem")
local shell = require("shell")
local event = require("event")
local term = require("term")
local unicode = require("unicode")

local nanoVERSION = "1.0.0"

-- TODO: Replace with more gnuopt style parser
local args, opts = shell.parse(...)

-- TODO: Once above has been done, check for invalid arguments
-- Default options
local options = {
	fgcolor = 0xFFFFFF,
	bgcolor = 0x000000,
	tabsize = 8,
}
-- TODO: Parse arguments

-- TODO: Parse nanorc

local buffers = {}
local gpu = component.gpu
gpu.setForeground(options.fgcolor)
gpu.setBackground(options.bgcolor)
local gpuW, gpuH = gpu.getResolution()
gpu.fill(1,1,gpuW,gpuH," ")
term.setCursorBlink(true)

-- Calculate positions for screen elements
-- TODO: Actually calculate
local linesY = 3
local linesH = gpuH - 3 -- TODO: Help area
local statusbarY = gpuH

local utf8char = "[%z\1-\127\194-\244][\128-\191]*"
local function formatLine(text,map)
	local newstr, pos = {}, 0
	local cmap
	if map then
		cmap = {}
	end
	for char in text:gmatch(utf8char) do
		if map then
			cmap[#cmap+1] = pos+1
		end
		if char == "\t" then
			local amt = options.tabsize - pos%options.tabsize
			for i = 1,amt do
				newstr[#newstr+1] = " "
			end
			pos = pos + amt
		else
			newstr[#newstr+1] = char
			pos = pos + unicode.charWidth(char)
		end
	end
	if map then
		cmap[#cmap+1] = pos+1
	end
	return table.concat(newstr), cmap
end

local function setTitleBar(buffer)
	local title = " New Buffer "
	if buffer.filename ~= nil then
		title = " File: " .. buffer.filename:match(".*/(.+)") .. " "
	end
	gpu.setForeground(options.bgcolor)
	gpu.setBackground(options.fgcolor)
	gpu.fill(1,1,gpuW,1," ")
	local startX = (gpuW - unicode.wlen(title))/2
	gpu.set(3,1,"Lua nano " .. nanoVERSION)
	if buffer.modified then
		local str = "Modified"
		gpu.set(gpuW-unicode.wlen(str)-2,1,str)
	end
	gpu.set(startX,1,title)
	gpu.setForeground(options.fgcolor)
	gpu.setBackground(options.bgcolor)
end

local function setModified(buffer,mod)
	if mod == nil then mod = true end
	if buffer.modified ~= mod then
		buffer.modified = mod
		setTitleBar(buffer)
	end
end

local function setStatusBar(text)
	text = "[ " .. text .. " ]"
	gpu.fill(1,statusbarY,gpuW,1," ")
	gpu.setForeground(options.bgcolor)
	gpu.setBackground(options.fgcolor)
	local startX = (gpuW - unicode.wlen(text))/2
	gpu.set(startX,statusbarY,text)
	gpu.setForeground(options.fgcolor)
	gpu.setBackground(options.bgcolor)
end

local function createNewBuffer()
	return {
		filename=nil,
		modified=false,
		lines = {
		},
		x = 1,
		y = 1,
		startLine = 1,
	}
end

local function createBuffer(filename)
	local buffer = createNewBuffer()
	if fs.exists(filename) then
		local file, err = io.open(filename,"rb")
		if file then
			buffer.filename = filename
			for line in file:lines() do
				buffer.lines[#buffer.lines+1] = line
			end
			file:close()
			setStatusBar("Read " .. #buffer.lines .. " line" .. (#buffer.lines ~= 1 and "s" or ""))
		else
			setStatusBar("Couldn't open " .. filename .. ": " .. err)
		end
	else
		buffer.filename = filename
	end
	if #buffer.lines == 0 then
		buffer.lines[1] = ""
	end
	buffers[#buffers+1] = buffer
end

local function drawLine(line,y)
	local fline = formatLine(line)
	if unicode.wlen(fline) < gpuW then
		fline = fline .. string.rep(" ",gpuW - unicode.wlen(fline))
	elseif unicode.wlen(fline) > gpuW then
		fline = unicode.wtrunc(fline,gpuW)
		fline = fline .. string.rep(" ",gpuW - unicode.wlen(fline) - 1) .. "$"
	end
	gpu.set(1,y,fline)
end

local function updateActiveLine()
	local buffer = buffers[buffers.cur]
	local line = buffer.lines[buffer.y]
	local fline,map = formatLine(line,true)
	-- TODO: Redraw with respect to the cursor
	term.setCursorBlink(false)
	drawLine(line,buffer.y-buffer.startLine+linesY)
	term.setCursor(map[math.min(buffer.x,unicode.len(line)+1)],buffer.y-buffer.startLine+linesY)
	for i=1,2 do term.setCursorBlink(true)end
end

local function scrollBuffer()
	local buffer, amt = buffers[buffers.cur]
	local startLine = buffer.startLine
	if buffer.y-startLine < 0 then
		amt = buffer.y-startLine
	elseif buffer.y-startLine > (linesH-1) then
		amt = buffer.y-startLine-(linesH-1)
	end
	if not amt then return end
	term.setCursorBlink(false)
	startLine = startLine + amt
	buffer.startLine = startLine
	if amt > 0 then
		gpu.copy(1,linesY+amt,gpuW,linesH-amt,0,-amt)
		for i = startLine+linesH-1-amt, math.min(startLine+linesH-1,#buffer.lines) do
			drawLine(buffer.lines[i],i-startLine+linesY)
		end
	else
		gpu.copy(1,linesY,gpuW,linesH+amt,0,-amt)
		for i = startLine, math.min(startLine-amt-1,#buffer.lines) do
			drawLine(buffer.lines[i],i-startLine+linesY)
		end
	end
	term.setCursorBlink(true)
end

local function switchBuffers(index)
	buffers.cur = index
	local buffer = buffers[index]
	setTitleBar(buffer)
	gpu.fill(1,linesY,gpuW,linesH," ")
	local startLine, amt = buffer.startLine
	if buffer.y-startLine < 0 then
		amt = buffer.y-startLine
	elseif buffer.y-startLine > (linesH-1) then
		amt = buffer.y-startLine-(linesH-1)
	end
	if amt then
		startLine = startLine + amt
		buffer.startLine = startLine
	end
	for i = startLine, math.min(startLine+linesH-1,#buffer.lines) do
		drawLine(buffer.lines[i],i-startLine+linesY)
	end
	updateActiveLine()
end

-- TODO: Line and column arguments
-- Load files
if #args > 0 then
	for i = 1,#args do
		createBuffer(shell.resolve(args[i]))
	end
	if #buffers > 1 then
		setStatusBar("Read " .. #buffers[1].lines .. " line" .. (#buffers[1].lines ~= 1 and "s" or ""))
	end
else
	local buffer = createNewBuffer()
	buffer.lines[1] = ""
	buffers[#buffers+1] = buffer
end

-- Show the first file
switchBuffers(1)

local running = true
while running do
	local buffer = buffers[buffers.cur]
	local e = { event.pull() }
	if e[1] == "key_down" then
		local char, code = e[3], e[4]
		local clul = unicode.len(buffer.lines[buffer.y])
        if kbd.isAltDown() or kbd.isControlDown() then
		elseif char == 0 or (kbd.isControl(char) and char ~= 9) then
			if code == keys.f1 then
				running = false
			elseif code == keys.left then
				if buffer.x > 1 or buffer.y > 1 then
					buffer.x = buffer.x - 1
					if buffer.x < 1 then
						buffer.y = buffer.y - 1
						buffer.x = unicode.len(buffer.lines[buffer.y])+1
						scrollBuffer()
					end
					updateActiveLine()
				end
			elseif code == keys.right then
				if buffer.x < clul+1 or buffer.y < #buffer.lines then
					buffer.x = buffer.x + 1
					if buffer.x > clul+1 then
						buffer.y = buffer.y + 1
						buffer.x = 1
						scrollBuffer()
					end
					updateActiveLine()
				end
			elseif code == keys.up then
				-- TODO: Match up cursor X positions
				if buffer.y > 1 then
					buffer.y = buffer.y - 1
					scrollBuffer()
					updateActiveLine()
				end
			elseif code == keys.down then
				-- TODO: Match up cursor X positions
				if buffer.y < #buffer.lines then
					buffer.y = buffer.y + 1
					scrollBuffer()
					updateActiveLine()
				end
			elseif code == keys.home then
				if buffer.x > 1 then
					buffer.x = 1
					updateActiveLine()
				end
			elseif code == keys["end"] then
				if buffer.x < clul+1 then
					buffer.x = clul+1
					updateActiveLine()
				end
			elseif code == keys.back then
				if buffer.x == 1 then
					if buffer.y > 1 then
						setModified(buffer)
						buffer.x = unicode.len(buffer.lines[buffer.y-1])+1
						buffer.lines[buffer.y-1] = buffer.lines[buffer.y-1] .. buffer.lines[buffer.y]
						table.remove(buffer.lines,buffer.y)
						buffer.y = buffer.y - 1
						-- TODO: Don't redraw everything
						switchBuffers(buffers.cur)
					end
				else
					setModified(buffer)
					local line = buffer.lines[buffer.y]
					buffer.lines[buffer.y] = unicode.sub(line,1,buffer.x-2) .. unicode.sub(line,buffer.x)
					buffer.x = buffer.x - 1
					updateActiveLine()
				end
			elseif code == keys.delete then
				if buffer.x >= clul+1 then
					setModified(buffer)
					if buffer.y < #buffer.lines then
						buffer.lines[buffer.y] = buffer.lines[buffer.y] .. buffer.lines[buffer.y+1]
						table.remove(buffer.lines,buffer.y+1)
						-- TODO: Don't redraw everything
						switchBuffers(buffers.cur)
					end
				else
					setModified(buffer)
					local line = buffer.lines[buffer.y]
					buffer.lines[buffer.y] = unicode.sub(line,1,buffer.x-1) .. unicode.sub(line,buffer.x+1)
					updateActiveLine()
				end
			elseif code == keys.enter then
				setModified(buffer)
				local line = buffer.lines[buffer.y]
				table.insert(buffer.lines,buffer.y+1,unicode.sub(line,buffer.x))
				buffer.lines[buffer.y] = unicode.sub(line,1,buffer.x-1)
				buffer.x = 1
				buffer.y = buffer.y + 1
				-- TODO: Don't redraw everything
				switchBuffers(buffers.cur)
			end
		else
			setModified(buffer)
			local line = buffer.lines[buffer.y]
			buffer.lines[buffer.y] = unicode.sub(line,1,buffer.x-1) .. unicode.char(char) .. unicode.sub(line,buffer.x)
			buffer.x = buffer.x + 1
			updateActiveLine()
		end
	end
end

term.clear()
term.setCursorBlink(false)
