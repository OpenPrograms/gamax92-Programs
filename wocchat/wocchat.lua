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

local args, options = shell.parse(...)

print("Saving screen ...")
local palette = {}
for i = 0,15 do
	palette[i] = gpu.getPaletteColor()
end
local width,height = gpu.getResolution()
local screen = {}
local screen.cfg = {}
local screen.cbg = {}
for y = 1,height do
	screen[y] = {}
	for x = 1,width do
		screen[y][x] = { gpu.get(x,y) }
		screen.cfg[screen[y][x][2] .. "_" .. tostring(screen[y][x][4])] = true
		screen.cbg[screen[y][x][3] .. "_" .. tostring(screen[y][x][5])] = true
	end
end

print("Loading config ...")

function restoreScreen()
	local palrev = {}
	for i = 0,15 do
		palrev[palette[i]] = i
		gpu.setPaletteColor(i,palette[i])
	end
	for bgs in pairs(screen.cbg) do
		local bg,bp = bgs:match("(.-)_(.+)")
		if bp ~= "nil" then
			gpu.setBackground(bp+0,true)
		else
			gpu.setBackground(bg+0)
		end
		for fgs in pairs(screen.cfg) do
			local fg,fp = fgs:match("(.-)_(.+)")
			if fp ~= "nil" then
				gpu.setBackground(bp+0,true)
			else
				gpu.setBackground(bg+0)
			end
		end
	end
end

function main()
	gpu.fill(1,1,width,height," ")
end

local stat, err = pcall(main)
restoreScreen()
if not stat then

end
