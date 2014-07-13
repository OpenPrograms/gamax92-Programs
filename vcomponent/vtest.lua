local vcomp = require("vcomponent")

local proxy = {
	test = function(something) return type(something) end
}

vcomp.register("LALWZADDR","testcomp",proxy)
