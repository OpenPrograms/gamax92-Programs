local component = require("component")
local shell = require("shell")
local format = require("format")

local args = shell.parse(...)
local test = {}
for _,arg in ipairs(args) do
	test[arg] = true
end

local result = {{"Type", "Address"}}
for address, name in component.list() do
	if #args == 0 or test[name] then
		table.insert(result, {name, address})
	end
end

format.tabulate(result)
for _, entry in ipairs(result) do
	io.write(table.concat(entry, " "), "\n")
end