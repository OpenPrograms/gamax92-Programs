local fs = require("filesystem")
local shell = require("shell")
local inFN, outFN

local args = {...}
if #args ~= 2 then
	print("Usage: decompress <input file> <output file>")
	return
end

inFN = shell.resolve(args[1])
outFN = shell.resolve(args[2])

if not fs.exists(inFN) then
	error("No such file", 0)
end

local f = io.open(inFN, "rb")
local inText = f:read("*a")
f:close()

local inPos = 1

local huffmanCompression = true

if huffmanCompression then
	-- convert characters to bits
	local inBits = {}
	for k = 1, #inText do
		local byte = inText:sub(k, k):byte() - 32
		for i = 0, 5 do
			local testBit = 2 ^ i
			inBits[#inBits + 1] = (byte % (2 * testBit)) >= testBit
		end
	end
	
	-- remove padding
	local padbit = inBits[#inBits]
	while inBits[#inBits] == padbit do
		inBits[#inBits] = nil
	end
	
	local pos = 1
	local function readBit()
		if pos > #inBits then error("end of stream", 2) end
		pos = pos + 1
		return inBits[pos - 1]
	end
	
	-- read huffman tree
	local function readTree()
		if readBit() then
			local byte = 0
			for i = 0, 7 do
				if readBit() then
					byte = byte + 2 ^ i
				end
			end
			return string.char(byte)
		else
			local subtree_0 = readTree()
			local subtree_1 = readTree()
			return {[false]=subtree_0, [true]=subtree_1}
		end
	end
	local tree = readTree()
	
	inText = ""
	
	local treePos = tree
	while pos <= #inBits do
		local bit = readBit()
		treePos = treePos[bit]
		if type(treePos) ~= "table" then
			inText = inText .. treePos
			treePos = tree
		end
	end
	if treePos ~= tree then
		error("unexpected end of stream")
	end
end

local function readTo(delim)
	local start = inPos
	local nextCaret = inText:find(delim, inPos, true)
	if not nextCaret then
		inPos = #inText + 1
		return inText:sub(start)
	end
	inPos = nextCaret + 1
	return inText:sub(start, nextCaret - 1)
end

-- returns iterator
local function splitString(str, delim)
	local pos = 1
	return function()
		if pos > #str then return end
		local start = pos
		local nextDelim = str:find(delim, pos, true)
		if not nextDelim then
			pos = #str + 1
			return str:sub(start)
		end
		pos = nextDelim + 1
		return str:sub(start, nextDelim - 1)
	end
end

local nameTable = {}

local idents = "abcdefghijklmnopqrstvuwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_"
local nextCompressed
do
	local validchars = idents:gsub("_","")
	
	local function encode(n)
		local s = ""
		while n > 0 do
			local digit = (n % #validchars) + 1
			s = s .. validchars:sub(digit, digit)
			n = math.floor(n / #validchars)
		end
		return s
	end
	
	local next = 0
	function nextCompressed()
		next = next + 1
		return encode(next)
	end
end

for k = 1, tonumber(readTo("^")) do
	local key = nextCompressed()
	local value = readTo("^")
	nameTable[key] = value
end

local out = ""

local function onFinishSegment(isIdent, segment)
	if isIdent then
		if segment:sub(1, 1) == "_" then
			out = out .. segment:sub(2)
		else
			out = out .. tostring(nameTable[segment])
		end
	else
		out = out .. segment
	end
end

local parsed = {}
local idents = "abcdefghijklmnopqrstvuwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_"
local lastIdent = nil

for k = inPos, #inText do
	local ch = inText:sub(k, k)
	local isIdent = idents:find(ch, 1, true) ~= nil
	if isIdent ~= lastIdent then
		if #parsed > 0 then
			onFinishSegment(lastIdent, parsed[#parsed])
		end
		parsed[#parsed+1] = ""
	end
	lastIdent = isIdent
	parsed[#parsed] = parsed[#parsed]..ch
end
if #parsed > 0 then
	onFinishSegment(isIdent, parsed[#parsed])
end

-- convert indentation back
local out2 = ""
local lastIndent = ""
for line in splitString(out, "\n") do
	while line:sub(1,2) == "&+" do
		lastIndent = lastIndent .. "\t"
		line = line:sub(3)
	end
	while line:sub(1,2) == "&-" do
		lastIndent = lastIndent:sub(1, #lastIndent - 1)
		line = line:sub(3)
	end
	if line:sub(1,2) == "&&" then
		line = line:sub(2)
	end
	
	out2 = out2 .. lastIndent .. line .. "\n"
end

local f = io.open(outFN, "wb")
f:write(out2)
f:close()