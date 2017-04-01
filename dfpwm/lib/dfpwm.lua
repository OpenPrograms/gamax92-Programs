local function ctx_update(state, curbit)
	local target=(curbit and 127 or -128)
	local nlevel=state.level+math.floor((state.response*(target-state.level)+state.RESP_PREC_HALF)/state.RESP_PREC_POWER)
	if nlevel == state.level and state.level ~= target then
		nlevel=nlevel+(curbit and 1 or -1)
	end

	local rtarget, rdelta
	if curbit == state.lastbit then
		rtarget=state.RESP_PREC_MAX
		rdelta=state.RESP_INC
	else
		rtarget=0
		rdelta=state.RESP_DEC
	end

	local nresponse=state.response+(state.new and 0 or math.floor((rdelta*(rtarget-state.response))/256))
	if nresponse == state.response and state.response ~= rtarget then
		nresponse=nresponse+((curbit == state.lastbit) and 1 or -1)
	end

	if state.RESP_PREC > 8 then
		if nresponse < state.RESP_PREC_8 then
			nresponse=state.RESP_PREC_8
		end
	end

	state.response=nresponse
	state.lastbit=curbit
	state.level=nlevel
end

local function decompress(state, src)
	local dest={}
	for i=1, #src do
		local d=src[i]
		for j=0, 7 do
			-- apply context
			local curbit=(bit32.band(d, bit32.lshift(1, j)) ~= 0)
			local lastbit=state.lastbit
			ctx_update(state, curbit)
			
			-- apply noise shaping
			local blevel = bit32.band((curbit == lastbit) and state.level or math.floor((state.flastlevel+state.level+1)/2), 0xFF)
			if blevel >= 128 then
				blevel=blevel-256
			end
			state.flastlevel=state.level

			-- apply low-pass filter
			state.lpflevel=state.lpflevel+math.floor((state.LPF_STRENGTH*(blevel-state.lpflevel)+0x80)/256)
			dest[#dest+1]=bit32.band(state.lpflevel, 0xFF)
		end
	end
	return dest
end

local function compress(state, src)
	local dest={}
	for i=1, #src, 8 do
		local d=0
		for j=0, 7 do
			local inlevel=(src[i+j] or 0)
			if inlevel >= 128 then
				inlevel=inlevel-256
			end
			local curbit=(inlevel > state.level or (inlevel == state.level and state.level == 127))
			d=bit32.bor(d/2, curbit and 128 or 0)
			ctx_update(state, curbit)
		end
		dest[#dest+1]=d
	end
	return dest
end

local dfpwm={}

function dfpwm.new(newdfpwm)
	local state={
		new=newdfpwm,
		response=0,
		level=0,
		lastbit=false,
		flastlevel=0,
		lpflevel=0,
		decompress=decompress,
		compress=compress
	}
	if newdfpwm then
		state.RESP_INC=1
		state.RESP_DEC=1
		state.RESP_PREC=10
		state.LPF_STRENGTH=140
	else
		state.RESP_INC=7
		state.RESP_DEC=20
		state.RESP_PREC=8
		state.LPF_STRENGTH=100
	end
	-- precompute and cache some stuff
	state.RESP_PREC_HALF=bit32.lshift(1, state.RESP_PREC-1)
	state.RESP_PREC_POWER=2^state.RESP_PREC
	state.RESP_PREC_MAX=bit32.lshift(1, state.RESP_PREC)-1
	state.RESP_PREC_8=bit32.lshift(2, state.RESP_PREC-8)
	return state
end

return dfpwm
