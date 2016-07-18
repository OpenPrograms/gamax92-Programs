local shell = require("shell")
local term = require("term")
local text = require("text")
local fs = require("filesystem")
local component = require("component")
local computer = require("computer")
local event = require("event")
local process = require("process")
local sides = require("sides")
local unicode = require("unicode")

local ccpal = {0xF0F0F0,0xF2B233,0xE57FD8,0x99B2F2,0xDEDE6C,0x7FCC19,0xF2B2CC,0x4C4C4C,0x999999,0x4C99B2,0xB266E5,0x253192,0x7F664C,0x57A64E,0xCC4C4C,0x000000}
local ocpal = {0xFFFFFF,0xFFCC33,0xCC66CC,0x6699FF,0xFFFF33,0x33CC33,0xFF6699,0x333333,0xCCCCCC,0x336699,0x9933CC,0x333399,0x663300,0x336600,0xFF3333,0x000000}
local oldpal = {}

local args, opt = shell.parse(...)
local vconfig = {
	"apipath",
	"enable-shell",
	"enable-ccpal",
	"enable-debug",
	"enable-native-io",
	"enable-unicode",
}
for i = 1, #vconfig do
	vconfig[vconfig[i]]=true
	vconfig[i]=nil
end
local config = {
	apipath = "/rom/apis",
	["enable-shell"] = true,
	["enable-ccpal"] = false,
	["enable-debug"] = false,
	["enable-native-io"] = true,
	["enable-unicode"] = false,
}

if fs.exists("/etc/ccemu.cfg") then
	local code = "return {"
	for line in io.lines("/etc/ccemu.cfg") do
		code = code .. line .. ", "
	end
	code = code .. "}"
	local fn, err = load(code, "config", nil, {})
	if not fn then
		io.stderr:write("Failed to load config: " .. err .. "\n")
	else
		local ok, err = pcall(fn)
		if not ok then
			io.stderr:write("Failed to load config: " .. err .. "\n")
		else
			for k, v in pairs(err) do
				if vconfig[k] then
					config[k] = v
				else
					io.stderr:write("Invalid config entry: " .. k .. "\n")
				end
			end
		end
	end
else
	local f, err = io.open("/etc/ccemu.cfg", "wb")
	if not f then
		io.stderr:write("Failed to write config: " .. err .. "\n")
	else
		local keys = {}
		for k, v in pairs(config) do
			if type(v) ~= "number" then
				keys[#keys+1] = k
			end
		end
		table.sort(keys)
		for i = 1, #keys do
			local v = config[keys[i]]
			f:write("[" .. string.format("%q", keys[i]) .. "] = " .. (type(v) == "string" and string.format("%q", v) or tostring(v)) .. "\n")
		end
		f:close()
	end
end

local usageStr = [[Usage: ccemu (options) (program) (arguments)
 --help          What you see here
 --apipath=path  Load certain apis in folder
 --ccpal         Load CC's palette
 --native-io     Use OC's io api
 --noshell       Disable built in shell api
 --unicode       Experimentally support unicode
 --debug         Enable debugging]]

for k, v in pairs(opt) do
	local part = "'" .. string.rep("-", (type(v) == "string" or #k > 1) and 2 or 1) .. k .. "'"
	if k == "help" then
		print(usageStr)
		return
	elseif vconfig[k] then
		if (type(config[k]) == type(v)) or (config[k] > 2 and type(v) == "string") or (config[k] <= 2 and type(v) == "boolean") then
			config[k] = v
		elseif type(v) == "boolean" then
			print("Option: " .. part .. " takes an argument")
			print(usageStr)
			return
		else
			print("Option: " .. part .. " takes no argument")
			print(usageStr)
			return
		end
	elseif vconfig["enable-" .. k] then
		config["enable-" .. k] = true
	elseif k:sub(1, 2) == "no" and vconfig["enable-" .. k:sub(3)] then
		config["enable-" .. k:sub(3)] = false
	else
		print("Unknown option: " .. part .. "")
		print(usageStr)
		return
	end
end
for k, v in pairs(config) do
	if type(v) == "number" then
		if v == 1 then
			config[k] = false
		elseif v == 2 then
			config[k] = true
		else
			config[k] = nil
		end
	end
end

local dprint
if config["enable-debug"] then
	dprint = print
else
	dprint = function() end
end

if #args < 1 then
	print(usageStr)
	return
end

args[1] = shell.resolve(args[1], "lua")

if args[1] == nil or not fs.exists(args[1]) or fs.isDirectory(args[1]) then
	error("Invalid program to launch", 0)
end

if config.apipath ~= nil and not fs.isDirectory(config.apipath) then
	error("Invalid apipath", 0)
end

if component.gpu.maxDepth() > 1 then
	dprint("Setting up palette ...")
	component.gpu.setBackground(15, true)
	component.gpu.setForeground(0, true)
	local pal = config["enable-ccpal"] and ccpal or ocpal
	for i = 1, 16 do
		oldpal[i] = component.gpu.getPaletteColor(i-1)
		if oldpal[i] ~= pal[i] then
			component.gpu.setPaletteColor(i-1, pal[i])
		end
	end
end

local comp = {
	label = nil,
	eventStack = {},
	alarmC = 0,
	alarmTrans = {},
	timerC = 0,
	timerTrans = {},
}

local env, _wrap

local function tablecopy(orig)
	local orig_type = type(orig)
	local copy
	if orig_type == 'table' then
		copy = {}
		for orig_key, orig_value in pairs(orig) do
			copy[orig_key] = orig_value
		end
	else
		copy = orig
	end
	return copy
end

local function recurse_spec(results, path, spec)
	if spec:sub(1, 1) == "/" then spec = spec:sub(2) end
	if spec:sub(-1, -1) == "/" then spec = spec:sub(1, -2) end
	local segment = spec:match('([^/]*)'):gsub('/', '')
	local pattern = '^' .. segment:gsub("[%.%[%]%(%)%%%+%-%?%^%$]", "%%%1"):gsub("%z", "%%z"):gsub("%*", ".+") .. '$'

	if fs.isDirectory(path) then
		for file in fs.list(path) do
			file = file:gsub("/", "")
			if file:match(pattern) then
				local f = _wrap.combine(path, file)

				if fs.isDirectory(f) then
					table.insert(results, f)
					recurse_spec(results, f, spec:sub(#segment + 2))
				elseif spec == segment then
					table.insert(results, f)
				end
			end
		end
	end
end

function assertArg(n, eval, msg)
	if not eval then
		error(string.format("bad argument #%d (%s)", n, msg), 3)
	end
end

local envs = {}
_wrap = {
	-- TODO: Can getfenv and setfenv be recreated?
	getfenv = function(level)
		if level == nil then level = 1 end
		if type(level) == "function" then
			return envs[level] or env
		else
			checkArg(1, level, "number")
			assertArg(1, level > -1, "level must be non-negative")
			local info = debug.getinfo(math.max(level, 0) + 1)
			assertArg(1, info, "invalid level")
		end
		return env
	end,
	setfenv = function(level, tbl)
		if level == nil then level = 1 end
		checkArg(2, tbl, "table")
		checkArg(1, level, "number", "function")
		if type(level) == "number" then
			assertArg(1, level > -1, "level must be non-negative")
			local info = debug.getinfo(math.max(level, 0) + 1)
			assertArg(1, info, "invalid level")
		end
		if type(level) == "function" and envs[level] ~= nil then
			envs[level] = tbl
			return level
		else
			error("'setfenv' cannot change environment of given object", 2) -- Not a lie, :P
		end
	end,
	loadstring = function(str, source)
		source = source or "string"
		if type(str) ~= "string" and type(str) ~= "number" then error("bad argument #1 (string expected, got " .. type(str) .. ")", 2) end
		if type(source) ~= "string" and type(source) ~= "number" then error("bad argument #2 (string expected, got " .. type(str) .. ")", 2) end
		local source2 = tostring(source)
		local sSS = source2:sub(1, 1)
		if sSS == "@" or sSS == "=" then
			source2 = source2:sub(2)
		end
		local f, err
		local customenv = setmetatable({}, {
			__index = function(_, k) return f ~= nil and envs[f][k] or env[k] end,
			__newindex = function(_, k, v) if f ~= nil then envs[f][k] = v else env[k] = v end end,
		})
		f, err = load(str, "@" .. source2, nil, customenv)
		if f == nil then
			-- Get the normal error message
			local _, err = load(str, source, nil, customenv)
			return f, err
		end
		envs[f] = env
		return f, err
	end,
	setTextColor = function(color)
		checkArg(1, color, "number")
		component.gpu.setForeground(math.floor(math.log(color)/math.log(2)), true)
	end,
	setBackgroundColor = function(color)
		checkArg(1, color, "number")
		component.gpu.setBackground(math.floor(math.log(color)/math.log(2)), true)
	end,
	scroll = function(pos)
		checkArg(1, pos, "number")
		local sW, sH = component.gpu.getResolution()
		component.gpu.copy(1, 1, sW, sH, 0, -pos)
		if pos < 0 then
			component.gpu.fill(1, 1, sW, -pos, " ")
		else
			component.gpu.fill(1, sH-pos+1, sW, pos, " ")
		end
	end,
	getDir = function(path)
		checkArg(1, path, "string")
		return _wrap._combine(path, "..", true)
	end,
	find = function(spec)
		checkArg(1, spec, "string")
		local results = {}
		recurse_spec(results, '', spec)
		return results
	end,
	open = function(path, mode)
		checkArg(1, path, "string")
		checkArg(2, mode, "string")
		if mode == "r" then
			local _file = io.open(path, "rb")
			if _file == nil then return end
			local file = {
				close = function() return _file:close() end,
				readLine = function() return _file:read("*l") end,
				readAll = function() return _file:read("*a") end,
			}
			return file
		elseif mode == "rb" then
			local _file = io.open(path, "rb")
			if _file == nil then return end
			local file = {
				close = function() return _file:close() end,
				read = function() local chr = _file:read(1) if chr ~= nil then chr = chr:byte() end return chr end,
			}
			return file
		elseif mode == "w" or mode == "a" then
			local _file = io.open(path, mode .. "b")
			if _file == nil then return end
			local file = {
				close = function() return _file:close() end,
				writeLine = function(data) return _file:write(data .. "\n") end,
				write = function(data) return _file:write(data) end,
				flush = function() return _file:flush() end
			}
			return file
		elseif mode == "wb" or mode == "ab" then
			local _file = io.open(path, mode)
			if _file == nil then return end
			local file = {
				close = function() return _file:close() end,
				write = function(data) return _file:write(string.char(data)) end,
				flush = function() return _file:flush() end
			}
			return file
		else
			error("bad argument #2 (invalid mode)", 2)
		end
	end,
	list = function(path)
		checkArg(1, path, "string")
		local toret = {}
		for entry in fs.list(path) do
			toret[#toret + 1] = entry
		end
		return toret
	end,
	getDrive = function(path)
		checkArg(1, path, "string")
		if fs.exists(path) then
			return "hdd"
		end
	end,
	getFreeSpace = function(path)
		checkArg(1, path, "string")
		path = fs.canonical(path)
		local bp, bm = nil, ""
		for proxy, mount in fs.mounts() do
			if (path:sub(1, #mount) == mount or path .. "/" == mount) and #mount > #bm then
				bp, bm = proxy, mount
			end
		end
		return bp.spaceTotal() - bp.spaceUsed()
	end,
	makeDir = function(path)
		checkArg(1, path, "string")
		if fs.exists(path) then
			if not fs.isDirectory(path) then
				error("file with that name already exists", 2)
			end
		else
			local ret, err = fs.makeDirectory(path)
			if not ret then
				error(err, 2)
			end
		end
	end,
	move = function(frompath, topath)
		checkArg(1, frompath, "string")
		checkArg(2, topath, "string")
		if not fs.exists(frompath) then
			error("file not found", 2)
		elseif fs.exists(topath) then
			error("file exists", 2)
		else
			local ok, err = fs.rename(frompath, topath)
			if not ok then
				err = err or "unknown error"
				error(err, 2)
			end
		end
	end,
	copy = function(frompath, topath)
		checkArg(1, frompath, "string")
		checkArg(2, topath, "string")
		if not fs.exists(frompath) then
			error("file not found", 2)
		elseif fs.exists(topath) then
			error("file exists", 2)
		else
			local ok, err = fs.copy(frompath, topath)
			if not ok then
				error(err, 2)
			end
		end
	end,
	_combine = function(basePath, localPath, dummy)
		local path = ("/" .. basePath .. "/" .. localPath):gsub("\\", "/")

		local tPath = {}
		for part in path:gmatch("[^/]+") do
			if part ~= "" and part ~= "." then
				if part == ".." and #tPath > 0 and (dummy or tPath[1] ~= "..") then
					table.remove(tPath)
				else
					table.insert(tPath, part:sub(1, 255))
				end
			end
		end
		return table.concat(tPath, "/")
	end,
	combine = function(basePath, localPath)
		checkArg(1, basePath, "string")
		checkArg(2, localPath, "string")
		return _wrap._combine(basePath, localPath)
	end,
	getComputerID = function()
		return tonumber(computer.address():sub(1, 4), 16)
	end,
	setComputerLabel = function(label)
		checkArg(1, label, "string", "nil")
		comp.label = label
	end,
	queueEvent = function(event, ...)
		checkArg(1, event, "string")
		computer.pushSignal("ccemu:" .. event, ...)
	end,
	startTimer = function(timeout)
		checkArg(1, timeout, "number")
		local timerRet = comp.timerC
		comp.timerC = comp.timerC + 1
		local timer = event.timer(timeout, function()
			comp.timerTrans[timerRet] = nil
			computer.pushSignal("ccemu:timer", timerRet)
		end)
		comp.timerTrans[timerRet] = timer
		return timerRet
	end,
	setAlarm = function(time)
		checkArg(1, time, "number")
		assertArg(1, time >= 0 and time < 24, "number out of range")
		local curtime = os.time()
		local alarmRet = comp.alarmC
		comp.alarmC = comp.alarmC + 1
		local timeout = (time*3600) - (curtime%86400)
		if timeout < 0 then timeout = timeout + 86400 end
		comp.alarmTrans[alarmRet] = curtime + timeout
		return alarmRet
	end,
	cancelTimer = function(id)
		checkArg(1, id, "number")
		if id == id and comp.timerTrans[id] ~= nil then
			event.cancel(comp.timerTrans[id])
			comp.timerTrans[id] = nil
		end
	end,
	cancelAlarm = function()
		checkArg(1, id, "number")
		if id == id then
			comp.alarmTrans[id] = nil
		end
	end,
	time = function()
		return math.floor((os.time()%86400)/3.600)/1000
	end,
	day = function()
		return math.floor(os.time()/86400) + 1
	end
}

env = {
	_VERSION = "Luaj-jse 2.0.3",
	__inext = ipairs({}),
	tostring = tostring,
	tonumber = tonumber,
	unpack = table.unpack,
	getfenv = _wrap.getfenv,
	setfenv = _wrap.setfenv,
	rawequal = rawequal,
	rawset = rawset,
	rawget = rawget,
	setmetatable = setmetatable,
	getmetatable = getmetatable,
	next = next,
	type = type,
	select = select,
	assert = assert,
	error = error,
	ipairs = ipairs,
	pairs = pairs,
	pcall = pcall,
	xpcall = xpcall,
	loadstring = _wrap.loadstring,
	math = math,
	string = string,
	table = table,
	coroutine = coroutine,
	term = {
		clear = function() local x, y = term.getCursor() term.clear() term.setCursor(x, y) end,
		clearLine = function() local x, y = term.getCursor() term.clearLine() term.setCursor(x, y) end,
		getSize = function() return component.gpu.getResolution() end,
		getCursorPos = term.getCursor,
		setCursorPos = term.setCursor,
		setTextColor = _wrap.setTextColor,
		setTextColour = _wrap.setTextColor,
		setBackgroundColor = _wrap.setBackgroundColor,
		setBackgroundColour = _wrap.setBackgroundColor,
		setCursorBlink = term.setCursorBlink,
		scroll = _wrap.scroll,
		write = function(text) term.write(tostring(text)) end, -- TODO: Dummy serializer?
		isColor = function() return component.gpu.maxDepth() > 1 end,
		isColour = function() return component.gpu.maxDepth() > 1 end,
	},
	fs = {
		getDir = _wrap.getDir,
		find = _wrap.find,
		open = _wrap.open,
		list = _wrap.list,
		exists = fs.exists,
		isDir = fs.isDirectory,
		isReadOnly = function() return false end,
		getName = function(path) local name = fs.name(path) return name == "" and "root" or name end,
		getDrive = _wrap.getDrive,
		getSize = function(path) checkArg(1, path, "string") if not fs.exists(path) then error("file not found", 2) end return fs.size(path) end,
		getFreeSpace = _wrap.getFreeSpace,
		makeDir = _wrap.makeDir,
		move = _wrap.move,
		copy = _wrap.copy,
		delete = function(path) checkArg(1, path, "string") fs.remove(path) end,
		combine = _wrap.combine,
	},
	os = {
		clock = computer.uptime,
		getComputerID = _wrap.getComputerID,
		computerID = _wrap.getComputerID,
		setComputerLabel = _wrap.setComputerLabel,
		getComputerLabel = function() return comp.label end,
		computerLabel = function() return comp.label end,
		queueEvent = _wrap.queueEvent,
		startTimer = _wrap.startTimer,
		setAlarm = _wrap.setAlarm,
		cancelTimer = _wrap.cancelTimer,
		cancelAlarm = _wrap.cancelAlarm,
		time = _wrap.time,
		day = _wrap.day,
		shutdown = function() computer.shutdown(false) end,
		reboot = function() computer.shutdown(true) end,
	},
	-- TODO: Peripherals
	peripheral = {
		isPresent = function(side) checkArg(1, side, "string") return false end,
		getType = function(side) checkArg(1, side, "string") end,
		getMethods = function(side) checkArg(1, side, "string") end,
		call = function(side, method) checkArg(1, side, "string") checkArg(2, method, "string") error("no peripheral attached", 2) end,
	},
	bit = {
		blshift = bit32.lshift,
		brshift = bit32.arshift,
		blogic_rshift = bit32.rshift,
		bxor = bit32.bxor,
		bor = bit32.bor,
		band = bit32.band,
		bnot = bit32.bnot,
	}
}

env._G = env
if config["enable-unicode"] then
	env.string = tablecopy(string)
	env.string.reverse = unicode.reverse
	env.string.char = unicode.char
	env.string.sub = unicode.sub
	env.string.len = unicode.len
	env.string.lower = unicode.lower
	env.string.upper = unicode.upper
end

if component.isAvailable("internet") and component.internet.isHttpEnabled() then
	-- TODO: Can this be written so http.request doesn't hog the execution?
	--env.http = {
	--}
end

local redstone
if component.isAvailable("redstone") then
	redstone = component.redstone
else
	dprint("Using fake redstone api")
	local outputs = {[0]=0, 0, 0, 0, 0, 0}
	local bundled = {[0]=0, 0, 0, 0, 0, 0}
	redstone = {
		getInput = function()
			return 0
		end,
		getOutput = function(side)
			return outputs[side]
		end,
		setOutput = function(side, val)
			outputs[side] = val
		end,
		getBundledInput = function()
			return 0
		end,
		getBundledOutput = function(side, color)
			return bit32.band(bundled[side], 2^color) > 0 and math.huge or 0
		end,
		setBundledOutput = function (side, color, value)
			bundled[side] = bit32.band(bundled[side], bit32.bnot(2^color)) + (value > 0 and 2^color or 0)
		end,
	}
end
local validSides = {top=true, bottom=true, left=true, right=true, front=true, back=true}
env.redstone = {
	getSides = function() return {"top", "bottom", "left", "right", "front", "back"} end,
	getInput = function(side)
		checkArg(1, side, "string")
		assertArg(1, validSides[side], "invalid side")
		return redstone.getInput(sides[side]) ~= 0
	end,
	getOutput = function(side)
		checkArg(1, side, "string")
		assertArg(1, validSides[side], "invalid side")
		return redstone.getOutput(sides[side]) ~= 0
	end,
	setOutput = function(side, val)
		checkArg(1, side, "string")
		checkArg(2, val, "boolean")
		assertArg(1, validSides[side], "invalid side")
		return redstone.setOutput(sides[side], val and 15 or 0)
	end,
	getAnalogInput = function(side)
		checkArg(1, side, "string")
		assertArg(1, validSides[side], "invalid side")
		return redstone.getInput(sides[side])
	end,
	getAnalogOutput = function(side)
		checkArg(1, side, "string")
		assertArg(1, validSides[side], "invalid side")
		return redstone.getOutput(sides[side])
	end,
	setAnalogOutput = function(side, val)
		checkArg(1, side, "string")
		checkArg(2, val, "number")
		assertArg(1, validSides[side], "invalid side")
		return redstone.setOutput(sides[side], val)
	end,
	getBundledInput = function(side)
		checkArg(1, side, "string")
		assertArg(1, validSides[side], "invalid side")
		side = sides[side]
		local val
		for i = 0, 15 do
			if redstone.getBundledInput(side, i) > 0 then
				val = val + (2^i)
			end
		end
		return val
	end,
	getBundledOutput = function(side)
		checkArg(1, side, "string")
		assertArg(1, validSides[side], "invalid side")
		side = sides[side]
		local val
		for i = 0, 15 do
			if redstone.getBundledOutput(side, i) > 0 then
				val = val + (2^i)
			end
		end
		return val
	end,
	setBundledOutput = function(side, val)
		checkArg(1, side, "string")
		checkArg(2, val, "number")
		assertArg(1, validSides[side], "invalid side")
		side = sides[side]
		for i = 0, 15 do
			redstone.setBundledOutput(side, i, bit32.band(val, 2^color) > 0 and math.huge or 0)
		end
	end,
	testBundledInput = function(side, val)
		checkArg(1, side, "string")
		checkArg(2, val, "number")
		assertArg(1, validSides[side], "invalid side")
		-- TODO: Implement this
		return false
	end,
}
env.redstone.getAnalogueInput = env.redstone.getAnalogInput
env.redstone.getAnalogueOutput = env.redstone.getAnalogOutput
env.redstone.setAnalogueOutput = env.redstone.setAnalogOutput
env.rs = env.redstone

-- Bios entries:
function env.os.version()
	return "CCEmu 1.0"
end
function env.os.pullEventRaw(filter)
	return coroutine.yield(filter)
end
function env.os.pullEvent(filter)
	local e = table.pack(env.os.pullEventRaw(filter))
	if e[1] == "terminate" then
		error("interrupted", 0)
	end
	return table.unpack(e)
end
env.sleep = os.sleep
env.write = function(data)
	local count = 0
	local otw = text.wrap
	function text.wrap(...)
		local a, b, c = otw(...)
		if c then count = count + 1 end
		return a, b, c
	end
	local x = term.getCursor()
	local w = component.gpu.getResolution()
	term.write(data, unicode.len(data) + x - 1 > w)
	text.wrap = otw
	return count
end
env.print = function(...)
	local args = {...}
	for i = 1, #args do
		args[i] = tostring(args[i])
	end
	return env.write(table.concat(args, "\t") .. "\n")
end
env.printError = function(...) io.stderr:write(table.concat({...}, "\t") .. "\n") end
env.read = function(pwchar, hist)
	local line = term.read(tablecopy(hist), nil, nil, pwchar)
	if line == nil then
		return ""
	end
	return line:gsub("\n", "")
end
env.loadfile = loadfile
env.dofile = dofile
env.os.run = function(newenv, name, ...)
	local args = {...}
	setmetatable(newenv, {__index=env})
	local fn, err = loadfile(name, nil, newenv)
	if fn then
		local ok, err = pcall(function() fn(table.unpack(args)) end)
		if not ok then
			if err and err ~= "" then
				env.printError(err)
			end
			return false
		end
		return true
	end
	if err and err ~= "" then
		env.printError(err)
	end
	return false
end

local tAPIsLoading = {}
env.os.loadAPI = function(path)
	local sName = fs.name(path)
	if tAPIsLoading[sName] == true then
		env.printError("API " .. sName .. " is already being loaded")
		return false
	end
	tAPIsLoading[sName] = true

	local env2
	env2 = {
		getfenv = function() return env2 end
	}
	setmetatable(env2, {__index = env})
	local fn, err = loadfile(path, nil, env2)
	if fn then
		fn()
	else
		env.printError(err)
		tAPIsLoading[sName] = nil
		return false
	end

	local tmpcopy = {}
	for k, v in pairs(env2) do
		tmpcopy[k] = v
	end

	env[sName] = tmpcopy
	tAPIsLoading[sName] = nil
	return true
end
env.os.unloadAPI = function(name)
	if _name ~= "_G" and type(env[name]) == "table" then
		env[name] = nil
	end
end
env.os.sleep = os.sleep
if env.http ~= nil then
	-- TODO: http.get
	-- TODO: http.post
end

local apiblacklist = {
	colours = true,
}
if config["enable-native-io"] then
	dprint("Using OC io")
	apiblacklist.io = true
	env.io = io
end
if config.apipath ~= nil then
	for file in fs.list(config.apipath) do
		local path = config.apipath .. "/" .. file
		if not fs.isDirectory(path) and not apiblacklist[file] then
			dprint("Loading " .. file)
			local stat, err = pcall(env.os.loadAPI, path)
			if stat == false then
				env.printError(err)
			end
		else
			dprint("Ignoring " .. file)
		end
	end
end

if env.colors ~= nil then
	dprint("Adding colours from colors")
	env.colours = {}
	for k, v in pairs(env.colors) do
		if k == "gray" then k = "grey" end
		if k == "lightGray" then k = "lightGrey" end
		env.colours[k] = v
	end
end

local function getEvent()
	if #comp.eventStack > 0 then
		local e = comp.eventStack[1]
		table.remove(comp.eventStack, 1)
		return table.unpack(e)
	end
	local e = table.pack(pcall(event.pull, 1))
	table.remove(e, 1)
	if e[1] == nil then
	elseif e[1] == "key_down" then
		if e[3] >= 32 and e[3] ~= 127 then
			table.insert(comp.eventStack, {"char", unicode.char(e[3])})
		end
		return "key", e[4]
	elseif e[1] == "touch" then
		return "mouse_click", e[5] + 1, e[3], e[4]
	elseif e[1] == "drag" then
		return "mouse_drag", e[5] + 1, e[3], e[4]
	elseif e[1] == "scroll" then
		return "mouse_scroll", e[5], e[3], e[4]
	elseif e[1]:sub(1, 6) == "ccemu:" then
		e[1] = e[1]:sub(7)
		return table.unpack(e)
	elseif e[1] == "interrupted" then
		return "terminate"
	end
end

local function startProgram(filename)
	if config["enable-debug"] then
		io.stdout:write("Loading '" .. filename .. "' ... ")
	end

	local fn, err = loadfile(filename, nil, env)
	if not fn then
		dprint("Fail")
		error("Failed to load: " .. err, 0)
	end
	dprint("Done")

	local ccproc = coroutine.create(fn)
	local eventFilter

	local ok, err = coroutine.resume(ccproc, table.unpack(args, 2))
	if not ok then
		io.stderr:write(err .. "\n")
	end
	if coroutine.status(ccproc) ~= "dead" then
		eventFilter = err
		while true do
			for k,v in pairs(comp.alarmTrans) do
				if os.time() >= v then
					comp.alarmTrans[k] = nil
					computer.pushSignal("ccemu:alarm", k)
				end
			end
			local ccevent = table.pack(getEvent())
			if ccevent[1] ~= nil and (eventFilter == nil or ccevent[1] == eventFilter) then
				local ok, err = coroutine.resume(ccproc, table.unpack(ccevent))
				if not ok then
					io.stderr:write(err .. "\n")
				end
				if coroutine.status(ccproc) == "dead" then
					break
				end
				eventFilter = err
			end
		end
	end
end

-- Shell api
local oldpath
local oldalias
if config["enable-shell"] then
	dprint("Using fake shell api")
	oldpath = shell.getPath()
	oldalias = tablecopy(select(2, shell.aliases()))
	for alias in pairs(oldalias) do
		shell.setAlias(alias, nil)
	end

	env.shell = {
		dir = shell.getWorkingDirectory,
		setDir = shell.setWorkingDirectory,
		path = shell.getPath,
		setPath = shell.setPath,
		resolve = function(path) checkArg(1, path, "string") return shell.resolve(path) end,
		resolveProgram = function(path) checkArg(1, path, "string") return shell.resolve(path, "lua") end,
		aliases = function() return tablecopy(select(2, shell.aliases())) end,
		setAlias = function(alias, value) checkArg(1, alias, "string") checkArg(2, value, "string") shell.setAlias(alias, value) end,
		clearAlias = function(alias) checkArg(1, alias, "string") shell.setAlias(alias, nil) end,
		programs = function(hidden)
			local firstlist = {}
			for part in string.gmatch(shell.getPath(), "[^:]+") do
				part = shell.resolve(part)
				if fs.isDirectory(part) then
					for entry in fs.list(part) do
						if not fs.isDirectory(env.fs.combine(part, entry)) and (hidden or string.sub(entry, 1, 1) ~= ".") then
							firstlist[entry] = true
						end
					end
				end
			end
			local list = {}
			for entry, _ in pairs(firstlist) do
				table.insert(list, entry)
			end
			table.sort(list)
			return list
		end,
		getRunningProgram = function() return args[1] end,
		run = function(command, ...) return shell.execute(command, nil, ...) end,
		openTab = function() end,
		switchTab = function() end,
	}
	
	if fs.exists("/rom/startup") then
		startProgram("/rom/startup")
	end
end

startProgram(args[1])

if config["enable-shell"] then
	shell.setPath(oldpath)
	local badalias = tablecopy(select(2, shell.aliases()))
	for alias in pairs(badalias) do
		shell.setAlias(alias, nil)
	end
	for alias, value in pairs(oldalias) do
		shell.setAlias(alias, value)
	end
end
component.gpu.setBackground(0x000000)
component.gpu.setForeground(0xFFFFFF)
if component.gpu.maxDepth() > 1 then
	dprint("Restoring palette ...")
	for i = 1, 16 do
		component.gpu.setPaletteColor(i-1, oldpal[i])
	end
end
