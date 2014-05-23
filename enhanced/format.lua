local format = {}
local component = require("component")
local term = require("term")

function format.padStringLeft(str, size)
	return str .. string.rep(" ", size - #str)
end

function format.padStringRight(str, size)
	return string.rep(" ", size - #str) .. str
end

function format.tabulate(input, justify)
	if #input == 0 then
		return
	end
	justify = justify or {}
	local tabsize = {}
	for i = 1, #input[1] do
		tabsize[i] = 0
	end
	for _, entry in ipairs(input) do
		for i, value in ipairs(entry) do
			if tostring(value):len() > tabsize[i] then
				tabsize[i] = tostring(value):len()
			end
		end
	end
	for _, entry in ipairs(input) do
		for i, value in ipairs(entry) do
			if (justify[i] or 0) == 0 then
				entry[i] = format.padStringLeft(tostring(entry[i]), tabsize[i])
			else
				entry[i] = format.padStringRight(tostring(entry[i]), tabsize[i])
			end
		end
	end
end

function format.tabulateList(input, justify)
	justify = justify or 0
	local tabsize = 0
	for i, value in ipairs(input) do
		if tostring(value):len() > tabsize then
			tabsize = tostring(value):len()
		end
	end
	for i, value in ipairs(input) do
		if justify == 0 then
			input[i] = format.padStringLeft(tostring(input[i]), tabsize)
		else
			input[i] = format.padStringRight(tostring(input[i]), tabsize)
		end
	end
end

function format.tabulateWidth(tAll, seperator)
	local w, h = component.gpu.getResolution()
	local nMaxLen = seperator
	for n, sItem in pairs(tAll) do
		if type(sItem) ~= "number" then
			nMaxLen = math.max(string.len(sItem) + seperator, nMaxLen)
		end
	end
	local nCols = math.floor(w/nMaxLen)
	local nCol = 1
	for n, s in ipairs(tAll) do
		if nCol > nCols then
			nCol = 1
			io.write("\n")
		end
		if type(s) == "number" then
			component.gpu.setForeground(s)
		else
			local cx, cy = term.getCursor()
			cx = 1 + ((nCol - 1) * nMaxLen)
			term.setCursor(cx, cy)
			term.write(s)
			nCol = nCol + 1
		end
	end
end

-------------------------------------------------------------------------------

return format
