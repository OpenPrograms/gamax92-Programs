local component = require("component")
local format = require("format")

local result = {{"Type", "Address"}}
for address, name in component.list() do
	table.insert(result, {name, address})
end

format.tabulate(result)
for _, entry in ipairs(result) do
	io.write(table.concat(entry, " "), "\n")
end