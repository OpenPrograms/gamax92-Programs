--[[
WocChat - the Wonderful OpenComputers Chat client
Written by gamax92
Some code borrowed from OpenIRC
--]]
local function errprint(msg)io.stderr:write(msg.."\n")end
local component = require("component")
local gpu = component.gpu

if gpu.maxDepth() < 4 then
	errprint("WocChat requires atleast a T2 GPU and Screen!")
	return
elseif not component.isAvailable("internet") then
	errprint("WocChat requires an Internet Card to run!")
	return
end

local computer = require("computer")
local event = require("event")
local internet = require("internet")
local shell = require("shell")
local text = require("text")
local unicode = require("unicode")

local args, options = shell.parse(...)

local config,blocks = {},{active=1,{type="main",name="WocChat",text={}}}
local screen,theme,lastbg,lastfg

function setBackground(bg)
	if bg ~= lastbg then
		gpu.setBackground(bg,true)
		lastbg = bg
	end
end

function setForeground(fg)
	if fg ~= lastfg then
		gpu.setForeground(fg,true)
		lastfg = fg
	end
end

function saveScreen()
	local width,height = gpu.getResolution()
	screen = {palette={},cfg={},cbg={},width=width,height=height}
	for i = 0,15 do
		screen.palette[i] = gpu.getPaletteColor(i)
	end
	screen.bg = {gpu.getBackground()}
	screen.fg = {gpu.getForeground()}
	for y = 1,height do
		screen[y] = {}
		for x = 1,width do
			screen[y][x] = { gpu.get(x,y) }
			screen.cfg[screen[y][x][2] .. "_" .. tostring(screen[y][x][4])] = true
			screen.cbg[screen[y][x][3] .. "_" .. tostring(screen[y][x][5])] = true
		end
	end
end

function restoreScreen()
	for i = 0,15 do
		gpu.setPaletteColor(i,screen.palette[i])
	end
	for bgs in pairs(screen.cbg) do
		local bg,bp = bgs:match("(.-)_(.+)")
		bg,bp=tonumber(bg),tonumber(bp)
		if bp ~= nil then
			gpu.setBackground(bp,true)
		else
			gpu.setBackground(bg)
		end
		for fgs in pairs(screen.cfg) do
			local fg,fp = fgs:match("(.-)_(.+)")
			fg,fp=tonumber(fg),tonumber(fp)
			if fp ~= nil then
				gpu.setForeground(fp,true)
			else
				gpu.setForeground(fg)
			end
			for y = 1,screen.height do
				local str = ""
				for x = 1,screen.width do
					if screen[y][x][2] == fg and screen[y][x][3] == bg then
						str = str .. screen[y][x][1]
					elseif #str > 0 then
						gpu.set(x-unicode.len(str),y,str)
						str = ""
					end
				end
				if #str > 0 then
					gpu.set(screen.width-unicode.len(str)+1,y,str)
				end
			end
		end
	end
	gpu.setBackground(table.unpack(screen.bg))
	gpu.setForeground(table.unpack(screen.fg))
end

function loadConfig()
	local section
	config = {}
	for line in io.lines("/etc/wocchat.cfg") do
		if line:sub(1,1) == "[" then
			section = line:sub(2,-2)
			config[section] = {}
		elseif line ~= "" then
			local key,value = line:match("(.-)=(.*)")
			key = section .. "\0" .. key:gsub("%.","\0")
			path,name=key:match("(.+)%z(.+)")
			local v = config
			for part in (path .. "\0"):gmatch("(.-)%z") do
				if tonumber(part) ~= nil then part = tonumber(part) end
				if v[part] == nil then
					v[part] = {}
				end
				v = v[part]
			end
			if tonumber(name) ~= nil then name = tonumber(name) end
			if value == "true" then
				v[name]=true
			elseif value == "false" then
				v[name]=false
			elseif value:sub(1,1) == "\"" then
				v[name]=value:sub(2,-2)
			else
				v[name]=tonumber(value)
			end
		end
	end
	theme=config[config.theme.theme .. ".theme"]
end

function drawTree(width)
	setBackground(theme.tree.color)
	gpu.fill(1,1,width,screen.height," ")
	local y = 1
	for i = 1,#blocks do
		local block = blocks[i]
		if block.type == "main" then
			setForeground(theme.tree.group.color)
			gpu.set(2,y,"WocChat")
		elseif block.type == "server" then
			setForeground(theme.tree.group.color)
			gpu.set(2,y,block.name)
			setForeground(theme.tree.group.prefix.color)
			gpu.set(1,y,theme.tree.group.prefix.str)
		elseif block.type == "channel" then
			setForeground(theme.tree.entry.color)
			gpu.set(2,y,block.name)
			setForeground(theme.tree.entry.prefix.color)
			local siblings = blocks[block.parent].children
			if i == siblings[#siblings] then
				gpu.set(1,y,theme.tree.entry.prefix.last)
			else
				gpu.set(1,y,theme.tree.entry.prefix.str)
			end
		end
		y=y+1
	end
end

function drawTabs()
end

function drawList(width,names)
	setBackground(theme.tree.color)
	local x = screen.width-width+1
	gpu.fill(x,1,width,screen.height," ")
	setForeground(theme.tree.group.color)
	for y = 1,#names do
		gpu.set(x,y,names[y])
	end
end

function drawWindow(x,width,height,text)
	setBackground(theme.window.color)
	gpu.fill(x,2,width,height," ")
	-- This needs text wrapping, just for demostration
	local nickwidth = 0
	for i = 1,#text do
		nickwidth=math.max(nickwidth,#text[i][1])
	end
	for i = 1,#text do
		setForeground(theme.window.nick.color)
		gpu.set(x,i+1,text[i][1])
		setForeground(theme.window.divider.color)
		gpu.set(x+nickwidth,i+1,"|")
		setForeground(theme.window.text.color)
		gpu.set(x+nickwidth+1,i+1,text[i][2])
	end
end

function drawText(x,y,width,text)
	setBackground(theme.textbar.color)
	gpu.fill(x,y,width,1," ")
	setForeground(theme.textbar.text.color)
	gpu.set(x,y,text)
end

function redraw()
	if config.wocchat.usetree then
		local treewidth = 8
		for i = 1,#blocks do
			local block = blocks[i]
			if block.type == "server" then
				treewidth=math.max(treewidth,unicode.len(theme.tree.group.prefix.str .. block.name))
			elseif block.type == "channel" then
				treewidth=math.max(treewidth,unicode.len(theme.tree.entry.prefix.str .. block.name))
			end
		end
		drawTree(treewidth)
		setBackground(theme.window.color)
		setForeground(theme.tree.color)
		gpu.fill(treewidth+1,2,1,screen.height-2,"▌")
		setBackground(theme.textbar.color)
		gpu.set(treewidth+1,screen.height,"▌")
		gpu.set(treewidth+1,1,"▌")
		local listwidth = -1
		if blocks[blocks.active].names ~= nil then
			local names = blocks[blocks.active].names
			for i = 1,#names do
				listwidth=math.max(listwidth,unicode.len(names[i]))
			end
			drawList(listwidth,names)
			setBackground(theme.tree.color)
			setForeground(theme.window.color)
			gpu.fill(screen.width-listwidth,2,1,screen.height-2,"▌")
			setForeground(theme.textbar.color)
			gpu.set(screen.width-listwidth,screen.height,"▌")
			gpu.set(screen.width-listwidth,1,"▌")
			drawText(treewidth+2,1,screen.width-treewidth-listwidth-2,blocks[blocks.active].title)
		else
			drawText(treewidth+2,1,screen.width-treewidth-listwidth-2,blocks[blocks.active].name .. " Main Window")
		end
		drawText(treewidth+2,screen.height,screen.width-treewidth-listwidth-2,blocks.text)
		drawWindow(treewidth+2,screen.width-treewidth-listwidth-2,screen.height-2,blocks[blocks.active].text)
	else
	end
end

function main()
	print("Loading config ...")
	loadConfig()
	print("Saving screen ...")
	saveScreen()
	gpu.fill(1,1,screen.width,screen.height," ")
	local i=0
	while theme[i] ~= nil do
		gpu.setPaletteColor(i,theme[i])
		i=i+1
	end
	blocks = {
		{type="main",name="WocChat",text={}},
		{type="server",name="EsperNet",text={},children={3,4}},
		{type="channel",name="#oc",title="OpenComputers! Home of the garbage scala code",text={{"Temia","moo?"},{"gamax92","yay"},{"*","rashy waves at Temia"}},names={"Nobody","Important"},parent=2},
		{type="channel",name="#oc_again",title="Extra Channel for testing",text={},names={"Useless","People"},parent=2},
		active=3,
		nick="gamax92",
		text="/me wonders what I'm even doing ..."
	}
	redraw()
	os.sleep(10)
end

local stat, err = xpcall(main,debug.traceback)
if screen then
	restoreScreen()
end
if not stat then
	errprint(err)
end
