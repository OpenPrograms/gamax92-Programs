local tapefs = require("tapefs")
local fs = require("filesystem")
local component = require("component")
local tapes = 1
for k,v in component.list("tape_drive") do
	if v == "tape_drive" then
		tapes = tapes + 1
		local tapeProxy = tapefs.proxy(k)
		local mntpath
		while true do
			mntpath = "/mnt/tape" .. (tapes > 1 and tapes or "")
			if fs.exists(mntpath) then
				tapes = tapes + 1
			else
				break
			end
		end
		print("Mounting " .. k .. " on " .. mntpath)
		fs.mount(tapeProxy,mntpath)
	end
end
