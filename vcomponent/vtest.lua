local vcomp = require("vcomponent")

local proxy = {
	test = function(something) return type(something) end
}
local docs = {
	test = "function(value:something):string -- I do stuff."
}
vcomp.register("LALWZADDR","testcomp",proxy,docs)
