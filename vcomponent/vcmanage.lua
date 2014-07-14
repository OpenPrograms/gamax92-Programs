local args = { ... }
if #args < 1 or #args > 2 then
	print("Usage: vcmanage list [filter]")
	print("       vcmanage delete <address>")
	print("       vcmanage deleteall")
	return
end

local vcomp = require("vcomponent")
local component = require("component")

if args[1] == "list" then
	local vclist = vcomp.list()
	for k = 1,#vclist do
		if args[2] == nil or vclist[k][2]:find(args[2],nil,true) then
			print(vclist[k][2], vclist[k][1])
		end
	end
elseif args[1] == "delete" or args[1] == "remove" then
	if args[2] == nil then
		error("Must specify address for deletion", 0)
	end
	local vclist = vcomp.list()
	realaddr = vcomp.resolve(args[2])
	if realaddr == nil then
		error("No such virtual component", 0)
	end
	for k = 1,#vclist do
		if vclist[k][1] == realaddr then
			local stat, problem = vcomp.unregister(vclist[k][1])
			if stat ~= true then
				error("Unregister: " .. problem,0)
			end
			if realaddr ~= args[2] then
				print("Component removed at " .. realaddr)
			else
				print("Component removed")
			end
			return
		end
	end
	print("No component removed")
elseif args[1] == "deleteall" or args[1] == "removeall" then
	local remv = 0
	local vclist = vcomp.list()
	for k = 1,#vclist do
		local stat, problem = vcomp.unregister(vclist[k][1])
		remv = remv + 1
	end
	print("Removed " .. remv .. " component" .. (remv ~= 1 and "s" or ""))
else
	error("Unknown command, " .. args[1], 0)
end
