-- Bios entries for CCEmu
-- A good majority of this is copied from ComputerCraft's bios.lua

local term = require("term")
local text = require("text")
local fs = require("filesystem")
local component = require("component")
local computer = require("computer")
local unicode = require("unicode")

local env = ccemu.env
local config = ccemu.config

local function tablecopy(orig)
	local orig_type = type(orig)
	local copy
	if orig_type == 'table' then
		copy = {}
		for orig_key, orig_value in pairs(orig) do
			copy[orig_key] = orig_value
		end
	else
		copy = orig
	end
	return copy
end

function env.os.version()
	return "CCEmu 1.1"
end
function env.os.pullEventRaw(filter)
	return coroutine.yield(filter)
end
function env.os.pullEvent(filter)
	local e = table.pack(env.os.pullEventRaw(filter))
	if e[1] == "terminate" then
		error("interrupted", 0)
	end
	return table.unpack(e)
end
env.sleep = os.sleep
env.write = function(data)
	local count = 0
	local otw = text.wrap
	function text.wrap(...)
		local a, b, c = otw(...)
		if c then count = count + 1 end
		return a, b, c
	end
	local x = term.getCursor()
	local w = component.gpu.getResolution()
	term.write(data, unicode.len(data) + x - 1 > w)
	text.wrap = otw
	return count
end
env.print = function(...)
	local args = {...}
	for i = 1, #args do
		args[i] = tostring(args[i])
	end
	return env.write(table.concat(args, "\t") .. "\n")
end
env.printError = function(...) io.stderr:write(table.concat({...}, "\t") .. "\n") end
env.read = function(pwchar, hist)
	local line = term.read(tablecopy(hist), nil, nil, pwchar)
	if line == nil then
		return ""
	end
	return line:gsub("\n", "")
end
env.loadfile = function(file, env)
	return loadfile(file, "t", env)
end
env.dofile = dofile
env.os.run = function(newenv, name, ...)
	local args = {...}
	setmetatable(newenv, {__index=env})
	local fn, err = loadfile(name, nil, newenv)
	if fn then
		local ok, err = pcall(function() fn(table.unpack(args)) end)
		if not ok then
			if err and err ~= "" then
				env.printError(err)
			end
			return false
		end
		return true
	end
	if err and err ~= "" then
		env.printError(err)
	end
	return false
end

local tAPIsLoading = {}
env.os.loadAPI = function(path)
	local sName = fs.name(path)
	if tAPIsLoading[sName] == true then
		env.printError("API " .. sName .. " is already being loaded")
		return false
	end
	tAPIsLoading[sName] = true

	local env2
	env2 = {
		getfenv = function() return env2 end
	}
	setmetatable(env2, {__index = env})
	local fn, err = loadfile(path, nil, env2)
	if fn then
		fn()
	else
		env.printError(err)
		tAPIsLoading[sName] = nil
		return false
	end

	local tmpcopy = {}
	for k, v in pairs(env2) do
		tmpcopy[k] = v
	end

	env[sName] = tmpcopy
	tAPIsLoading[sName] = nil
	return true
end
env.os.unloadAPI = function(name)
	if _name ~= "_G" and type(env[name]) == "table" then
		env[name] = nil
	end
end
env.os.sleep = os.sleep
if env.http ~= nil then
	-- TODO: http.get
	-- TODO: http.post
end

-- Install the lua part of the FS api
local empty = {}
env.fs.complete = function(path, location, includeFiles, includeDirs)
    includeFiles = (includeFiles ~= false)
    includeDirs = (includeDirs ~= false)
    local dir = location
    local start = 1
    local slash = string.find(path, "[/\\]", start)
    if slash == 1 then
        dir = ""
        start = 2
    end
    local name
    while not name do
        local slash = string.find(path, "[/\\]", start)
        if slash then
            local part = string.sub(path, start, slash - 1)
            dir = env.fs.combine(dir, part)
            start = slash + 1
        else
            name = string.sub(path, start)
        end
    end

    if env.fs.isDir(dir) then
        local results = {}
        if includeDirs and path == "" then
            table.insert(results, ".")
        end
        if dir ~= "" then
            if path == "" then
                table.insert(results, (includeDirs and "..") or "../")
            elseif path == "." then
                table.insert(results, (includeDirs and ".") or "./")
            end
        end
        local tFiles = env.fs.list(dir)
        for n=1,#tFiles do
            local sFile = tFiles[n]
            if #sFile >= #name and string.sub(sFile, 1, #name) == name then
                local bIdir = env.fs.isDir(env.fs.combine(dir, sFile))
                local result = string.sub(sFile, #name + 1)
                if bIdir then
                    table.insert(results, result .. "/")
                    if includeDirs and #result > 0 then
                        table.insert(results, result)
                    end
                else
                    if includeFiles and #result > 0 then
                        table.insert(results, result)
                    end
                end
            end
        end
        return results
    end
    return empty
end
