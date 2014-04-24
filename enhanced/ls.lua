local component = require("component")
local fs = require("filesystem")
local shell = require("shell")
local format = require("format")

local dirs, options = shell.parse(...)
if #dirs == 0 then
	table.insert(dirs, ".")
end

io.output():setvbuf("line")
for i = 1, #dirs do
	local path = shell.resolve(dirs[i])
	if #dirs > 1 then
		if i > 1 then
			io.write("\n")
		end
		io.write(path, ":\n")
	end
	local fslist, reason = fs.list(path)
	if not fslist then
		io.write(reason .. "\n")
	else
		local function setColor(c)
			if component.gpu.getForeground() ~= c then
				io.stdout:flush()
				component.gpu.setForeground(c)
			end
		end
		local list = {}
		for f in fslist do
			if options.a or f:sub(1, 1) ~= "." then
				table.insert(list, f)
			end
		end
		table.sort(list)
		local toOutput = {}
		local function getFileColor(file)
			if fs.isDirectory(fs.concat(path, file)) then
				return 0x66CCFF
			elseif fs.isLink(fs.concat(path, file)) then
				return 0xFFAA00
			elseif file:sub(-4) == ".lua" then
				return 0x00FF00
			else
				return 0xFFFFFF
			end
		end
		if options.l then
			local objColor = {}
			local totalSize = 0
			for _, f in ipairs(list) do
				local type
				if fs.isDirectory(fs.concat(path, f)) then
					type = "d"
				elseif fs.isLink(fs.concat(path, f)) then
					type = "l"
				else
					type = "-"
				end
				local flags = "rw" .. (f:sub(-4) == ".lua" and "x" or "-")
				local modificationTime = fs.lastModified(fs.concat(path, f)) / 1000
				local testdate = os.date("*t", modificationTime)
				local now = os.date("*t")
				local date
				if testdate.year ~= now.year then
					date = os.date("%b %d  %Y", modificationTime)
				else
					date = os.date("%b %d %H:%M", modificationTime)
				end
				local filesize = fs.size(fs.concat(path, f))
				totalSize = totalSize + filesize
				table.insert(toOutput, {type .. flags .. flags .. flags, filesize, date, f})
				table.insert(objColor, getFileColor(f))
			end
			format.tabulate(toOutput, {0,1,0,0})
			io.write("total " .. math.ceil(totalSize / 1024) .. "\n")
			for j, entry in ipairs(toOutput) do
				for i = 1, 4 do
					if i == 4 then
						setColor(objColor[j])
					end
					io.write(entry[i])
					if i == 4 then
						setColor(0xFFFFFF)
					else
						io.write(" ")
					end
				end
				io.write("\n")
			end
		else
			for _, f in ipairs(list) do
				table.insert(toOutput, getFileColor(f))
				table.insert(toOutput, f)
			end
			format.tabulateWidth(toOutput, 2)
		end
		setColor(0xFFFFFF)
		if not options.l then
			io.write("\n")
		end
	end
end
io.output():setvbuf("no")