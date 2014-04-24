local computer = require("computer")
local shell = require("shell")
local format = require("format")

local _, options = shell.parse(...)

local function printUsage()
	io.write([[
Usage: free [options]

Options:
 -b, --bytes  show output in  bytes
 -k, --kilo   show output in kilobytes
 -m, --mega   show output in megabytes
 -g, --giga   show output in gigabytes
     --tera   show output in terabytes
 -h, --human  show human readable output
     --si     use powers of 1000 not 1024
 -t, --total  show total for all usage
     --help   display this help text
	]])
end

local size = "k"
local si = 1024
local total = false

for k,v in pairs(options) do
	if k == "b" or k == "bytes" or k == "k" or k == "kilo" or k == "m" or k == "mega" or k == "g" or k == "giga" or k == "tera" or  k == "h" or k == "human" then
		size = k:sub(1,1)
	elseif k == "si" then
		si = 1000
	elseif k == "t" or k == "total" then
		total = true
	elseif k == "help" then
		printUsage()
		return
	else
		io.write("free: invalid option -- '" .. k .. "'\n")
		printUsage()
		return
	end
end

local function formatSize(value)
	if size == "b" then
		return value
	elseif size == "k" then
		return math.floor(value / si)
	elseif size == "m" then
		return math.floor(value / si / si)
	elseif size == "g" then
		return math.floor(value / si / si / si)
	elseif size == "t" then
		return math.floor(value / si / si / si / si)
	elseif size == "h" then
		local sizeLet = {"B","K","M","G","T"}
		local i = 1
		while i <= #sizeLet do
			if value < si then
				break
			end
			i = i + 1
			value = value / si
		end
		return math.floor(value * 10) / 10 .. sizeLet[i]
	end
end

local result = {{"","total","used","free"}}
local compFree = computer.freeMemory()
table.insert(result, {"Mem:",computer.totalMemory(),computer.totalMemory() - compFree,compFree})
if total then
	local totalEntry = {"Total",0,0,0}
	for j = 2, #result do
		for i = 2, 4 do
			totalEntry[i] = totalEntry[i] + result[j][i]
		end
	end
	table.insert(result, totalEntry)
end
for j = 2, #result do
	for i = 2, 4 do
		result[j][i] = formatSize(result[j][i])
	end
end
format.tabulate(result,{0,1,1,1})
for _, entry in ipairs(result) do
	io.write(table.concat(entry, "  "), "\n")
end