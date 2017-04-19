local component=require("component")

local soundcard={}

function soundcard.wrap(proxy, maxms)
	if maxms == nil then maxms = math.huge end
	if type(proxy) == "string" then
		proxy=component.proxy(component.get(proxy))
	end

	local sound={
		process=proxy.process,
		clear=proxy.clear,
		setTotalVolume=proxy.setTotalVolume
	}
	for k, v in pairs(proxy) do
		if sound[k] then
			-- don't replace it
		elseif type(v) == "function" or (type(v) == "table" and getmetatable(v) ~= nil) then
			sound[k]=function(...)
				local ok=v(...)
				if not ok then
					os.sleep(0)
					while not proxy.process() do os.sleep(0) end
					assert(v(...))
				end
				return true
			end
		else
			sound[k]=proxy[k]
		end
	end

	local chcount=proxy.channel_count

	local time=0
	function sound.delay(ms)
		if ms < 1 then return end
		if time+ms >= maxms then
			proxy.delay(maxms-time)
			while not proxy.process() do os.sleep(0) end
			time=time+ms-maxms
			while time >= maxms do
				time=time-maxms
				proxy.delay(maxms)
				while not proxy.process() do os.sleep(0) end
			end
			if time > 0 then
				proxy.delay(time)
			end
			time=0
		else
			proxy.delay(ms)
			time=time+ms
		end
	end

	-- Reset Sound Card to known state.
	sound.clear()
	sound.setTotalVolume(1)
	for i = 1, chcount do
		sound.resetEnvelope(i)
		sound.resetAM(i)
		sound.resetFM(i)
		sound.setVolume(i, 1)
		sound.close(i)
		sound.setWave(i, sound.modes.square)
	end

	while not proxy.process() do os.sleep(0) end

	return sound
end

return soundcard
