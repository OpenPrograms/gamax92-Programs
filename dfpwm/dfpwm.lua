local shell=require("shell")

local args, options=shell.parse(...)
if options.h or options.help then
	print([=[Usage: dfpwm [infile [outfile]]

Options:
	-h --help   This message
	-d --decode Decode from dfpwm
	-e --encode Encode to dfpwm (default)
	-o --old    Use old DFPWM codec
	-n --new    Use new DFPWM1a codec (default)
	--bsize=n   Buffer size
	]=])
	return
end

local function errprint(msg)
	io.stderr:write(msg.."\n")
	io.stderr:flush()
end

local encode=true
local new=true
local bsize=8192

if options.d or options.decode then
	encode=false
end
if options.o or options.old then
	new=false
end
if options.bsize then
	bsize=tonumber(options.bsize, 10)
	if not bsize then
		errprint("Error: '"..tostring(options.bsize).."' is not a valid number")
		return
	end
end

local dfpwm=require("dfpwm")
local codec=dfpwm.new(new)

local file, err
if #args >= 1 then
	file, err=io.open(args[1], "rb")
	if not file then
		errprint(err)
		return
	end
else
	file=io.stdin
end

local outfile
if #args >= 2 then
	outfile, err=io.open(args[2], "wb")
	if not outfile then
		file:close()
		errprint(err)
		return
	end
else
	outfile=io.stdout
end

while true do
	local data=file:read(bsize)
	if not data then break end
	data=table.pack(data:byte(1,-1))

	local odata
	if encode then
		for i=1, #data do
			data[i]=bit32.bxor(data[i], 0x80)
		end
		odata=codec:compress(data)
	else
		odata=codec:decompress(data)
		for i=1, #odata do
			odata[i]=bit32.bxor(odata[i], 0x80)
		end
	end

	for i=1, #odata do
		odata[i]=string.char(odata[i])
	end
	outfile:write(table.concat(odata))
	outfile:flush()

	os.sleep(0)
end

if #args >= 1 then
	file:close()
	if #args >= 2 then
		outfile:close()
	end
end
