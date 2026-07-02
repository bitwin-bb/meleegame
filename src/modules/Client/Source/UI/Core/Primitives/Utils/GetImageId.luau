local require = require(script.Parent.loader).load(script)

local MISSING_ASSET_ERROR = "no asset found!"

local function normalizeImageId(valueRaw: any): string?
	if typeof(valueRaw) == "number" then
		if valueRaw ~= valueRaw or valueRaw <= 0 then
			return nil
		end
		return "rbxassetid://" .. tostring(math.floor(valueRaw))
	end

	if typeof(valueRaw) ~= "string" then
		return nil
	end

	local value = string.gsub(valueRaw, "%s", "")
	if value == "" then
		return nil
	end

	if string.find(value, "rbxassetid://", 1, true) == 1 then
		local digits = string.match(value, "%d+")
		if digits == nil then
			return nil
		end
		return "rbxassetid://" .. digits
	end

	if string.match(value, "^%d+$") ~= nil then
		return "rbxassetid://" .. value
	end

	return value
end

local function GetImageId(valueRaw: any, _fallbackRaw: any?): string
	local imageId = normalizeImageId(valueRaw)
	if imageId == nil then
		error(MISSING_ASSET_ERROR, 0)
	end
	return imageId
end

return GetImageId
