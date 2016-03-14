local component = require("component")
local event = require("event")
local unicode = require("unicode")
local shell = require("shell")
local gpu = component.gpu

local args, options = shell.parse(...)
if #args ~= 1 then
	print([[Usage: ooci-oc filename

Options:
  --nores   Disable resolution switching
  --noswap  Disable resolution restoration
  --nopause Don't pause when finished]])
	return
end

local oerror = error
function error(str)
	oerror("Error: " .. str,0)
	os.exit(1)
end

local file, err = io.open(args[1], "rb")
if not file then
	error(err)
end
function r8()
	local char = file:read(1)
	return char and char:byte()
end
local function r16()
	return r8(file) | (r8(file) << 8)
end

if file:read(4) ~= "OOCI" then
	error("Invalid header!")
end

local hdrVersion = r8()
if hdrVersion > 1 then
	error("Unknown header version: " .. hdrVersion)
end

local width, height = r16(), r16()

local paletteCount = r8()
if paletteCount > 16 then
	error("Unsupported palette entry count: " .. paletteCount)
end

local pal = {}
for i=0,paletteCount-1 do
    local b, g, r = file:read(3):byte(1,-1)
    pal[i] = r << 16 | g << 8 | b
	local _=(gpu.getPaletteColor(i)~=pal[i] and gpu.setPaletteColor(i, pal[i]))
end
for i=0,239 do
	local r = math.floor((math.floor(i / 40.0) % 6) * 255 / 5.0)
	local g = math.floor((math.floor(i / 5.0) % 8) * 255 / 7.0)
	local b = math.floor((i % 5) * 255 / 4.0)
	pal[i+16] = r << 16 | g << 8 | b
end

local q={}
for i=0,255 do
	q[i]=unicode.char(0x2800+i)
end
local function byte2char(a) return q[a:byte()] end

local oldw,oldh
if not options.nores then
	oldw,oldh = gpu.getResolution()
	gpu.setResolution(width,height)
end

while true do
	local inst = r8()
	if not inst then
		break
	elseif inst == 0x00 then
		local col = r8()
		if col < 16 then
			gpu.setBackground(col,true)
		else
			gpu.setBackground(pal[col])
		end
	elseif inst == 0x01 then
		local col = r8()
		if col < 16 then
			gpu.setForeground(col,true)
		else
			gpu.setForeground(pal[col])
		end
	else
		local x = r8()
		local y = r8()
		if inst == 0x02 then
			gpu.set(x,y,q[r8()])
		elseif inst == 0x03 then
			local len = r8()
			gpu.set(x,y,q[r8()]:rep(len))
		elseif inst == 0x04 then
			local len = r8()
			gpu.set(x,y,q[r8()]:rep(len),true)
		elseif inst == 0x05 then
			gpu.set(x,y,(file:read(r8()):gsub(".", byte2char)))
		elseif inst == 0x06 then
			gpu.set(x,y,(file:read(r8()):gsub(".", byte2char)),true)
		else
			error("Unknown Instruction: " .. inst)
		end
	end
end
if not options.nopause then
	while true do
		local name,addr,char,key,player = event.pull("key_down")
		if key == 0x10 then
		    break
		end
	end
end
gpu.setBackground(0, false)
gpu.setForeground(16777215, false)
if not options.nores and not options.noswap then
	gpu.setResolution(oldw, oldh)
	gpu.fill(1, 1, oldw, oldh, " ")
end
