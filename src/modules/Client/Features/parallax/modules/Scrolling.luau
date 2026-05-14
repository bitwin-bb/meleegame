--!strict

local Scrolling = {}

local BASE_TEXTURE_OFFSET_STUDS_U = 0.3
local BASE_TEXTURE_OFFSET_STUDS_V = 0.3
local PARALLAX_TEXTURE_MOTION_SCALE = 0.65

function Scrolling.WrapOffsetStuds(offsetStudsRaw: number, repeatWidthRaw: number): number
	local repeatWidth = math.max(repeatWidthRaw, 0.001)
	local wrapped = offsetStudsRaw % repeatWidth
	if wrapped < 0 then
		wrapped += repeatWidth
	end
	return wrapped
end

function Scrolling.ComputeHorizontalOffsetStuds(
	cameraZ: number,
	depth: number,
	scrollSpeed: number,
	repeatWidth: number,
	now: number
): number
	return Scrolling.WrapOffsetStuds(
		BASE_TEXTURE_OFFSET_STUDS_U
			+ cameraZ * depth * PARALLAX_TEXTURE_MOTION_SCALE
			- now * scrollSpeed * PARALLAX_TEXTURE_MOTION_SCALE,
		repeatWidth
	)
end

function Scrolling.ComputeVerticalOffsetStuds(repeatHeight: number): number
	return Scrolling.WrapOffsetStuds(BASE_TEXTURE_OFFSET_STUDS_V, repeatHeight)
end

function Scrolling.ComputeOffsetPixels(offsetStudsRaw: number, repeatStudsRaw: number, tilePixelsRaw: number): number
	local repeatStuds = math.max(repeatStudsRaw, 0.001)
	local tilePixels = math.max(tilePixelsRaw, 1)
	return (Scrolling.WrapOffsetStuds(offsetStudsRaw, repeatStuds) / repeatStuds) * tilePixels
end

Scrolling.wrapOffsetStuds = Scrolling.WrapOffsetStuds
Scrolling.computeHorizontalOffsetStuds = Scrolling.ComputeHorizontalOffsetStuds
Scrolling.computeVerticalOffsetStuds = Scrolling.ComputeVerticalOffsetStuds
Scrolling.computeOffsetPixels = Scrolling.ComputeOffsetPixels

return Scrolling
