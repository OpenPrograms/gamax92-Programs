local component = require("component")

local proxylist = {}
local typelist = {}

local oproxy = component.proxy
function component.proxy(address)
	checkArg(1,address,"string")
	if proxylist[address] ~= nil then
		return proxylist[address]
	end
	return oproxy(address)
end

local olist = component.list
function component.list(filter)
	if type(filter) ~= "nil" and type(filter) ~= "string" then
		checkArg(1,filter,"string or nil")
	end
	local data = {}
	for k,v in olist(filter) do
		data[#data + 1] = k
		data[#data + 1] = v
	end
	for k,v in pairs(proxylist) do
		if filter == nil or typelist[k]:find(filter, nil, true) then
			data[#data + 1] = k
			data[#data + 1] = typelist[k]
		end
	end
	local place = 1
	return function()
		local addr,type = data[place], data[place + 1]
		place = place + 2
		return addr,type
	end
end

local otype = component.type
function component.type(address)
	checkArg(1,address,"string")
	if typelist[address] ~= nil then
		return typelist[address]
	end
	return otype(address)
end

local odoc = component.doc
function component.doc(address, method)
	checkArg(1,address,"string")
	checkArg(2,method,"string")
	if proxylist[address] ~= nil then
		if proxylist[address][method] == nil then
			error("no such method",2)
		end
		return nil -- No doc support
	end
	return odoc(address, method)
end

local oinvoke = component.invoke
function component.invoke(address, method, ...)
	checkArg(1,address,"string")
	checkArg(2,method,"string")
	if proxylist[address] ~= nil then
		if proxylist[address][method] == nil then
			error("no such method",2)
		end
		return proxylist[address][method](...)
	end
	return oinvoke(address, method, ...)
end

local vcomponent = {}

function vcomponent.register(address, type, proxy)
	checkArg(1,address,"string")
	checkArg(2,proxy,"table")
	if proxylist[address] ~= nil then
		return nil, "component already at address"
	elseif component.type(address) ~= nil then
		return nil, "cannot register over real component"
	end
	proxy.address = address
	proxy.type = type
	proxylist[address] = proxy
	typelist[address] = type
	return true
end

function vcomponent.unregister(address)
	checkArg(1,address,"string")
	if proxylist[address] == nil then
		if component.type(address) ~= nil then
			return nil, "cannot unregister real component"
		else
			return nil, "no component at address"
		end
	end
	proxylist[address] = nil
	typelist[address] = nil
	return true
end

return vcomponent
