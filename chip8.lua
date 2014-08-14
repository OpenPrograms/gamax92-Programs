--[[
  This requires OCLights2.
  Sadly, I don't have compiled builds of this, so go here and build this:
  https://github.com/gamax92/CCLights2/tree/opencomputers
--]]
local component = require("component")
local computer = require("computer")
local fs = require("filesystem")
local keyboard = require("keyboard")
local event = require("event")
local shell = require("shell")

-- You can setup the keylayout here:
local keylayout = {
{"1","2","3","4"}, -- 1,2,3,C
{"Q","W","E","R"}, -- 4,5,6,D
{"A","S","D","F"}, -- 7,8,9,E
{"Z","X","C","V"}, -- A,0,B,F
}

local function errprint(...)
	local args = {...}
	for i = 1,#args do
		io.stderr:write(tostring(args[i]))
		if i < #args then
			io.stderr:write("\t")
		end
	end
	io.stderr:write("\n")
end

local args,opt = shell.parse(...)

if #args ~= 1 then
	print("Usage: chip8 [OPTIONS] rom")
	print(" -ipf=%d  Instructions per frame")
	return
end

local romfile = shell.resolve(args[1])
if not fs.exists(romfile) then
	errprint("No such file")
	return
end

if component.isAvailable("ocl_gpu") == nil then
	errprint("Could not find a OCLights2 GPU")
	return
end

local gpu = component.ocl_gpu

local playSound
if component.isAvailable("masssound") then
	print("Detected a MassSound card")
	playSound = function() component.masssound.playSound("note.pling") end
else
	print("Falling back to computer.beep")
	playSound = function() computer.beep(300,0) end
end

-- Initialize the GPU
print("Initializing GPU ...")
gpu.bindTexture(0) -- Bind screen
local gW,gH = gpu.getSize()
if gW < 64 or gH < 32 then
	errprint("Your Monitor attached to the GPU is too small (" .. gW .. "," .. gH .. ")")
	return
end
local gpu_scale = math.floor(math.min(gW/64,gH/32))
gpu.setColor(64,64,64,255)
gpu.fill() -- Fill in blank areas
gpu.setColor(0,0,0,255)
gpu.filledRectangle(0, 0, 64 * gpu_scale, 32 * gpu_scale) -- Black out Actual Display

-- Initialize Emulator
print("Initializing Emulator ...")
local chip8 = {
	mem = {},
	stack = {},
	display = {},
	ghost = {},
	keycode = {},
	keyflip = {},
	keystate = {},
	PC = 512,
	I = 512,
	REG = {},
	delay = 0,
	sound = 0,
	IPF = 10, -- Instructions Per Frame
	PDS = 50, -- Pixel Decrement Speed, set to 255 to disable.
	running = true,
}
for i = 0,4095 do
	chip8.mem[i] = 0
end
local fontset = {
0xF0, 0x90, 0x90, 0x90, 0xF0,
0x20, 0x60, 0x20, 0x20, 0x70,
0xF0, 0x10, 0xF0, 0x80, 0xF0,
0xF0, 0x10, 0xF0, 0x10, 0xF0,
0x90, 0x90, 0xF0, 0x10, 0x10,
0xF0, 0x80, 0xF0, 0x10, 0xF0,
0xF0, 0x80, 0xF0, 0x90, 0xF0,
0xF0, 0x10, 0x20, 0x40, 0x40,
0xF0, 0x90, 0xF0, 0x90, 0xF0,
0xF0, 0x90, 0xF0, 0x10, 0xF0,
0xF0, 0x90, 0xF0, 0x90, 0x90,
0xE0, 0x90, 0xE0, 0x90, 0xE0,
0xF0, 0x80, 0x80, 0x80, 0xF0,
0xE0, 0x90, 0x90, 0x90, 0xE0,
0xF0, 0x80, 0xF0, 0x80, 0xF0,
0xF0, 0x80, 0xF0, 0x80, 0x80}
print("Loading fontset ...")
for i = 1,80 do
    chip8.mem[i-1] = fontset[i]
end
for y = 0,31 do
	chip8.display[y] = {}
	for x = 0,63 do
		chip8.display[y][x] = false
	end
end
for i = 0,15 do
	chip8.REG[i] = 0
end
chip8.keycode[00] = keyboard.keys[keylayout[4][2]:lower()]
chip8.keycode[01] = keyboard.keys[keylayout[1][1]:lower()]
chip8.keycode[02] = keyboard.keys[keylayout[1][2]:lower()]
chip8.keycode[03] = keyboard.keys[keylayout[1][3]:lower()]
chip8.keycode[04] = keyboard.keys[keylayout[2][1]:lower()]
chip8.keycode[05] = keyboard.keys[keylayout[2][2]:lower()]
chip8.keycode[06] = keyboard.keys[keylayout[2][3]:lower()]
chip8.keycode[07] = keyboard.keys[keylayout[3][1]:lower()]
chip8.keycode[08] = keyboard.keys[keylayout[3][2]:lower()]
chip8.keycode[09] = keyboard.keys[keylayout[3][3]:lower()]
chip8.keycode[10] = keyboard.keys[keylayout[4][1]:lower()]
chip8.keycode[11] = keyboard.keys[keylayout[4][3]:lower()]
chip8.keycode[12] = keyboard.keys[keylayout[1][4]:lower()]
chip8.keycode[13] = keyboard.keys[keylayout[2][4]:lower()]
chip8.keycode[14] = keyboard.keys[keylayout[3][4]:lower()]
chip8.keycode[15] = keyboard.keys[keylayout[4][4]:lower()]
for i = 0,15 do
	chip8.keyflip[chip8.keycode[i]] = i
	chip8.keystate[i] = false
end

os.sleep(0.05) -- Above may be LVM intensive.

-- Load ROM
print("Loading ROM ...")
local file = io.open(romfile,"rb")
if file == nil then
	errprint("Could not open file")
end
local index = 512
while true do
	local data = file:read(1)
	if data == nil then break end
	chip8.mem[index] = data:byte()
	index = index + 1
end
file:close()

os.sleep(0.05) -- Above may be LVM intensive.

local keywait = { false, -1 }

event.listen("key_down",function(name,uuid,char,key,who)
	if key == keyboard.keys["f1"] then chip8.running = false end
	if chip8.keyflip[key] ~= nil then
		chip8.keystate[chip8.keyflip[key]] = true
		if keywait[1] == true then
			keywait[1] = false
			chip8.REG[keywait[2]] = chip8.keyflip[key]
		end
	end
end)
event.listen("key_up",function(name,uuid,char,key,who)
	if chip8.keyflip[key] ~= nil then
		chip8.keystate[chip8.keyflip[key]] = false
	end
end)

--Start emulating
print("Beginning Emulation ...")
while chip8.running do
	if keywait[1] ~= true then
		for i = 1,chip8.IPF do
			local opcode = chip8.mem[chip8.PC] * 256 + chip8.mem[chip8.PC + 1] -- Opcodes are two bytes
			chip8.PC = (chip8.PC + 2) % 4096 -- Advance PC
			-- Pull appart the opcode for easier processing.
			local base = math.floor(opcode/4096)
			local address = opcode % 4096
			local pX = math.floor(opcode/256)%16
			local pY = math.floor(opcode/16)%16
			local subbase = opcode%16
			local value = opcode%256
			if base == 0 then -- Call RCA 1802 program
				if address == 0x0E0 then
					for y = 0,31 do
						for x = 0,63 do
							chip8.display[y][x] = false
						end
					end
					gpu.setColor(0,0,0,255)
					gpu.filledRectangle(0, 0, 64 * gpu_scale, 32 * gpu_scale)
				elseif address == 0x0EE then
					-- Pop stack and jump
					chip8.PC = chip8.stack[#chip8.stack]
					chip8.stack[#chip8.stack] = nil
				else
					print("Attempted to run RCA program: " .. string.format("%03X", address))
				end
			elseif base == 1 then -- Jumps to address
				chip8.PC = address
			elseif base == 2 then -- Push current address to stack and jump
				chip8.stack[#chip8.stack + 1] = chip8.PC
				chip8.PC = address
			elseif base == 3 then -- Skips the next instruction if REG[pX] equals value
				if chip8.REG[pX] == value then
					chip8.PC = chip8.PC + 2
				end
			elseif base == 4 then -- Skips the next instruction if REG[pX] doesn't equal value
				if chip8.REG[pX] ~= value then
					chip8.PC = chip8.PC + 2
				end
			elseif base == 5 and subbase == 0 then -- Skips the next instruction if REG[pX] equals REG[pY]
				if chip8.REG[pX] == chip8.REG[pY] then
					chip8.PC = chip8.PC + 2
				end
			elseif base == 6 then -- Sets REG[pX] to value
				chip8.REG[pX] = value
			elseif base == 7 then -- Adds value to REG[pX]
				chip8.REG[pX] = (chip8.REG[pX] + value) % 256
			elseif base == 8 and (subbase == 14 or (subbase >= 0 and subbase <= 7)) then -- Bit Operations
				if subbase == 0 then      -- Sets REG[pX] to the value of REG[pY]
					chip8.REG[pX] = chip8.REG[pY]
				elseif subbase == 1 then  -- Sets REG[pX] to REG[pX] BitWise OR REG[pY]
					chip8.REG[pX] = bit32.bor(chip8.REG[pX],chip8.REG[pY])
				elseif subbase == 2 then  -- Sets REG[pX] to REG[pX] BitWise AND REG[pY]
					chip8.REG[pX] = bit32.band(chip8.REG[pX],chip8.REG[pY])
				elseif subbase == 3 then  -- Sets REG[pX] to REG[pX] BitWise XOR REG[pY]
					chip8.REG[pX] = bit32.bxor(chip8.REG[pX],chip8.REG[pY])
				elseif subbase == 4 then  -- Adds REG[pY] to REG[pX]. REG[F] is set to 1 when there's a carry, and to 0 when there isn't
					local tmp = chip8.REG[pX] + chip8.REG[pY]
					chip8.REG[15] = tmp > 255 and 1 or 0
					chip8.REG[pX] = tmp % 256
				elseif subbase == 5 then  -- REG[pY] is subtracted from REG[pX]. REG[F] is set to 0 when there's a borrow, and 1 when there isn't
					local tmp = chip8.REG[pX] - chip8.REG[pY]
					chip8.REG[15] = tmp >= 0 and 1 or 0
					chip8.REG[pX] = (tmp + 256) % 256
				elseif subbase == 6 then  -- Shifts REG[pY] right by one and stored in REG[pX]. REG[F] is set to the value of the least significant bit of REG[pY] before the shift
					chip8.REG[15] = chip8.REG[pY] % 2
					chip8.REG[pX] = math.floor(chip8.REG[pY] / 2)
				elseif subbase == 7 then  -- Sets REG[pX] to REG[pY] minus REG[pX]. REG[F] is set to 0 when there's a borrow, and 1 when there isn't
					local tmp = chip8.REG[pY] - chip8.REG[pX]
					chip8.REG[15] = tmp >= 0 and 1 or 0
					chip8.REG[pX] = (tmp + 256) % 256
				elseif subbase == 14 then -- Shifts REG[pY] left by one and stored in REG[pX]. REG[F] is set to the value of the most significant bit of REG[pY] before the shift
					chip8.REG[15] = math.floor(chip8.REG[pY] / 128) % 2
					chip8.REG[pX] = (chip8.REG[pY] * 2) % 256
				end
			elseif base == 9 and subbase == 0 then -- Skips the next instruction if REG[pX] doesn't equal REG[pY]
				if chip8.REG[pX] ~= chip8.REG[pY] then
					chip8.PC = chip8.PC + 2
				end
			elseif base == 10 then -- Sets I to address
				chip8.I = address
			elseif base == 11 then -- Jumps to address plus REG[0]
				chip8.PC = (address + chip8.REG[0]) % 4096
			elseif base == 12 then -- Sets REG[pX] to a random number BitWise AND value
				chip8.REG[pX] = bit32.band(math.random(0,255),value)
			elseif base == 13 then -- Draw Sprite
				chip8.REG[15] = 0
				local x = chip8.REG[pX]
				local y = chip8.REG[pY]
				for i = 0,subbase - 1 do
					local data = chip8.mem[chip8.I + i]
					for j = 0,7 do
						local bit = (math.floor(data/(2^j))%2) == 1
						local lx = (7 - j + x) % 64
						if bit then
							if chip8.display[y+i][lx] == true then
								chip8.REG[15] = 1
							end
							local CC = not chip8.display[y+i][lx]
							chip8.display[y+i][lx] = not chip8.display[y+i][lx]
							if CC then
								chip8.ghost[(y+i)*64 + lx] = nil
								gpu.setColor(0,255,0,255)
								gpu.filledRectangle(lx * gpu_scale, (y+i) * gpu_scale, gpu_scale, gpu_scale)
							else
								chip8.ghost[(y+i)*64 + lx] = 255
							end
						end
					end
				end
			elseif base == 14 and value == 0x9E then -- Skips the next instruction if the key stored in REG[pX] is pressed
				if chip8.keystate[chip8.REG[pX]] then
					chip8.PC = chip8.PC + 2
				end
			elseif base == 14 and value == 0xA1 then -- Skips the next instruction if the key stored in REG[pX] isn't pressed
				if not chip8.keystate[chip8.REG[pX]] then
					chip8.PC = chip8.PC + 2
				end
			elseif base == 15 and value == 0x07 then -- Sets REG[pX] to the value of the delay timer
				chip8.REG[pX] = chip8.delay
			elseif base == 15 and value == 0x0A then -- A key press is awaited, and then stored in REG[pX]
				keywait[1],keywait[2] = true, pX
				break
			elseif base == 15 and value == 0x15 then -- Sets the delay timer to REG[pX]
				chip8.delay = chip8.REG[pX]
			elseif base == 15 and value == 0x18 then -- Sets the sound timer to REG[pX]
				chip8.sound = chip8.REG[pX]
			elseif base == 15 and value == 0x1E then -- Adds REG[pX] to I
				local tmp = chip8.I + chip8.REG[pX]
				chip8.REG[15] = tmp >= 4096 and 1 or 0
				chip8.I = tmp % 4096
			elseif base == 15 and value == 0x29 then -- Sets I to the location of the sprite for the character in REG[pX]
				chip8.I = chip8.REG[pX] * 5
			elseif base == 15 and value == 0x33 then -- Stores the Binary-coded decimal representation of REG[pX] at the address in I
				local BCD = string.format("%03d",chip8.REG[pX])
				chip8.mem[chip8.I  ] = tonumber(BCD:sub(1,1))
				chip8.mem[chip8.I+1] = tonumber(BCD:sub(2,2))
				chip8.mem[chip8.I+2] = tonumber(BCD:sub(3,3))
			elseif base == 15 and value == 0x55 then -- Stores REG[0] to REG[pX] in memory starting at address I
				for i = 0,pX do
					chip8.mem[chip8.I + i] = chip8.REG[i]
				end
				chip8.I = chip8.I + pX + 1
			elseif base == 15 and value == 0x65 then -- Fills REG[0] to REG[pX] with values from memory starting at address I
				for i = 0,pX do
					chip8.REG[i] = chip8.mem[chip8.I + i]
				end
				chip8.I = chip8.I + pX + 1
			else
				print("Unknown opcode: " .. string.format("%04X",opcode))
			end
		end
	end
	-- Decrement ghost pixels
	for k,v in pairs(chip8.ghost) do
		local x = k%64
		local y = math.floor(k/64)
		chip8.ghost[k] = chip8.ghost[k] - chip8.PDS
		gpu.setColor(0,math.max(chip8.ghost[k],0),0)
		gpu.filledRectangle(x * gpu_scale, y * gpu_scale, gpu_scale, gpu_scale)
		if chip8.ghost[k] <= 0 then chip8.ghost[k] = nil end
	end
	-- Decrement timers
	local oldsound = chip8.sound
	if chip8.delay >= 0 then chip8.delay = chip8.delay - 3 end
	if chip8.sound >= 0 then chip8.sound = chip8.sound - 3 end
	-- Play sound if zero
	if oldsound > 0 and chip8.sound <= 0 then
		playSound()
	end
	os.sleep(0.05)
end
gpu.setColor(0,0,0,50)
for i = 1,20 do
	gpu.filledRectangle(0,0,gW,gH)
	os.sleep(0.05)
end
