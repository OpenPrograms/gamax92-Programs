local args = {...}
if #args ~= 2 then
	print("Usage: ooci2ctif filename outname")
	return
end

local file, err = io.open(args[1], "rb")
if not file then
	print(err)
	return
end
local function check(a, b, c)
	if a ~= b then
		file:close()
		error(c,0)
		os.exit(1)
	end
	return a
end
local function r8()
	local char = file:read(1)
	return char and char:byte()
end
local function r16()
	return r8(file)+(r8(file)*256)
end

print("Warning: The CTIF files this Decompiler produces are not bit identical, but visually identical.")
check(file:read(4), "OOCI", "Invalid magic bytes")
check(r8(), 1, "Unknown header version")
local width, height = r16(), r16()
local palCount = r8()
check(palCount <= 16, true, "Unsupported palette entry count: " .. palCount)
local pal={}
for i=0,palCount-1 do
	pal[i] = {file:read(3):byte(1, -1)}
end
local img={}
for y=1,height do
	img[y]={}
end

-- Borrowed from ctif-oc.lua
local q = {}
for i=0,255 do
  local dat = (i & 0x01) << 7
  dat = dat | (i & 0x02) >> 1 << 6
  dat = dat | (i & 0x04) >> 2 << 5
  dat = dat | (i & 0x08) >> 3 << 2
  dat = dat | (i & 0x10) >> 4 << 4
  dat = dat | (i & 0x20) >> 5 << 1
  dat = dat | (i & 0x40) >> 6 << 3
  dat = dat | (i & 0x80) >> 7
  q[dat] = i
end

io.stdout:write("Decompiling Image ... ")
local curb, curf
while true do
	local inst = r8()
	if not inst then
		break
	elseif inst == 0x00 then
		curb = r8()
	elseif inst == 0x01 then
		curf = r8()
	else
		local x = r8()
		local y = r8()
		if inst == 0x02 then
			img[y][x]={curb,curf,q[r8()]}
		elseif inst == 0x03 then
			local len, char = r8(), q[r8()]
			for i=x,x+len-1 do
				img[y][i]={curb,curf,char}
			end
		elseif inst == 0x04 then
			local len, char = r8(), q[r8()]
			for i=y,y+len-1 do
				img[i][x]={curb,curf,char}
			end
		elseif inst == 0x05 then
			local len = r8()
			for i=x,x+len-1 do
				img[y][i]={curb,curf,q[r8()]}
			end
		elseif inst == 0x06 then
			local len = r8()
			for i=y,y+len-1 do
				img[i][x]={curb,curf,q[r8()]}
			end
		else
			error("Unknown Instruction: " .. inst)
		end
	end
end
file:close()
print("Done!")
io.stdout:write("Writing Image ... ")

local newfile, err = io.open(args[2],"wb")
if not newfile then
	print(err)
	return
end
local function w8(...)
	return newfile:write(string.char(...))
end

-- Write header
newfile:write("CTIF")
w8(1) -- Version
w8(0) -- Platform Variant
w8(1,0) -- Platform ID
w8(width,0) -- Width
w8(height,0) -- Height
w8(2) -- Char Width
w8(4) -- Char Height
w8(8) -- BPC
w8(3) -- BPPE
-- Write palette colors
w8(16,0) -- Number of Palette Entries
for i = 0,15 do
	w8(table.unpack(pal[i],1,3))
end
--Write image data
for y=1,height do
	for x=1,width do
		w8(table.unpack(img[y][x],1,3))
	end
end
newfile:close()
print("Done!")
