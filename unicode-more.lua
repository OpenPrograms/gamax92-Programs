local unicode = require("unicode")

local function uz(a)
	local b={a:byte(1,-1)}
	if #b==1 then return b[1] end
	local c=b[1]%(8*(2^(4-#b)))*(2^(6*#b-6))
	for i=2,#b do
		c=c+(b[i]%64)*2^(6*(#b-i))
	end
	return c
end

function unicode.find(str, pattern, init, plain)
    checkArg(1, str, "string")
    checkArg(2, pattern, "string")
    checkArg(3, init, "number", "nil")
	if init then
		if init < 0 then
			init = -#unicode.sub(str,init)
		elseif init > 0 then
			init = #unicode.sub(str,1,init-1)+1
		end
	end
	a, b = string.find(str, pattern, init, plain)
	if a then
		local ap,bp = str:sub(1,a-1), str:sub(a,b)
		a = unicode.len(ap)+1
		b = a + unicode.len(bp)-1
		return a,b
	else
		return a
	end
end

function unicode.byte(str, i, j)
    checkArg(1, str, "string")
	if i == nil then i = 1 end
	if j == nil then j = i end
    checkArg(2, i, "number")
    checkArg(3, j, "number")
	local part = unicode.sub(str,i,j)
	local results = {}
	for char in part:gmatch("[%z\1-\127\194-\244][\128-\191]*") do
		results[#results+1] = uz(char)
	end
	return table.unpack(results)
end

