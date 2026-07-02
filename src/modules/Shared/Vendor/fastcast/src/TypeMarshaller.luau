--!strict

return function(obj: any): string
	-- If not table, return type
	local objType = typeof(obj)
	if not (objType == "table") then
		return objType
	end

	-- If metatable isn't a table, obj just regular table
	local meta = getmetatable(obj)
	if not (typeof(meta) == "table") then
		return objType
	end

	-- If no custom type, just regular table with metatable
	local customType: string? = meta["__type"] -- I want to mandate that this is a string.
	if not customType then
		return objType
	end

	-- Custom type, return
	return customType
end
