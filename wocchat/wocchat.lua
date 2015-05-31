--[[
WocChat - the Wonderful OpenComputers Chat client
Written by gamax92
Some code borrowed from OpenIRC
Some code borrowed from wget
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

local version = "v0.0.1"

local bit32 = require("bit32")
local computer = require("computer")
local event = require("event")
local fs = require("filesystem")
local internet = require("internet")
local shell = require("shell")
local term = require("term")
local text = require("text")
local unicode = require("unicode")

local args, options = shell.parse(...)

local config,blocks,persist = {},{{type="main",name="WocChat",text={{"*","Welcome to WocChat!"}}},active=1},{}
local screen,theme,lastbg,lastbgp,lastfg,lastfgp

local function setBackground(bg, pal)
	if bg ~= lastbg or pal ~= lastbgp then
		gpu.setBackground(bg,not pal)
		lastbg = bg
		lastbgp = pal
	end
end

local function setForeground(fg, pal)
	if fg ~= lastfg or pal ~= lastfgp then
		gpu.setForeground(fg,not pal)
		lastfg = fg
		lastfgp = pal
	end
end

local function saveScreen()
	local width,height = gpu.getResolution()
	screen = {palette={},width=width,height=height}
	for i = 0,15 do
		screen.palette[i] = gpu.getPaletteColor(i)
	end
	screen.bg = {gpu.getBackground()}
	screen.fg = {gpu.getForeground()}
end

local function restoreScreen()
	term.setCursor(1,screen.height)
	gpu.setBackground(table.unpack(screen.bg))
	gpu.setForeground(table.unpack(screen.fg))
	print("Restoring screen ...")
	for i = 0,15 do
		gpu.setPaletteColor(i,screen.palette[i])
	end
end

local function loadConfig()
	local section
	config = {}
	for line in io.lines("/etc/wocchat.cfg") do
		if line:sub(1,1) == "[" then
			section = line:sub(2,-2)
			config[section] = {}
		elseif line ~= "" then
			local key,value = line:match("(.-)=(.*)")
			key,value = text.trim(key),text.trim(value)
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
	theme=setmetatable({},{__index=function(_,k)
		local theme = config.theme.theme .. ".theme"
		if config[theme][k] then
			return config[theme][k]
		elseif config[theme].parent ~= nil then
			return config[config[theme].parent .. ".theme"][k]
		end
	end})
end

local function configSort(a,b)
	local ta,tb = type(a),type(b)
	if ta == tb then
		return a < b
	end
	return ta == "number"
end
local saveSection
function saveSection(file,tbl,name)
	name = name or ""
	local keys = {}
	for k,v in pairs(tbl) do
		keys[#keys+1] = k
	end
	table.sort(keys,configSort)
	for i = 1,#keys do
		local k,v = keys[i],tbl[keys[i]]
		local ndk = (name == "" and k or name .. "." .. k)
		if type(v) == "table" then
			saveSection(file,v,ndk)
		elseif type(k) == "number" and type(v) == "number" then
			file:write(ndk .. "=" .. string.format("0x%06X\n",v))
		elseif type(v) == "string" then
			file:write(ndk .. "=\"" .. v .. "\"\n")
		else
			file:write(ndk .. "=" .. tostring(v) .. "\n")
		end
	end
end
local sections = {wocchat=1,default=2,server=3,theme=4}
local function sectionSort(a,b)
	if sections[a] and sections[b] then
		return sections[a] < sections[b]
	elseif not sections[a] and not sections[b] then
		return a < b
	end
	return sections[a] ~= nil
end
local function saveConfig()
	local file, err = io.open("/etc/wocchat.cfg","wb")
	if not file then
		return false, err
	end
	local keys = {}
	for k,v in pairs(config) do
		keys[#keys+1] = k
	end
	table.sort(keys,sectionSort)
	for i = 1,#keys do
		file:write("[" .. keys[i] .. "]\n")
		saveSection(file, config[keys[i]])
		file:write("\n")
	end
	file:close()
	return true
end

local function simpleHash(str)
	local v = 0
	for char in str:gmatch(".") do
		v = bit32.bxor(bit32.lrotate(v,5),char:byte())
	end
	return v
end

local dirty = {
	blocks = true,
	window = true,
	nicks = true,
	title = true,
}

local default_support = {
	PREFIX="(ov)@+",
	CHANTYPES="#&",
}

local function drawTree(width)
	setBackground(theme.tree.color)
	gpu.fill(1,1,width,screen.height," ")
	local y = 1
	for i = 1,#blocks do
		local block = blocks[i]
		if blocks.active == i then
			setBackground(theme.tree.active.color)
			gpu.fill(1,i,width,1," ")
		end
		setForeground(block.new and theme.tree.new.color or block.type:sub(1,5) == "dead_" and theme.tree.dead.color or block.type == "channel" and theme.tree.entry.color or theme.tree.group.color)
		if block.type == "main" then
			gpu.set(unicode.wlen(theme.tree.group.prefix.str)+1,y,block.name)
		elseif block.type == "server" or block.type == "dead_server" then
			gpu.set(unicode.wlen(theme.tree.group.prefix.str)+1,y,block.support.NETWORK or block.name)
			setForeground(theme.tree.group.prefix.color)
			gpu.set(1,y,theme.tree.group.prefix.str)
		elseif block.type == "channel" or block.type == "dead_channel" then
			gpu.set(unicode.wlen(theme.tree.entry.prefix.str)+1,y,block.name)
			setForeground(theme.tree.entry.prefix.color)
			local siblings = block.parent.children
			if block == siblings[#siblings] then
				gpu.set(1,y,theme.tree.entry.prefix.last)
			else
				gpu.set(1,y,theme.tree.entry.prefix.str)
			end
		end
		if blocks.active == i then
			setBackground(theme.tree.color)
		end
		y=y+1
	end
end

local function drawTabs()
	setBackground(theme.tree.color)
	setForeground(theme.window.color)
	gpu.fill(2,screen.height,screen.width-1,1," ")
	gpu.set(1,screen.height,"┃")
	local x = 1
	for i = 1,#blocks do
		local block = blocks[i]
		local name = block.name
		if block.type == "server" or block.type == "dead_server" then
			name = block.support.NETWORK or block.name
		end
		x=x+unicode.wlen(name)+1
		gpu.set(x,screen.height,"┃")
	end
	x = 2
	for i = 1,#blocks do
		local block = blocks[i]
		local name = block.name
		if block.type == "server" or block.type == "dead_server" then
			name = block.support.NETWORK or block.name
		end
		if blocks.active == i then
			setBackground(theme.tree.active.color)
		end
		setForeground(block.type:sub(1,5) == "dead_" and theme.tree.dead.color or theme.tree.group.color)
		gpu.set(x,screen.height,name)
		if blocks.active == i then
			setBackground(theme.tree.color)
		end
		x=x+unicode.wlen(name)+1
	end
end

local scroll_chars = {"█","▇","▆","▅","▄","▃","▂","▁"}

local function drawList(width,height)
	local block = blocks[blocks.active]
	local names = block.names
	setBackground(theme.window.color)
	gpu.fill(screen.width,1,1,height," ")
	setBackground(theme.tree.color)
	local x = screen.width-width+1
	gpu.fill(x,1,width-1,height," ")
	setForeground(theme.tree.group.color)
	local prefix = blocks[blocks.active].parent.support.PREFIX or default_support.PREFIX
	prefix = prefix:match("%)(.*)")
	block.scroll = math.max(math.min(block.scroll,#names-height+1),1)
	for y = block.scroll,math.min(#names,height+block.scroll-1) do
		if names[y]:find("^[" .. prefix .. "]") then
			gpu.set(x,y-block.scroll+1,names[y])
		else
			gpu.set(x+1,y-block.scroll+1,names[y])
		end
	end
	local pos = (block.scroll-1)/(#names-height)*(height-1)+1
	local ipos = math.floor((pos % 1)*8)+1
	setForeground(theme.tree.active.color)
	setBackground(theme.window.color)
	gpu.set(screen.width,pos,scroll_chars[ipos])
	setBackground(theme.tree.active.color)
	setForeground(theme.window.color)
	gpu.set(screen.width,pos+1,scroll_chars[ipos])
end

local function colorChunker(ostr,kill)
	local chunks = {}
	while ostr:find("[\3\15]") do
		local part,str
		part,str,ostr = ostr:match("(.-)([\3\15])(.*)")
		if part ~= "" then
			chunks[#chunks+1] = part
		end
		if str == "\3" then
			for char in ostr:gmatch(".") do
				if char:find("[^%d,]") or (str:find(",",nil,true) and char == ",") or #str >= 6 or (#str == 3 and not str:find(",",nil,true) and char ~= ",") or (#str == 1 and char == ",") then
					if not kill then
						chunks[#chunks+1] = str
					end
					ostr = ostr:sub(#str)
					break
				else
					str = str .. char
				end
			end
		else
			if not kill then
				chunks[#chunks+1] = str
			end
		end
	end
	chunks[#chunks+1] = ostr
	return chunks
end

local function basicWrap(line,width)
	local broken = ""
	local clean = table.concat(colorChunker(line,true),"")
	for part in text.wrappedLines(clean,width,width) do
		broken = broken .. part .. "\n"
	end
	local new = ""
	local bpos = 1
	for i = 1,#broken do
		if broken:sub(i,i) == "\n" then
			new = new .. "\n"
		elseif broken:sub(i,i) == line:sub(bpos,bpos) then
			new = new .. broken:sub(i,i)
			bpos=bpos+1
		else
			while broken:sub(i,i) ~= line:sub(bpos,bpos) do
				new = new .. line:sub(bpos,bpos)
				bpos=bpos+1
			end
			bpos=bpos+1
			new = new .. broken:sub(i,i)
		end
	end
	return new:gmatch("(.-)\n")
end

local function drawWindow(x,width,height,irctext)
	setBackground(theme.window.color)
	gpu.fill(x,2,width,height," ")
	local nickwidth = 0
	for i = 1,#irctext do
		nickwidth=math.max(nickwidth,#irctext[i][1])
	end
	local textwidth = width-nickwidth-1
	local buffer = {}
	for i = 1,#irctext do
		local first = true
		local line = irctext[i][2]:gsub("[\2\29\31]",""):gsub("\15+","\15")
		if not config.wocchat.showcolors or gpu.maxDepth() < 8 then
			line = table.concat(colorChunker(line,true),"")
		end
		for part in basicWrap(line,textwidth) do
			if first then
				buffer[#buffer+1] = {irctext[i][1],part,irctext[i][3],true}
				first = false
			else
				buffer[#buffer+1] = {"",part,irctext[i][3]}
			end
		end
		while #buffer > height do
			table.remove(buffer,1)
		end
	end
	setForeground(theme.window.divider.color)
	gpu.fill(x+nickwidth,2,1,height,theme.window.divider.str)
	local nickcolors
	if type(theme.window.nick.color) == "number" then
		nickcolors = theme.window.nick.color
	else
		nickcolors = {}
		for part in (theme.window.nick.color .. ","):gmatch("(.-),") do
			nickcolors[#nickcolors+1] = tonumber(part)
		end
	end
	for i = 1,#buffer do
		if buffer[i][1] ~= "" then
			setBackground(theme.window.color)
			if type(nickcolors) == "number" then
				setForeground(nickcolors)
			else
				setForeground(nickcolors[simpleHash(buffer[i][1])%#nickcolors+1])
			end
			gpu.set(x+nickwidth-unicode.wlen(buffer[i][1]),i+1,buffer[i][1])
		end
		if config.wocchat.showcolors and gpu.maxDepth() >= 8 then
			local chunk = colorChunker(buffer[i][2])
			local xpos = x+nickwidth+1
			if buffer[i][4] then
				setForeground(buffer[i][3] or theme.window.text.color)
				setBackground(theme.window.color)
			end
			for j = 1,#chunk do
				if chunk[j]:sub(1,1) == "\3" then
					local fg,bg
					if chunk[j]:find(",",nil,true) then
						fg,bg = chunk[j]:match("\3(.-),(.*)")
						fg,bg = tonumber(fg),tonumber(bg)
					else
						fg = tonumber(chunk[j]:sub(2))
					end
					if fg then setForeground(config.wocchat.mirc.colors[fg%16],true) end
					if bg then setBackground(config.wocchat.mirc.colors[bg%16],true) end
				elseif chunk[j] == "\15" then
					setForeground(buffer[i][3] or theme.window.text.color)
					setBackground(theme.window.color)
				else
					gpu.set(xpos,i+1,chunk[j])
					xpos = xpos + unicode.wlen(chunk[j])
				end
			end
		else
			setForeground(buffer[i][3] or theme.window.text.color)
			gpu.set(x+nickwidth+1,i+1,buffer[i][2])
		end
	end
end

local function drawTextbar(x,y,width,text)
	setBackground(theme.textbar.color)
	gpu.fill(x,y,width,1," ")
	if text ~= "" then
		setForeground(theme.textbar.text.color)
		gpu.set(x,y,unicode.sub(text,1,width))
	end
end

local customGPU = {
	gpuSetup = function(self, x,y,width,height)
		self.x=x
		self.y=y
		self.width=width
		self.height=height
		if self.gpu == nil then
			self.gpu = {
				set = function(x,y,s,v) return gpu.set(x+self.x-1,y+self.y-1,s,v ~= nil and v) end,
				get = function(x,y) return gpu.get(x+self.x-1,y+self.y-1) end,
				getResolution = function() return self.width, self.height end,
				copy = function(x,y,w,h,tx,ty) if ty ~= -1 then return gpu.copy(x+self.x-1,y+self.y-1,w,h,tx,ty) end end,
				fill = function(x,y,w,h,c) return gpu.fill(x+self.x-1,y+self.y-1,w,h,c) end,
			}
			setmetatable(self.gpu,{
				__index = function(_,k)
					if gpu[k] ~= nil then
						return gpu[k]
					end
				end
			})
		end
	end
}

local function _redraw(first)
	local yoffset
	local treewidth = persist.treewidth
	if config.wocchat.usetree then
		yoffset = 0
		if dirty.blocks then
			treewidth = 8
			for i = 1,#blocks do
				local block = blocks[i]
				if block.type == "server" or block.type == "dead_server" then
					treewidth=math.max(treewidth,unicode.len(theme.tree.group.prefix.str .. (block.support.NETWORK or block.name)))
				else
					treewidth=math.max(treewidth,unicode.len(theme.tree.entry.prefix.str .. block.name))
				end
			end
			if treewidth ~= persist.treewidth and not first then
				local old = screen.width-persist.treewidth-persist.listwidth-2
				local new = screen.width-treewidth-persist.listwidth-2
				gpu.copy(persist.treewidth+2,screen.height,math.min(new,old),1,old - new,0)
			end
			drawTree(treewidth)
			dirty.blocks = false
		end
	else
		treewidth, yoffset = -1, -1
		if dirty.blocks then
			drawTabs()
			dirty.blocks = false
		end
	end
	if treewidth ~= persist.treewidth then
		dirty.window = true
		dirty.title = true
		if treewidth ~= -1 then
			setBackground(theme.window.color)
			setForeground(theme.tree.color)
			gpu.fill(treewidth+1,2,1,screen.height-2,"▌")
			setBackground(theme.textbar.color)
			gpu.set(treewidth+1,screen.height,"▌")
			gpu.set(treewidth+1,1,"▌")
		end
	end
	local listwidth = persist.listwidth
	if dirty.nicks then
		listwidth = -1
		if blocks[blocks.active].names ~= nil then
			local names = blocks[blocks.active].names
			local prefix = blocks[blocks.active].parent.support.PREFIX or default_support.PREFIX
			prefix = prefix:match("%)(.*)")
			for i = 1,#names do
				listwidth=math.max(listwidth,unicode.len(names[i])+(names[i]:find("^[" .. prefix .. "]") and 0 or 1))
			end
			listwidth=listwidth+1
			drawList(listwidth,screen.height+yoffset)
		end
		dirty.nicks = false
	end
	if listwidth ~= persist.listwidth then
		dirty.window = true
		dirty.title = true
		setBackground(theme.tree.color)
		setForeground(theme.window.color)
		gpu.fill(screen.width-listwidth,2,1,screen.height-2+yoffset,"▌")
		setForeground(theme.textbar.color)
		gpu.set(screen.width-listwidth,screen.height+yoffset,"▌")
		gpu.set(screen.width-listwidth,1,"▌")
	end
	if dirty.title then
		local block = blocks[blocks.active]
		local title
		if block.title ~= nil then
			title = block.title
		elseif block.support and block.support.NETWORK then
			title = block.support.NETWORK .. " Main Window"
		else
			title = block.name .. " Main Window"
		end
		drawTextbar(treewidth+2,1,screen.width-treewidth-listwidth-2,title)
		dirty.title = false
	end
	if dirty.window then
		drawWindow(treewidth+2,screen.width-treewidth-listwidth-2,screen.height-2+yoffset,blocks[blocks.active].text)
		dirty.window = false
	end
	if first then
		drawTextbar(treewidth+2,screen.height+yoffset,screen.width-treewidth-listwidth-2,"")
	elseif listwidth < persist.listwidth then
		setBackground(theme.textbar.color)
		gpu.fill(screen.width-persist.listwidth,screen.height+yoffset,persist.listwidth-listwidth,1," ")
	end
	customGPU:gpuSetup(treewidth+2,screen.height+yoffset,screen.width-treewidth-listwidth-2,1)

	persist.window_width = screen.width-treewidth-listwidth-2
	persist.window_x = treewidth+2
	persist.listwidth = listwidth
	persist.treewidth = treewidth

	setBackground(theme.textbar.color)
	setForeground(theme.textbar.text.color)
end
local redrawHang = false
local function redraw(first)
	if not redrawHang then
		local ok, err = xpcall(_redraw, debug.traceback, first)
		if not ok then
			redrawHang = true
			gpu.setPaletteColor(theme.textbar.color,0)
			gpu.setPaletteColor(theme.textbar.text.color,0xFF0000)
			setForeground(theme.textbar.text.color)
			setBackground(theme.textbar.color)
			if config.wocchat.usetree then
				gpu.fill(1,1,screen.width,screen.height-1," ")
			else
			end
			gpu.set(1,1,"Rendering error!")
			local y = 3
			err = text.detab(err) .. "\n"
			for line in err:gmatch("(.-)\n") do
				gpu.set(1,y,line)
				y=y+1
			end
		end
	end
end

local helper = {}
function helper.write(sock,msg)
	sock:write(msg .. "\r\n")
	sock:flush()
end
function helper.addTextToBlock(block,user,msg,color)
	block.text[#block.text+1] = {user,msg,color}
	if block == blocks[blocks.active] then
		dirty.window = true
	else
		block.new = true
		dirty.blocks = true
	end
end
function helper.addText(user,msg,color)
	return helper.addTextToBlock(blocks[blocks.active],user,msg,color)
end
function helper.markDirty(...)
	for k, v in pairs({...}) do dirty[v] = true end
end
function helper.getSocket()
	local block = blocks[blocks.active]
	if block.sock then
		return block.sock
	elseif block.parent then
		return block.parent.sock
	end
end
function helper.joinServer(server)
	local server,id = config.server[server],server
	local nick = config.default.nick
	local block = {type="server",name=server.name,id=id,text={},nick=nick,children={},support={}}
	block.sock = internet.open(server.server)
	block.sock:setTimeout(0.05)
	block.sock:write(string.format("NICK %s\r\n", config.default.nick))
	block.sock:write(string.format("USER %s 0 * :%s\r\n", config.default.user, config.default.realname))
	block.sock:flush()
	blocks[#blocks + 1] = block
	blocks.active = #blocks
	helper.markDirty("blocks","window","nicks","title")
end
function helper.joinChannel(block,channel,switch)
	local cblock = {type="channel",name=channel,text={},title="",names={},parent=block,scroll=1}
	local look = block
	if #block.children > 0 then
		look = block.children[#block.children]
	end
	for i = 1,#blocks do
		if blocks[i] == look then
			table.insert(blocks,i+1,cblock)
			look = i+1
			break
		end
	end
	block.children[#block.children+1] = cblock
	if not switch then blocks.active = look end
	helper.markDirty("blocks","window","nicks","title")
	return cblock
end
function helper.findChannel(block,channel)
	local children = block.children
	for i = 1,#children do
		if children[i].name:lower() == channel:lower() then
			return children[i]
		end
	end
end
function helper.findOrJoinChannel(block,channel)
	local cblock = helper.findChannel(block,channel)
	if cblock then return cblock end
	cblock = helper.joinChannel(block,channel,true)
	cblock.title = "Dialog with " .. channel
	return cblock
end
function helper.closeChannel(cblock)
	local block = cblock.parent
	for i = 1,#block.children do
		if block.children[i] == cblock then
			table.remove(block.children,i)
			break
		end
	end
	local decrement = true
	for i = 1,#blocks do
		if blocks[i] == cblock then
			table.remove(blocks,i)
			break
		elseif blocks[i] == blocks[blocks.active] then
			decrement = false
		end
	end
	if decrement then
		blocks.active = blocks.active - 1
		helper.markDirty("blocks","window","nicks","title")
	else
		dirty.blocks = true
	end
end
function helper.sortList(block)
	local list = block.names
	local prefix = block.parent.support.PREFIX or default_support.PREFIX
	prefix = prefix:match("%)(.*)")
	table.sort(list,function(a,b)
		local as = prefix:find(a:sub(1,1),nil,true)
		local bs = prefix:find(b:sub(1,1),nil,true)
		if as and bs then
			if as == bs then
				return a:lower() < b:lower()
			else
				return as < bs
			end
		elseif as then
			return true
		elseif bs then
			return false
		else
			return a:lower() < b:lower()
		end
	end)
end

local function autocreate(table, key)
	table[key] = {}
	return table[key]
end

local function name(identity)
	return identity and identity:match("^[^!]+") or identity or "Anonymous"
end
local whois = setmetatable({}, {__index=autocreate})
local names = setmetatable({}, {__index=autocreate})

local ignore = {
	[213]=true, [214]=true, [215]=true, [216]=true, [217]=true,
	[218]=true, [231]=true, [232]=true, [233]=true, [240]=true,
	[241]=true, [244]=true, [244]=true, [246]=true, [247]=true,
	[250]=true, [300]=true, [316]=true, [361]=true, [362]=true,
	[363]=true, [373]=true, [384]=true, [492]=true,
	-- custom ignored responses.
	[265]=true, [266]=true, [330]=true
}

local replies = {
	RPL_WELCOME = "001",
	RPL_YOURHOST = "002",
	RPL_CREATED = "003",
	RPL_MYINFO = "004",
	RPL_ISUPPORT = "005",
	RPL_LUSERCLIENT = "251",
	RPL_LUSEROP = "252",
	RPL_LUSERUNKNOWN = "253",
	RPL_LUSERCHANNELS = "254",
	RPL_LUSERME = "255",
	RPL_AWAY = "301",
	RPL_UNAWAY = "305",
	RPL_NOWAWAY = "306",
	RPL_WHOISUSER = "311",
	RPL_WHOISSERVER = "312",
	RPL_WHOISOPERATOR = "313",
	RPL_WHOISIDLE = "317",
	RPL_ENDOFWHOIS = "318",
	RPL_WHOISCHANNELS = "319",
	RPL_CHANNELMODEIS = "324",
	RPL_NOTOPIC = "331",
	RPL_TOPIC = "332",
	RPL_TOPICWHOTIME = "333",
	RPL_NAMREPLY = "353",
	RPL_ENDOFNAMES = "366",
	RPL_MOTDSTART = "375",
	RPL_MOTD = "372",
	RPL_ENDOFMOTD = "376",
	RPL_WHOISSECURE = "671",
	RPL_HELPSTART = "704",
	RPL_HELPTXT = "705",
	RPL_ENDOFHELP = "706",
	RPL_UMODEGMSG = "718",

	ERR_BANLISTFULL = "478",
	ERR_CHANNELISFULL = "471",
	ERR_UNKNOWNMODE = "472",
	ERR_INVITEONLYCHAN = "473",
	ERR_BANNEDFROMCHAN = "474",
	ERR_CHANOPRIVSNEEDED = "482",
	ERR_UNIQOPRIVSNEEDED = "485",
	ERR_USERNOTINCHANNEL = "441",
	ERR_NOTONCHANNEL = "442",
	ERR_NICKCOLLISION = "436",
	ERR_NICKNAMEINUSE = "433",
	ERR_ERRONEUSNICKNAME = "432",
	ERR_WASNOSUCHNICK = "406",
	ERR_TOOMANYCHANNELS = "405",
	ERR_CANNOTSENDTOCHAN = "404",
	ERR_NOSUCHCHANNEL = "403",
	ERR_NOSUCHNICK = "401",
	ERR_MODELOCK = "742"
}

local function handleCommand(block, prefix, command, args, message)
	local nprefix = block.support.PREFIX or default_support.PREFIX
	nprefix = nprefix:match("%)(.*)")
	local sock = block.sock
	local nick = block.nick
	if command == "PING" then
		helper.write(sock, string.format("PONG :%s", message))
	elseif command == "NICK" then
		local oldNick, newNick = name(prefix), tostring(args[1] or message)
		if oldNick == nick then
			block.nick = newNick
		end
		for i = 1,#block.children do
			local cblock = block.children[i]
			for i = 1,#cblock.names do
				if cblock.names[i]:gsub("^[" .. nprefix .. "]+","") == oldNick then
					helper.addTextToBlock(cblock,"*",oldNick .. " is now known as " .. newNick .. ".")
					cblock.names[i] = newNick
					helper.sortList(cblock)
					break
				end
			end
			if cblock == blocks[blocks.active] then
				dirty.nicks = true
			end
		end
	elseif command == "MODE" then
		if #args == 2 then
			helper.addTextToBlock(block,"*","[" .. args[1] .. "] " .. name(prefix) .. " set mode".. ( #args[2] > 2 and "s" or "" ) .. " " .. tostring(args[2] or message) .. ".")
		else
			local setmode = {}
			local cumode = "+"
			args[2]:gsub(".", function(char)
				if char == "-" or char == "+" then
					cumode = char
				else
					table.insert(setmode, {cumode, char})
				end
			end)
			local d = {}
			local users = {}
			for i = 3, #args do
				users[i-2] = args[i]
			end
			users[#users+1] = message
			local last
			local ctxt = ""
			for c = 1, #users do
				if not setmode[c] then
					break
				end
				local mode = setmode[c][2]
				local pfx = setmode[c][1]=="+"
				local key = mode == "o" and (pfx and "opped" or "deoped") or
					mode == "v" and (pfx and "voiced" or "devoiced") or
					mode == "q" and (pfx and "quieted" or "unquieted") or
					mode == "b" and (pfx and "banned" or "unbanned") or
					"set " .. setmode[c][1] .. mode .. " on"
				if last ~= key then
					if last then
						helper.addTextToBlock(block,"*",ctxt)
					end
					ctxt = "[" .. args[1] .. "] " .. name(prefix) .. " " .. key
					last = key
				end
				ctxt = ctxt .. " " .. users[c]
			end
			if #ctxt > 0 then
				helper.addTextToBlock(block,"*",ctxt)
			end
		end
	elseif command == "QUIT" then
		local name = name(prefix)
		for i = 1,#block.children do
			local cblock = block.children[i]
			for i = 1,#cblock.names do
				if cblock.names[i]:gsub("^[" .. nprefix .. "]+","") == name then
					helper.addTextToBlock(cblock,"*", name .. " quit (" .. (message or "Quit") .. ").",theme.actions.part.color)
					table.remove(cblock.names,i)
					break
				end
			end
			if cblock == blocks[blocks.active] then
				dirty.nicks = true
			end
		end
	elseif command == "JOIN" then
		local name = name(prefix)
		if name == nick then
			helper.joinChannel(block,args[1])
		else
			local cblock = helper.findChannel(block,args[1])
			helper.addTextToBlock(cblock,"*",name .. " entered the room.",theme.actions.join.color)
			table.insert(cblock.names,name)
			helper.sortList(cblock)
			if cblock == blocks[blocks.active] then
				dirty.nicks = true
			end
		end
	elseif command == "PART" then
		local cblock = helper.findChannel(block,args[1])
		local name = name(prefix)
		if name == nick then
			helper.closeChannel(cblock)
		else
			helper.addTextToBlock(cblock,"*",name .. " has left the room (quit: " .. (message or "Quit") .. ").",theme.actions.part.color)
			for i = 1,#cblock.names do
				if cblock.names[i]:gsub("^[" .. nprefix .. "]+","") == name then
					table.remove(cblock.names,i)
					break
				end
			end
			if cblock == blocks[blocks.active] then
				dirty.nicks = true
			end
		end
	elseif command == "TOPIC" then
		local cblock = helper.findChannel(block,args[1])
		helper.addTextToBlock(cblock,"*",name(prefix) .. " has changed the topic to: " .. message)
	elseif command == "KICK" then
		local cblock = helper.findChannel(block,args[1])
		helper.addTextToBlock(cblock,"*",name(prefix) .. " kicked " .. args[2],theme.actions.part.color)
		for i = 1,#cblock.names do
			if cblock.names[i]:gsub("^[" .. nprefix .. "]+","") == args[2] then
				table.remove(cblock.names,i)
				break
			end
		end
		if cblock == blocks[blocks.active] then
			dirty.nicks = true
		end
	elseif command == "PRIVMSG" then
		local channel = args[1]
		if not (block.support.CHANTYPES or default_support.CHANTYPES):find(args[1]:sub(1,1),nil,true) then
			channel = name(prefix)
		end
		local ctcp = message:match("^\1(.-)\1$")
		if ctcp then
			local ctcp, param = ctcp:match("^(%S+) ?(.-)$")
			if ctcp ~= "ACTION" then
				helper.addTextToBlock(block,"*","[" .. name(prefix) .. "] CTCP " .. ctcp .. " " .. param)
			end
			ctcp = ctcp:upper()
			if ctcp == "ACTION" then
				local cblock = helper.findOrJoinChannel(block,channel)
				helper.addTextToBlock(cblock,"*", name(prefix) .. " " .. param)
			elseif ctcp == "TIME" then
				helper.write(sock, "NOTICE " .. name(prefix) .. " :\001TIME " .. os.date() .. "\001")
			elseif ctcp == "VERSION" then
				helper.write(sock, "NOTICE " .. name(prefix) .. " :\001VERSION WocChat " .. version .. " [OpenComputers]\001")
			elseif ctcp == "PING" then
				helper.write(sock, "NOTICE " .. name(prefix) .. " :\001PING " .. param .. "\001")
			end
		else
			if string.find(message, nick) then
				computer.beep()
			end
			local cblock = helper.findOrJoinChannel(block,channel)
			helper.addTextToBlock(cblock, name(prefix), message)
		end
	elseif command == "NOTICE" then
		local channel = args[1]
		if not (block.support.CHANTYPES or default_support.CHANTYPES):find(args[1]:sub(1,1),nil,true) then
			channel = name(prefix)
		end
		if string.find(message, nick) then
			computer.beep()
		end
		if channel == prefix then
			helper.addTextToBlock(block, "*", "[NOTICE] " .. message)
		else
			local cblock = helper.findOrJoinChannel(block,channel)
			helper.addTextToBlock(cblock, "-" .. name(prefix) .. "-", message)
		end
	elseif command == "ERROR" then
		helper.addTextToBlock(block,"*","[ERROR] " .. message)
	elseif tonumber(command) and ignore[tonumber(command)] then
	elseif command == replies.RPL_WELCOME then
		helper.addTextToBlock(block,"*",message)
		if config.server[block.id].channels ~= nil then
			for channel in (config.server[block.id].channels .. ","):gmatch("(.-),") do
				sock:write(string.format("JOIN %s\r\n", channel))
			end
			sock:flush()
		end
	elseif command == replies.RPL_YOURHOST then
		helper.addTextToBlock(block,"*",message)
	elseif command == replies.RPL_CREATED then
		helper.addTextToBlock(block,"*",message)
	elseif command == replies.RPL_MYINFO then
	elseif command == replies.RPL_ISUPPORT then
		for i = 2,#args do
			if args[i]:sub(1,1) == "-" then
				block.support[args[i]:sub(2)] = nil
			elseif args[i]:find("=",nil,true) then
				local parameter,value = args[i]:match("(.-)=(.+)")
				if value == "" then
					value = true
				end
				block.support[parameter] = value
			else
				block.support[args[i]] = true
			end
			if args[i] == "NETWORK" or args[i] == "-NETWORK" or args[i]:sub(1,8) == "NETWORK=" then
				helper.markDirty("blocks","title")
			end
		end
	elseif command == replies.RPL_LUSERCLIENT then
		helper.addTextToBlock(block,"*",message)
	elseif command == replies.RPL_LUSEROP then
	elseif command == replies.RPL_LUSERUNKNOWN then
	elseif command == replies.RPL_LUSERCHANNELS then
	elseif command == replies.RPL_LUSERME then
		helper.addTextToBlock(block,"*",message)
	elseif command == replies.RPL_AWAY then
		helper.addTextToBlock(block,"*",string.format("%s is away: %s", name(args[1]), message))
	elseif command == replies.RPL_UNAWAY or command == replies.RPL_NOWAWAY then
		helper.addTextToBlock(block,"*",message)
	elseif command == replies.RPL_WHOISUSER then
		local nick = args[2]:lower()
		whois[nick].nick = args[2]
		whois[nick].user = args[3]
		whois[nick].host = args[4]
		whois[nick].realName = message
	elseif command == replies.RPL_WHOISSERVER then
		local nick = args[2]:lower()
		whois[nick].server = args[3]
		whois[nick].serverInfo = message
	elseif command == replies.RPL_WHOISOPERATOR then
		local nick = args[2]:lower()
		whois[nick].isOperator = true
	elseif command == replies.RPL_WHOISIDLE then
		local nick = args[2]:lower()
		whois[nick].idle = tonumber(args[3])
	elseif command == replies.RPL_WHOISSECURE then
		local nick = args[2]:lower()
		whois[nick].secureconn = "Is using a secure connection"
	elseif command == replies.RPL_ENDOFWHOIS then
		local nick = args[2]:lower()
		local info = whois[nick]
		if info.nick then helper.addTextToBlock(block,"*","Nick: " .. info.nick) end
		if info.user then helper.addTextToBlock(block,"*","User name: " .. info.user) end
		if info.realName then helper.addTextToBlock(block,"*","Real name: " .. info.realName) end
		if info.host then helper.addTextToBlock(block,"*","Host: " .. info.host) end
		if info.server then helper.addTextToBlock(block,"*","Server: " .. info.server .. (info.serverInfo and (" (" .. info.serverInfo .. ")") or "")) end
		if info.secureconn then helper.addTextToBlock(block,"*",info.secureconn) end
		if info.channels then helper.addTextToBlock(block,"*","Channels: " .. info.channels) end
		if info.idle then helper.addTextToBlock(block,"*","Idle for: " .. info.idle) end
		whois[nick] = nil
	elseif command == replies.RPL_WHOISCHANNELS then
		local nick = args[2]:lower()
		whois[nick].channels = message
	elseif command == replies.RPL_CHANNELMODEIS then
		helper.addTextToBlock(block,"*","Channel mode for " .. args[1] .. ": " .. args[2] .. " (" .. args[3] .. ")")
	elseif command == replies.RPL_NOTOPIC then
		local cblock = helper.findChannel(block,args[2])
		helper.addTextToBlock(cblock,"*","No topic is set for " .. args[2] .. ".",theme.actions.title.color)
	elseif command == replies.RPL_TOPIC then
		local cblock = helper.findChannel(block,args[2])
		cblock.title = message
		helper.addTextToBlock(cblock,"*","Topic for " .. args[2] .. ": " .. message,theme.actions.title.color)
		if blocks[blocks.active] == cblock then
			dirty.title = true
		end
	elseif command == replies.RPL_TOPICWHOTIME then
		local cblock = helper.findChannel(block,args[2])
		helper.addTextToBlock(cblock,"*","Topic set by " .. args[3] .. " at " .. os.date("%a %b %d %H:%M:%S %Y",tonumber(args[4])),theme.actions.title.color)
		if blocks[blocks.active] == cblock then
			dirty.title = true
		end
	elseif command == replies.RPL_NAMREPLY then
		local channel = args[3]
		for name in (message .. " "):gmatch("(.-) ") do
			table.insert(names[channel], name)
		end
	elseif command == replies.RPL_ENDOFNAMES then
		local channel = args[2]
		local cblock = helper.findChannel(block,channel)
		cblock.names = names[channel]
		helper.sortList(cblock)
		if blocks[blocks.active] == cblock then
			dirty.nicks = true
		end
		names[channel] = nil
	elseif command == replies.RPL_MOTDSTART then
		if config.wocchat.showmotd then
			helper.addTextToBlock(block,"*",message .. args[1])
		end
	elseif command == replies.RPL_MOTD then
		if config.wocchat.showmotd then
			helper.addTextToBlock(block,"*",message)
		end
	elseif command == replies.RPL_ENDOFMOTD then
	elseif command == replies.RPL_HELPSTART or 
	command == replies.RPL_HELPTXT or 
	command == replies.RPL_ENDOFHELP then
		helper.addTextToBlock(block,"*",message)
	elseif command == replies.ERR_BANLISTFULL or
	command == replies.ERR_BANNEDFROMCHAN or
	command == replies.ERR_CANNOTSENDTOCHAN or
	command == replies.ERR_CHANNELISFULL or
	command == replies.ERR_CHANOPRIVSNEEDED or
	command == replies.ERR_ERRONEUSNICKNAME or
	command == replies.ERR_INVITEONLYCHAN or
	command == replies.ERR_NICKCOLLISION or
	command == replies.ERR_NOSUCHNICK or
	command == replies.ERR_NOTONCHANNEL or
	command == replies.ERR_UNIQOPRIVSNEEDED or
	command == replies.ERR_UNKNOWNMODE or
	command == replies.ERR_USERNOTINCHANNEL or
	command == replies.ERR_WASNOSUCHNICK or
	command == replies.ERR_MODELOCK then
		helper.addTextToBlock(block,"*","[ERROR]: " .. message)
	elseif tonumber(command) and (tonumber(command) >= 200 and tonumber(command) < 400) then
		helper.addTextToBlock(block,"*","[Response " .. command .. "] " .. table.concat(args, ", ") .. ": " .. (message or ""))
	elseif tonumber(command) and (tonumber(command) >= 400 and tonumber(command) < 600) then
		helper.addTextToBlock(block,"*","[Error] " .. table.concat(args, ", ") .. ": " .. (message or ""))
	else
		helper.addTextToBlock(block,"*","Unhandled command: " .. command .. ": " .. (message or ""))
	end
end

local commands = {}
function commands.help(...)
	local names = {}
	for k,v in pairs(commands) do
		names[#names+1] = k
	end
	table.sort(names)
	helper.addText("","Commands Available: " .. table.concat(names,", "))
end
function commands.server(...)
	local args,opts = shell.parse(...)
end
function commands.connect(...)
	local args,opts = shell.parse(...)
	if #args == 0 then
		helper.addText("","Usage: /connect serverid")
	elseif config.server[args[1]] == nil then
		helper.addText("","No server named '" .. args[1] .. "'",theme.actions.error.color)
	else
		helper.joinServer(args[1])
		redraw()
	end
end
function commands.join(...)
	local args = {...}
	if #args == 0 then
		helper.addText("","Usage: /join channel1 channel2 channel3 ...")
	else
		local sock = helper.getSocket()
		if sock == nil then
			helper.addText("","/join cannot be performed on this block",theme.actions.error.color)
		else
			for i = 1,#args do
				sock:write(string.format("JOIN %s\r\n", args[i]))
			end
			sock:flush()
		end
	end
end
function commands.part(...)
	local args = {...}
	local sock = helper.getSocket()
	if blocks[blocks.active].type == "dead_channel" then
		helper.closeChannel(blocks[blocks.active])
	elseif sock == nil then
		helper.addText("","/part cannot be performed on this block",theme.actions.error.color)
	else
		if #args == 0 then
			if blocks[blocks.active].type ~= "channel" then
				helper.addText("","/part cannot be performed on this block",theme.actions.error.color)
			elseif not (blocks[blocks.active].parent.support.CHANTYPES or default_support.CHANTYPES):find(blocks[blocks.active].name:sub(1,1),nil,true) then
				helper.closeChannel(blocks[blocks.active])
			else
				helper.write(sock, string.format("PART %s", blocks[blocks.active].name))
			end
		else
			for i = 1,#args do
				sock:write(string.format("PART %s\r\n", args[i]))
			end
			sock:flush()
		end
	end
end
function commands.quit(...)
	local args = {...}
	local sock = helper.getSocket()
	if sock == nil then
		helper.addText("","/quit cannot be performed on this block",theme.actions.error.color)
	else
		helper.write(sock, "QUIT :" .. (#args > 0 and table.concat(args," ") or config.default.quit))
	end
end
function commands.raw(...)
	local args = {...}
	if #args ~= 0 then
		local sock = helper.getSocket()
		if sock == nil then
			helper.addText("","/raw cannot be performed on this block",theme.actions.error.color)
		else
			helper.write(sock, string.format("%s", table.concat(args," ")))
		end
	end
end
function commands.me(...)
	local args = {...}
	if #args == 0 then
		helper.addText("","Usage: /me <action>")
	else
		local sock = helper.getSocket()
		if blocks[blocks.active].type ~= "channel" or sock == nil then
			helper.addText("","/me cannot be performed on this block",theme.actions.error.color)
		else
			helper.write(sock, string.format("PRIVMSG %s :\1ACTION %s\1", blocks[blocks.active].name, table.concat(args," ")))
			helper.addText("*",blocks[blocks.active].parent.nick .. " " .. table.concat(args," "))
		end
	end
end
function commands.redraw(...)
	local args = {...}
	if #args == 0 then
		helper.markDirty("blocks","window","nicks","title")
	else
		local good = true
		for i = 1,#args do
			if args[i] ~= "blocks" and args[i] ~= "window" and args[i] ~= "nicks" and args[i] ~= "title" then
				helper.addText("","Invalid type '" .. args[i] .. "'",theme.actions.error.color)
				good = false
			end
		end
		if not good then return end
		for i = 1,#args do
			dirty[args[i]] = true
		end
	end
	redraw()
end
function commands.msg(...)
	local args = {...}
	if #args < 2 then
		helper.addText("","Usage: /msg <nickname> <message>")
	else
		local sock = helper.getSocket()
		if sock == nil then
			helper.addText("","/msg cannot be performed on this block",theme.actions.error.color)
		else
			helper.write(sock, string.format("PRIVMSG %s :%s", args[1], table.concat(args," ",2)))
			local block = blocks[blocks.active]
			if block.parent ~= nil then
				block = block.parent
			end
			if (block.support.CHANTYPES or default_support.CHANTYPES):find(args[1]:sub(1,1),nil,true) then
				local cblock = helper.findChannel(block,args[1])
				if cblock then
					helper.addTextToBlock(cblock,block.nick,table.concat(args," ",2))
				end
			else
				local cblock = helper.findOrJoinChannel(block,args[1])
				helper.addTextToBlock(cblock,block.nick,table.concat(args," ",2))
			end
		end
	end
end
function commands.clear(...)
	blocks[blocks.active].text = {}
	dirty.window = true
end

local function main()
	if not fs.exists("/etc/wocchat.cfg") or options["dl-config"] then
		print("Downloading config ...")
		local f, reason = io.open("/etc/wocchat.cfg", "wb")
		if not f then
			errprint("Failed to open file for writing: " .. reason)
			return
		end
		local result, response = pcall(internet.request, "https://raw.githubusercontent.com/OpenPrograms/gamax92-Programs/master/wocchat/wocchat.cfg")
		if result then
			local result, reason = pcall(function()
				for chunk in response do
					f:write(chunk)
				end
			end)
			f:close()
			if not result then
				fs.remove("/etc/wocchat.cfg")
				errprint("HTTP request failed: " .. reason)
				return
			end
		else
			f:close()
			fs.remove("/etc/wocchat.cfg")
			errprint("HTTP request failed: " .. response)
			return
		end		
	end
	print("Loading config ...")
	loadConfig()
	if config.default.nick == nil then
		term.write("Enter your default nickname: ")
		local nick = term.read()
		config.default.nick = text.trim(nick)
	end
	if config.default.user == nil then
		config.default.user = config.default.nick:lower()
	end
	if config.default.realname == nil then
		config.default.realname = config.default.nick .. " [OpenComputers]"
	end
	print("Saving screen ...")
	saveScreen()
	gpu.setForeground(0xFFFFFF)
	gpu.setBackground(0)
	gpu.fill(1,1,screen.width,screen.height," ")
	gpu.set(screen.width/2-15,screen.height/2,"Loading theme, please wait ...")
	local i=0
	while theme[i] ~= nil do
		gpu.setPaletteColor(i,theme[i])
		gpu.fill(screen.width/2-16,screen.height/2+1,i*2+2,1,"█")
		i=i+1
	end
	term.setCursor(1,1)
	function persist.mouse(event, addr, x, y, button)
		local ok,err = pcall(function()
		if event == "touch" then
			if config.wocchat.usetree then
				if y <= #blocks and x <= persist.window_x-2 and y ~= blocks.active then
					blocks.active = y
					blocks[blocks.active].new = nil
					helper.markDirty("blocks","window","nicks","title")
					redraw()
				end
			else
				if y == screen.height and x > 1 then
					local bx = 2
					for i = 1,#blocks do
						local block = blocks[i]
						local name = block.name
						if block.type == "server" or block.type == "dead_server" then
							name = block.support.NETWORK or block.name
						end
						local bnx = bx+unicode.wlen(name)
						if x >= bx and x <= bnx then
							blocks.active = i
							helper.markDirty("blocks","window","nicks","title")
							redraw()
							break
						end
						bx=bnx+1
					end
				end
			end
			if x == screen.width and y <= (config.wocchat.usetree and screen.height or screen.height - 1) and blocks[blocks.active].names ~= nil then
				local height = (config.wocchat.usetree and screen.height or screen.height - 1)
				blocks[blocks.active].scroll = math.floor((y-1)/(height-1)*(#blocks[blocks.active].names-height)+1)
				dirty.nicks = true
			end
		elseif event == "scroll" then
			if x > screen.width-persist.listwidth and y <= screen.height+(config.wocchat.usetree and 0 or 1) then
				blocks[blocks.active].scroll = blocks[blocks.active].scroll - button
				dirty.nicks = true
			end
		end
		end)
		if not ok then
			helper.addText("EventErr",err,theme.actions.error.color)
		end
	end
	event.listen("touch",persist.mouse)
	event.listen("scroll",persist.mouse)
	persist.timer = event.timer(0.5, function()
		for i = 1,#blocks do
			local block = blocks[i]
			if block.sock ~= nil then
				local sock = block.sock
				repeat
					local ok, line = pcall(sock.read, sock)
					if ok then
						if not line then
							helper.addTextToBlock(block,"*","Connection lost.")
							pcall(sock.close, sock)
							block.sock = nil
							block.type = "dead_" .. block.type
							for j=1,#block.children do
								block.children[j].type = "dead_" .. block.children[j].type
							end
							dirty.blocks = true
							if blocks[blocks.active] == block then
								dirty.window = true
							end
							break
						end
						line = text.trim(line) -- get rid of trailing \r
						local origline = line
						local match, prefix = line:match("^(:(%S+) )")
						if match then line = line:sub(#match + 1) end
						local match, command = line:match("^(([^:]%S*))")
						if match then line = line:sub(#match + 1) end
						local args = {}
						repeat
							local match, arg = line:match("^( ([^:]%S*))")
							if match then
								line = line:sub(#match + 1)
								table.insert(args, arg)
							end
						until not match
						local message = line:match("^ :(.*)$")
						local hco, hcerr = pcall(handleCommand, block, prefix, command, args, message)
						if not hco then
							helper.addTextToBlock(block,"LuaError",hcerr,theme.actions.error.color)
						end
						if config.wocchat.showraw then
							helper.addTextToBlock(blocks[1],"RAW",origline)
						end
					end
				until not ok
			end
		end
	end, math.huge)
	persist.timer = event.timer(0.05, function()
		if dirty.blocks or dirty.title or dirty.window or dirty.nicks then
			redraw()
		end
	end, math.huge)
	redraw(true)
	for k,v in pairs(config.server) do
		if v.autojoin then
			helper.joinServer(k)
		end
	end
	local history = {}
	while true do
		if dirty.blocks or dirty.title or dirty.window or dirty.nicks then
			redraw()
		end
		setBackground(theme.textbar.color)
		setForeground(theme.textbar.text.color)
		local line = term.read(history,nil,function(line,pos)
			local block = blocks[blocks.active]
			if block.names == nil then
				return {}
			end
			local nprefix = (block.parent.support.PREFIX or default_support.PREFIX):match("%)(.*)")
			local line, extra = line:sub(1,pos-1), line:sub(pos)
			local base, word = (" " .. line):match("(.*%s)(.*)")
			base,word = base:sub(2),word:lower()
			local list = {}
			for i = 1,#block.names do
				local name = block.names[i]:gsub("^[" .. nprefix .. "]+","")
				if name:sub(1,#word):lower() == word then
					list[#list+1] = base .. name .. (base == "" and ": " or "") .. extra
				end
			end
			table.sort(list,function(a,b) return a:lower() < b:lower() end)
			if #list == 1 then
				list[2] = list[1] -- Prevent term.read stupidity
			end
			return list
		end)
		if line ~= nil then line = text.trim(line) end
		if line == "/exit" then break end
		if line:sub(1,1) == "/" and line:sub(1,2) ~= "//" then
			local parse = {}
			for part in (line:sub(2) .. " "):gmatch("(.-) ") do
				parse[#parse+1] = part
			end
			if commands[parse[1]] ~= nil then
				commands[parse[1]](table.unpack(parse,2))
			else
				helper.addText("","No such command: " .. parse[1])
			end
		elseif blocks[blocks.active].type == "channel" then
			if line:sub(1,2) == "//" then
				line = line:sub(2)
			end
			helper.write(blocks[blocks.active].parent.sock, string.format("PRIVMSG %s :%s",blocks[blocks.active].name,line))
			helper.addText(blocks[blocks.active].parent.nick,line)
		else
			helper.addText("","Cannot type on this window")
		end
	end
end

-- Hijack needed for term.read
local old_getPrimary = component.getPrimary
function component.getPrimary(componentType)
	checkArg(1, componentType, "string")
	assert(component.isAvailable(componentType), "no primary '" .. componentType .. "' available")
	if componentType == "gpu" then
		return customGPU.gpu or old_getPrimary(componentType)
	end
	return old_getPrimary(componentType)
end
local stat, err = xpcall(main,debug.traceback)
component.getPrimary = old_getPrimary
for i = 1,#blocks do
	if blocks[i].sock then
		pcall(blocks[i].sock.write, blocks[i].sock, "QUIT\r\n")
		pcall(blocks[i].sock.close, blocks[i].sock)
	end
end
if persist.mouse then
	event.ignore("touch",persist.mouse)
	event.ignore("scroll",persist.mouse)
end
if persist.timer then
	event.cancel(persist.timer)
end
if screen then
	restoreScreen()
end
print("Saving config ...")
local sok,srr = saveConfig()
if not sok then
	errprint("Failed to save config: " .. srr)
end
if not stat then
	errprint(err)
end
