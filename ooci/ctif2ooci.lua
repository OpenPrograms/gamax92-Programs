local args = {...}
if #args ~= 2 then
	print("Usage: ctif2ooci filename outname")
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
	return file:read(1):byte()
end
local function r16()
	return r8(file)+(r8(file)*256)
end

check(file:read(4), "CTIF", "Invalid magic bytes")
check(r8(), 1, "Unknown header version")
check(r8(), 0, "Unknown platform variant")
check(r16(), 1, "Unknown platform ID")
local width, height = r16(), r16()
check(r8(), 2, "Invalid character width")
check(r8(), 4, "Invalid character height")
local bpp = r8()
check(r8(), 3, "Invalid palette entry size")
check(r16(), 16, "Invalid palette entry count")
local pal={}
for i=0,15 do
	pal[i] = {file:read(3):byte(1, -1)}
end
local img={}
for y=1,height do
	img[y]={}
	for x=1,width do
		img[y][x]={file:read(3):byte(1, -1)}
	end
end
file:close()

local newfile, err = io.open(args[2],"wb")
if not newfile then
	print(err)
	return
end
local function w8(...)
	return newfile:write(string.char(...))
end

-- Gather palette usage stats
local prestats = {}
for y = 1,height do
	for x = 1,width do
		local key = string.char(img[y][x][1], img[y][x][2])
		if prestats[key] == nil then
			prestats[key] = 0
		end
		prestats[key] = prestats[key] + 1
	end
end
local stats = {}
for k,usage in pairs(prestats) do
	local ti,bi = k:byte(1,-1)
	stats[#stats+1] = {ti,bi,usage}
end
table.sort(stats,function(a,b) return a[3] > b[3] end)

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
  q[i] = dat
end

-- Write header
newfile:write("OOCI")
w8(1) -- Version
w8(width,0) -- Width
w8(height,0) -- Height
-- Write palette colors
w8(16) -- Number of Palette Entries
for i = 0,15 do
	w8(table.unpack(pal[i],1,3))
end

local callsbg, callsfg, callsd = 0, 0, 0
local lastti, lastbi

io.stdout:write("Testing drawing methods ... ")
io.stdout:flush()

-- Horizontal, Vertical, and Dynamic check
local horiz = {}
local vertz = {}
local dynam = {}
os.sleep(0)
for i = 1,#stats do
	local ti = stats[i][1]
	local bi = stats[i][2]
	local calls = 0
	for y = 1,height do
		local blockcount = 0
		for x = 1,width do
			if img[y][x][1] == ti and img[y][x][2] == bi then
				blockcount = blockcount + 1
			else
				if blockcount > 0 then
					calls = calls + 1
				end
				blockcount = 0
			end
		end
		if blockcount > 0 then
			calls = calls + 1
		end
	end
	horiz[i] = calls
end
os.sleep(0)
for i = 1,#stats do
	local ti = stats[i][1]
	local bi = stats[i][2]
	local calls = 0
	for x = 1,width do
		local blockcount = 0
		for y = 1,height do
			if img[y][x][1] == ti and img[y][x][2] == bi then
				blockcount = blockcount + 1
			else
				if blockcount > 0 then
					calls = calls + 1
				end
				blockcount = 0
			end
		end
		if blockcount > 0 then
			calls = calls + 1
		end
	end
	vertz[i] = calls
end
os.sleep(0)
for i = 1,#stats do
	local ti = stats[i][1]
	local bi = stats[i][2]
	local calls = 0
	local donttouch = {}
	for y = 1,height do
		donttouch[y] = {}
	end
	for y = 1,height do
		for x = 1,width do
			if img[y][x][1] == ti and img[y][x][2] == bi and donttouch[y][x] ~= true then
				local xlength = 0
				local ylength = 0
				for nx = x,width do
					if img[y][nx][1] ~= ti or img[y][nx][2] ~= bi then break end
					xlength = xlength + 1
				end
				for yx = y,height do
					if img[yx][x][1] ~= ti or img[yx][x][2] ~= bi then break end
					ylength = ylength + 1
				end
				if xlength > ylength then
					calls = calls + 1
					for brk = x,x+xlength-1 do
						donttouch[y][brk] = true
					end
				else
					calls = calls + 1
					for brk = y,y+ylength-1 do
						donttouch[brk][x] = true
					end
				end
			end
		end
	end
	dynam[i] = calls
end
os.sleep(0)
print("Done!")
io.stdout:write("Writing Image ... ")
-- Go through stack
local function horizemit(braille,startx,y)
	if #braille > 0 then
		local same = true
		for i = 2,#braille do
			if braille[i] ~= braille[1] then
				same = false
				break
			end
		end
		if #braille>1 then
			if same then
				w8(0x03,startx,y,#braille,braille[1])
			else
				w8(0x05,startx,y,#braille,table.unpack(braille))
			end
		else
			w8(0x02,startx,y,braille[1])
		end
		callsd = callsd + 1
	end
end
local function vertzemit(braille,x,starty)
	if #braille > 0 then
		local same = true
		for i = 2,#braille do
			if braille[i] ~= braille[1] then
				same = false
				break
			end
		end
		if #braille>1 then
			if same then
				w8(0x04,x,starty,#braille,braille[1])
			else
				w8(0x06,x,starty,#braille,table.unpack(braille))
			end
		else
			w8(0x02,x,starty,braille[1])
		end
		callsd = callsd + 1
	end
end
for i = 1,#stats do
	local ti = stats[i][1]
	local bi = stats[i][2]
	if lastti ~= ti then
		w8(0x00, ti)
		callsbg = callsbg + 1
		lastti = ti
	end
	if lastbi ~= bi and bi ~= ti then
		w8(0x01, bi)
		callsfg = callsfg + 1
		lastbi = bi
	end
	if horiz[i] < vertz[i] and horiz[i] < dynam[i] then
		for y = 1,height do
			local braille = {}
			local startx = 1
			for x = 1,width do
				if img[y][x][1] == ti and img[y][x][2] == bi then
					if #braille == 0 then startx = x end
					braille[#braille+1] = q[img[y][x][3]]
				else
					horizemit(braille,startx,y)
					braille = {}
				end
			end
			horizemit(braille,startx,y)
		end
	elseif vertz[i] < horiz[i] and vertz[i] < dynam[i] then
		for x = 1,width do
			local braille = {}
			local starty = 1
			for y = 1,height do
				if img[y][x][1] == ti and img[y][x][2] == bi then
					if #braille == 0 then starty = y end
					braille[#braille+1] = q[img[y][x][3]]
				else
					vertzemit(braille,x,starty)
					braille = {}
				end
			end
			vertzemit(braille,x,starty)
		end
	else
		local donttouch = {}
		for y = 1,height do
			donttouch[y] = {}
		end
		for y = 1,height do
			for x = 1,width do
				if img[y][x][1] == ti and img[y][x][2] == bi and donttouch[y][x] ~= true then
					local xlength = 0
					local ylength = 0
					for nx = x,width do
						if img[y][nx][1] ~= ti or img[y][nx][2] ~= bi then break end
						xlength = xlength + 1
					end
					for yx = y,height do
						if img[yx][x][1] ~= ti or img[yx][x][2] ~= bi then break end
						ylength = ylength + 1
					end
					if xlength == 1 and ylength == 1 then
						w8(0x02,x,y,q[img[y][x][3]])
						donttouch[y][x] = true
					else
						local braille = {}
						local extra
						if xlength > ylength then
							extra = 0x03
							for brk = x,x+xlength-1 do
								donttouch[y][brk] = true
								braille[#braille+1] = q[img[y][brk][3]]
							end
						else
							extra = 0x04
							for brk = y,y+ylength-1 do
								donttouch[brk][x] = true
								braille[#braille+1] = q[img[brk][x][3]]
							end
						end
						local same = true
						for i = 2,#braille do
							if braille[i] ~= braille[1] then
								same = false
								break
							end
						end
						if same and #braille > 2 then
							w8(extra,x,y,#braille,braille[1])
						else
							w8(extra+2,x,y,#braille,table.unpack(braille))
						end
					end
					callsd = callsd + 1
				end
			end
		end
	end
end
newfile:close()
print("Done!")
print(callsbg,callsfg,callsd,callsbg+callsfg+callsd,((callsbg/128)+(callsfg/128)+(callsd/256))/20 .. "s")
