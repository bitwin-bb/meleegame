--!strict

local CmdrUtils = {}

CmdrUtils.CMDR_ENABLED_ATTRIBUTE = "CmdrEnabled"
CmdrUtils.FLY_ENABLED_ATTRIBUTE = "CmdrFlyEnabled"
CmdrUtils.FLY_SPEED_ATTRIBUTE = "CmdrFlySpeed"
CmdrUtils.GODMODE_ENABLED_ATTRIBUTE = "CmdrGodmodeEnabled"

CmdrUtils.DEFAULT_FLY_SPEED = 64
CmdrUtils.MIN_FLY_SPEED = 8
CmdrUtils.MAX_FLY_SPEED = 256

function CmdrUtils.sanitizeFlySpeed(speedRaw: any, fallbackRaw: any): number
	local fallback = if typeof(fallbackRaw) == "number" and fallbackRaw == fallbackRaw
		then fallbackRaw
		else CmdrUtils.DEFAULT_FLY_SPEED

	local speed = if typeof(speedRaw) == "number" and speedRaw == speedRaw then speedRaw else fallback
	return math.clamp(math.floor(speed + 0.5), CmdrUtils.MIN_FLY_SPEED, CmdrUtils.MAX_FLY_SPEED)
end

function CmdrUtils.isValidCmdrGui(guiRaw: any): boolean
	if typeof(guiRaw) ~= "Instance" or not guiRaw:IsA("ScreenGui") then
		return false
	end

	local frame = guiRaw:FindFirstChild("Frame")
	local autocomplete = guiRaw:FindFirstChild("Autocomplete")
	if frame == nil or not frame:IsA("ScrollingFrame") then
		return false
	end
	if autocomplete == nil or not autocomplete:IsA("ScrollingFrame") then
		return false
	end

	local line = frame:FindFirstChild("Line")
	local entry = frame:FindFirstChild("Entry")
	if line == nil or not line:IsA("TextBox") then
		return false
	end
	if entry == nil or not entry:IsA("Frame") then
		return false
	end

	local textBox = entry:FindFirstChild("TextBox")
	local textLabel = entry:FindFirstChild("TextLabel")
	if textBox == nil or not textBox:IsA("TextBox") then
		return false
	end
	if textLabel == nil or not textLabel:IsA("TextLabel") then
		return false
	end

	return true
end

function CmdrUtils.getCmdrGuiInstances(parentRaw: any): { Instance }
	local matches = {}
	if typeof(parentRaw) ~= "Instance" then
		return matches
	end

	for _, child in parentRaw:GetChildren() do
		if child.Name == "Cmdr" then
			matches[#matches + 1] = child
		end
	end

	return matches
end

function CmdrUtils.keepSingleValidCmdrGui(parentRaw: any): ScreenGui?
	local keptGui = nil :: ScreenGui?

	for _, gui in CmdrUtils.getCmdrGuiInstances(parentRaw) do
		if keptGui == nil and CmdrUtils.isValidCmdrGui(gui) then
			keptGui = gui :: ScreenGui
		else
			gui:Destroy()
		end
	end

	return keptGui
end

return CmdrUtils
