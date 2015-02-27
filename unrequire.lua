local unload_shell = package.loaded["shell"] == nil
local shell = require("shell")
if unload_shell then
	package.loaded["shell"] = nil
end

local blacklist = {
	["filesystem"] = true,
	["shell"] = true,
	["package"] = true,
	["process"] = true,
}

local function errprint(msg)
	io.stderr:write(msg .. "\n")
end

local args, options = shell.parse(...)
if #args == 0 then
	print
[[Usage: unrequire list
       unrequire unload <name>
       unrequire unload-all
Options:
    -v --verbose  List unloaded libraries
    --unsafe      Unload blacklisted libraries]]
	return
end
if args[1] == "list" then
	local list = {}
	for k,v in pairs(package.loaded) do
		list[#list+1] = k
	end
	table.sort(list)
	print(table.concat(list,"\n"))
elseif args[1] == "unload" then
	if #args < 2 then
		errprint("unrequire: missing name")
	elseif package.loaded[args[2]] == nil then
		errprint("unrequire: '" .. args[2] .. "' not loaded")
	elseif blacklist[args[2]] and not options.unsafe then
		errprint("unrequire: refusing to unload '" .. args[2] .. "'\nUse --unsafe to override this")
	else
		package.loaded[args[2]] = nil
		if options.v or options.verbose then
			print("unloaded '" .. args[2] .. "'")
		end
	end
elseif args[1] == "unload-all" then
	local list = {}
	for k,v in pairs(package.loaded) do
		if options.unsafe or not blacklist[k] then
			list[#list+1] = k
		end
	end
	for i = 1,#list do
		package.loaded[list[i]] = nil
		if options.v or options.verbose then
			print("unloaded '" .. list[i] .. "'")
		end
	end
else
	errprint("Unknown command '" .. args[1] .. "'")
end
