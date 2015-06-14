--[[
nano clone based off GNU nano for OpenComputers
by Gamax92
--]]
local component = require("component")
local computer = require("computer")
local kbd = require("keyboard")
local keys = kbd.keys
local fs = require("filesystem")
local shell = require("shell")
local event = require("event")
local term = require("term")
local unicode = require("unicode")

local nanoVERSION = "1.0.0"

local function printf(...) print(string.format(...)) end
local function eprintf(...) io.stderr:write(string.format(...) .. "\n") end

-- TODO: Replace with more gnuopt style parser
local args, opts = shell.parse(...)

-- TODO: Once above has been done, check for invalid arguments
-- Default options
local options = {
	fgcolor = 0xFFFFFF,
	bgcolor = 0x000000,
	tabsize = 8,
}
local flags={"autoindent","backup","backwards","brighttext","casesensitive","const","cut","morespace","mouse","multibuffer","noconvert","nohelp","nonewlines","nowrap","quiet","quickblank","patterns","smarthome","smooth","softwrap","tabstospaces","tempfile","undo","view"}
for i = 1,#flags do
	options[flags[i]] = false
end
flags = nil
-- Default bindings
-- TODO: Bindings for things other than main
local bind = {
	main = {
		{"help","^G","F1"},
		{"exit","^X","F2"},
		{"writeout","^O","F3"},
		{"insert","^R","F5","insert"},
		{"whereis","^W","F6"},
		{"replace","^\\","M-R","F14"},
		{"cut","^K","F9"},
		{"uncut","^U","F10"},
		{"justify","^J","F4"},
		{"speller","^T","F12"},
		{"curpos","^C","F11"},
		{"gotoline","^_","M-G","F13"},
		{"prevpage","^Y","F7","pageUp"},
		{"nextpage","^V","F8","pageDown"},
		{"firstline","M-\\","M-|"},
		{"lastline","M-/","M-?"},
		{"searchagain","M-W","F16"},
		{"findbracket","M-]"},
		{"mark","^^","M-A","F15"},
		{"copytext","M-^","M-6"},
		{"indent","M-}"},
		{"unindent","M-{"},
		{"undo","M-U"},
		{"redo","M-E"},
		{"left","^B","left"},
		{"right","^F","right"},
		{"prevword","M-Space"},
		{"nextword","^Space"},
		{"home","^A","home"},
		{"end","^E","end"},
		{"prevline","^P","up"},
		{"nextline","^N","down"},
		{"beginpara","M-(","M-9"},
		{"endpara","M-)","M-0"},
		{"scrollup","M--","M-_"},
		{"scrolldown","M-+","M-="},
		{"prevbuf","M-<","M-,"},
		{"nextbuf","M->","M-."},
		{"verbatim","M-V"},
		{"tab","^I"},
		{"enter","^M","enter"},
		{"delete","^D","delete"},
		{"backspace","^H","back"},
		{"cutrestoffile","M-T"},
		{"fulljustify","M-J"},
		{"wordcount","M-D"},
		{"refresh","^L"},
		{"suspend","^Z"},
		{"nohelp","M-X"},
		{"constupdate","M-C"},
		{"morespace","M-O"},
		{"smoothscroll","M-S"},
		{"softwrap","M-$"},
		{"whitespacedisplay","M-P"},
		{"nosyntax","M-Y"},
		{"smarthome","M-H"},
		{"autoindent","M-I"},
		{"cuttoend","M-K"},
		{"nowrap","M-L"},
		{"tabstospaces","M-Q"},
		{"backupfile","M-B"},
		{"multibuffer","M-F"},
		{"mouse","M-M"},
		{"noconvert","M-N"},
		{"suspendenable","M-Z"},
	}
}
for k,v in pairs(bind) do
	for i = 1,#v do
		local b = v[i]
		for j = 2,#b do
			v[unicode.upper(b[j])]=b[1]
		end
		v[i] = nil
	end
end

local eb = "Error in %s on line %d: "
local function parseRC(filename)
	local problem = false
	local file, err = io.open(filename,"rb")
	if not file then
		problem = true; printf("Error reading %s: %s", filename, err)
	else
		local i = 1
		for line in file:lines() do
			local cmd = {}
			for part in line:gmatch("%S+") do
				cmd[#cmd+1] = part
			end
			if cmd[1] == "set" or cmd[1] == "unset" then
				if #cmd < 2 then
					problem = true; printf(eb .. "Missing flag", filename, i)
				elseif options[cmd[2]] ~= nil then
					if type(options[cmd[2]]) == "boolean" then
						options[cmd[2]] = cmd[1] == "set"
					elseif type(options[cmd[2]]) == "number" then
						if tonumber(cmd[3]) == nil then
							problem = true; printf(eb.."Parameter \"%s\" is invalid", filename, i, cmd[3])
						else
							options[cmd[2]] = tonumber(cmd[3])
						end
					end
				else
					problem = true; printf(eb.."Unknown flag \"%s\"", filename, i, cmd[2])
				end
			elseif cmd[1] == "bind" or cmd[1] == "unbind" then
				-- TODO: These commands
			else
				problem = true; printf(eb.."Command \"%s\" not understood", filename, i, cmd[1])
			end
			i = i + 1
		end
	end
	if problem then
		print("Press Enter to continue starting nano.")
		while true do
			local name,_,_,code = event.pull()
			if name == "key_down" and code == keys.enter then break end
		end
	end
end
if fs.exists("/etc/nanorc") then
	parseRC("/etc/nanorc")
end
-- TODO: Parse arguments

local buffers, buffer = {}
local gpu = component.gpu
gpu.setForeground(options.fgcolor)
gpu.setBackground(options.bgcolor)
local gpuW, gpuH = gpu.getResolution()
gpu.fill(1,1,gpuW,gpuH," ")
term.setCursorBlink(true)

-- TODO: more modes
local mode = "main"
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
		tx = 1,
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
	local line = buffer.lines[buffer.y]
	local fline,map = formatLine(line,true)
	-- TODO: Redraw with respect to the cursor
	term.setCursorBlink(false)
	drawLine(line,buffer.y-buffer.startLine+linesY)
	term.setCursor(map[math.min(buffer.x,#map)],buffer.y-buffer.startLine+linesY)
	for i=1,2 do term.setCursorBlink(true)end
end

local function updateTX()
	local _,map = formatLine(buffer.lines[buffer.y],true)
	buffer.tx = map[math.min(buffer.x,#map)]
end

local function scrollBuffer()
	local amt
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

local function redraw()
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

local function switchBuffers(index)
	buffer = buffers[index]
	if buffers.cur ~= nil then
		local name = "New Buffer"
		if buffer.filename ~= nil then
			name = buffer.filename:match(".*/(.+)")
		end
		setStatusBar("Switched to " .. name)
	end
	buffers.cur = index
	redraw()
end

local function statusPrompt(text)
	gpu.fill(1,statusbarY,gpuW,1," ")
	gpu.set(1,statusbarY,text)
	term.setCursor(unicode.wlen(text)+1,statusbarY)
end

local function resetColor()
	gpu.setForeground(options.fgcolor)
	gpu.setBackground(options.bgcolor)
end

local running = true
local function clul() return unicode.len(buffer.lines[buffer.y]) end
local binding = {}
function binding.exit()
	-- TODO: Get a MYESNO mode
	if buffer.modified then
		gpu.setForeground(options.bgcolor)
		gpu.setBackground(options.fgcolor)
		statusPrompt("Save modified buffer (ANSWERING \"No\" WILL DESTROY CHANGES) ? ")
		while true do
			local e,_,c = event.pull()
			if e == "key_down" then
				c = unicode.lower(unicode.char(c))
				local ctrl = kbd.isControlDown()
				if not ctrl and c == "y" then
					-- TODO: Get a MWRITEFILE mode
					-- TODO: Needs more options
					local oldname = ""
					if buffer.filename ~= nil then
						oldname = buffer.filename:match(".*/(.+)")
					end
					local filename = oldname
					::tryagain::
					statusPrompt("File Name to Write: ")
					-- TODO: HACK HACK HACK
					computer.pushSignal("key_down",computer.address(),0,keys.up)
					filename = term.read({filename},false)
					if filename then
						filename = filename:gsub("[\r\n]","")
					end
					if filename == "" or filename == nil then
						resetColor()
						setStatusBar("Cancelled")
						return
					end
					if filename ~= oldname and fs.exists(shell.resolve(filename)) then
						-- TODO: Again, MYESNO mode
						statusPrompt("File exists, OVERWRITE ? ")
						while true do
							local e,_,c = event.pull()
							c = unicode.lower(unicode.char(c))
							if e == "key_down" then
								local ctrl = kbd.isControlDown()
								if not ctrl and c == "y" then
									break
								elseif (not ctrl and c == "n") or (ctrl and c == "\3") then
									goto tryagain
								end
							end
						end
					end
					local file, err = io.open(shell.resolve(filename),"wb")
					if not file then
						resetColor()
						setStatusBar("Error writing " .. filename .. ": " .. err)
						return
					end
					for i = 1,#buffer.lines do
						file:write(buffer.lines[i] .. "\n")
					end
					file:close()
					break
				elseif not ctrl and c == "n" then
					break
				elseif ctrl and c == "\3" then
					resetColor()
					setStatusBar("Cancelled")
					return
				end
			end
		end
	end
	gpu.setForeground(options.fgcolor)
	gpu.setBackground(options.bgcolor)
	table.remove(buffers,buffers.cur)
	buffers.cur = math.min(buffers.cur,#buffers)
	if buffers.cur < 1 then
		running = false
	else
		switchBuffers(buffers.cur)
	end
end
function binding.left()
	if buffer.x > 1 or buffer.y > 1 then
		buffer.x = buffer.x - 1
		if buffer.x < 1 then
			buffer.y = buffer.y - 1
			buffer.x = unicode.len(buffer.lines[buffer.y])+1
			scrollBuffer()
		end
		updateTX()
		updateActiveLine()
	end
end
function binding.right()
	if buffer.x < clul()+1 or buffer.y < #buffer.lines then
		buffer.x = buffer.x + 1
		if buffer.x > clul()+1 then
			buffer.y = buffer.y + 1
			buffer.x = 1
			scrollBuffer()
		end
		updateTX()
		updateActiveLine()
	end
end
function binding.prevline()
	if buffer.y > 1 then
		buffer.y = buffer.y - 1
		local _,map = formatLine(buffer.lines[buffer.y],true)
		for i = 1,#map do
			if map[i] > buffer.tx then break end
			buffer.x = i
		end
		scrollBuffer()
		updateActiveLine()
	end
end
function binding.nextline()
	if buffer.y < #buffer.lines then
		buffer.y = buffer.y + 1
		local _,map = formatLine(buffer.lines[buffer.y],true)
		for i = 1,#map do
			if map[i] > buffer.tx then break end
			buffer.x = i
		end
		scrollBuffer()
		updateActiveLine()
	end
end
function binding.home()
	if buffer.x > 1 then
		buffer.x = 1
		updateTX()
		updateActiveLine()
	end
end
binding["end"] = function()
	if buffer.x < clul()+1 then
		buffer.x = clul()+1
		updateTX()
		updateActiveLine()
	end
end
function binding.backspace()
	if buffer.x == 1 then
		if buffer.y > 1 then
			setModified(buffer)
			buffer.x = unicode.len(buffer.lines[buffer.y-1])+1
			buffer.lines[buffer.y-1] = buffer.lines[buffer.y-1] .. buffer.lines[buffer.y]
			table.remove(buffer.lines,buffer.y)
			buffer.y = buffer.y - 1
			-- TODO: Don't redraw everything
			redraw()
		end
	else
		setModified(buffer)
		local line = buffer.lines[buffer.y]
		buffer.lines[buffer.y] = unicode.sub(line,1,buffer.x-2) .. unicode.sub(line,buffer.x)
		buffer.x = buffer.x - 1
		updateActiveLine()
	end
	updateTX()
end
function binding.delete()
	if buffer.x >= clul()+1 then
		setModified(buffer)
		if buffer.y < #buffer.lines then
			buffer.lines[buffer.y] = buffer.lines[buffer.y] .. buffer.lines[buffer.y+1]
			table.remove(buffer.lines,buffer.y+1)
			-- TODO: Don't redraw everything
			redraw()
		end
	else
		setModified(buffer)
		local line = buffer.lines[buffer.y]
		buffer.lines[buffer.y] = unicode.sub(line,1,buffer.x-1) .. unicode.sub(line,buffer.x+1)
		updateActiveLine()
	end
end
function binding.enter()
	setModified(buffer)
	local line = buffer.lines[buffer.y]
	table.insert(buffer.lines,buffer.y+1,unicode.sub(line,buffer.x))
	buffer.lines[buffer.y] = unicode.sub(line,1,buffer.x-1)
	buffer.x = 1
	buffer.tx = 1
	buffer.y = buffer.y + 1
	-- TODO: Don't redraw everything
	redraw()
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

while running do
	local e = { event.pull() }
	if e[1] == "key_down" then
		local char, code = e[3], e[4]
		local ctrl = kbd.isControlDown()
		local alt = kbd.isAltDown()
		local scp,sc = keys[code]:sub(1,1), keys[code]:sub(2)
		local schar
		if not kbd.isControl(char) and char ~= 32 then
			schar = unicode.upper(unicode.char(char))
		else
			schar = unicode.upper(keys[code])
		end
		if ctrl then
			-- TODO: This doesn't cover everything
			if unicode.len(keys[code]) == 1 then
				schar = unicode.upper(keys[code])
			end
		end
		if ctrl then
			schar = "^" .. schar
		elseif alt then
			schar = "M-" .. schar
		end
		if (scp == "l" or scp == "r") and (sc == "control" or sc == "menu" or sc == "shift") then
		elseif bind[mode][schar] ~= nil then
			local cmd = bind[mode][schar]
			if binding[cmd] ~= nil then
				binding[cmd]()
			else
				setStatusBar("Binding \"" .. cmd .. "\" Unimplemented")
			end
		elseif ctrl or alt then
			setStatusBar("Unknown Command")
		else
			setModified(buffer)
			local line = buffer.lines[buffer.y]
			buffer.lines[buffer.y] = unicode.sub(line,1,buffer.x-1) .. unicode.char(char) .. unicode.sub(line,buffer.x)
			buffer.x = buffer.x + 1
			updateTX()
			updateActiveLine()
		end
	end
end

term.clear()
term.setCursorBlink(false)
