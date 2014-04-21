local arg = { ... }
if #arg < 1 then
	print("Usage: install mountpoint")
	return
end
local shell = require("shell")
local instpath = shell.resolve(arg[1])
local fs = require("filesystem")
if not fs.exists(instpath) then
	error("No such directory",2)
end
if not fs.isDirectory(instpath) then
	error("Cannot install to a file",2)
end
local found = false
local proxy
for k,v in fs.mounts() do
	if v == instpath .. "/" then
		proxy = k
		found = true
	end
end
if not found then
	error("Installation point must be a mount path",2)
end
local mountTable = {}
for k,v in fs.mounts() do
	mountTable[v] = true
end
print("Locating rom ...")
local romproxy
for k,v in fs.mounts() do
	if v == "/" then
		romproxy = k
		break
	end
end
if romproxy == nil then
	error("Could not find /",2)
end
print("Mounting rom to /mnt/installtmp")
fs.mount(romproxy,"/mnt/installtmp")

print("Creating directory structure ...")
local copylist
function copylist(path, topath)
	for entry in fs.list(path) do
		local srcpath = path .. entry
		local folderpath = topath .. entry
		if fs.isDirectory(srcpath) and not mountTable[srcpath] then
			if fs.exists(folderpath) and not fs.isDirectory(folderpath) then
				print("WARNING: deleting " .. folderpath)
				local stat = fs.remove(folderpath)
				if stat ~= true then
					error("Could not remove " .. folderpath,2)
				end
			end
			if not fs.isDirectory(folderpath) then
				print(folderpath)
				local stat = fs.makeDirectory(folderpath)
				if stat ~= true then
					error("Could not create " .. folderpath,2)
				end
			end
			copylist(srcpath, folderpath)
		end
	end
end
copylist("/mnt/installtmp/", instpath .. "/")
print("Copying files ...")
local copybatch
function copybatch(path, topath)
	for entry in fs.list(path) do
		local srcpath = path .. entry
		local filepath = topath .. entry
		if fs.isDirectory(srcpath) and not mountTable[srcpath] then
			copybatch(srcpath, filepath)
		elseif not fs.isDirectory(srcpath) then
			if fs.exists(filepath) then
				print("WARNING: deleting " .. filepath)
				local stat = fs.remove(filepath)
				if stat ~= true then
					error("Could not remove " .. filepath,2)
				end
			end
			print(filepath)
			local stat = fs.copy(srcpath, filepath)
			if stat ~= true then
				error("Could not copy " .. srcpath,2)
			end
		end
	end
end
copybatch("/mnt/installtmp/", instpath .. "/")
print("Writing boot script ...")
local file = fs.open(instpath .. "/autorun.lua","wb")
if file == nil then
	error("Failed to open boot script",2)
end
file:write([[
local a = require("filesystem")
local b = require("component")
print("Remounting ...")
a.umount("/")
a.mount(b.proxy("]] .. proxy.address .. [["),"/")
]])
file:close()
print("Unmounting /mnt/installtmp ...")
fs.umount("/mnt/installtmp")
print("Done!")
