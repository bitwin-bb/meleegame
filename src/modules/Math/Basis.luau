--!strict
-- Orthonormal basis construction and local/world conversion helpers.

local Vec = require(script.Parent.Vec)

local Basis = {}

export type Basis = {
	origin: Vector3,
	xAxis: Vector3,
	yAxis: Vector3,
	zAxis: Vector3,
}

local X_AXIS = Vector3.new(1, 0, 0)
local Y_AXIS = Vector3.new(0, 1, 0)
local Z_AXIS = Vector3.new(0, 0, 1)

local function perpendicular(axis: Vector3): Vector3
	local reference = if math.abs(axis.Y) < 0.999 then Y_AXIS else X_AXIS
	return Vec.unit(reference:Cross(axis), X_AXIS)
end

local function orthonormalize(xAxis: Vector3, yAxis: Vector3, zAxis: Vector3?): (Vector3, Vector3, Vector3)
	local x = Vec.unit(xAxis, X_AXIS)

	local ySource = yAxis - x * x:Dot(yAxis)
	if Vec.isNearlyZero(ySource) then
		ySource = perpendicular(x):Cross(x)
	end
	local y = Vec.unit(ySource, Y_AXIS)

	local zSource = if zAxis ~= nil then zAxis else x:Cross(y)
	zSource = zSource - x * x:Dot(zSource) - y * y:Dot(zSource)
	if Vec.isNearlyZero(zSource) then
		zSource = x:Cross(y)
	end
	local z = Vec.unit(zSource, Z_AXIS)

	if x:Cross(y):Dot(z) < 0 then
		z = -z
	end

	y = Vec.unit(z:Cross(x), Y_AXIS)
	x = Vec.unit(y:Cross(z), X_AXIS)
	return x, y, z
end

function Basis.new(origin: Vector3, xAxis: Vector3, yAxis: Vector3, zAxis: Vector3?): Basis
	local x, y, z = orthonormalize(xAxis, yAxis, zAxis)
	return {
		origin = origin,
		xAxis = x,
		yAxis = y,
		zAxis = z,
	}
end

function Basis.fromLook(origin: Vector3, forward: Vector3, up: Vector3?): Basis
	local z = Vec.unit(forward, Z_AXIS)
	local upHint = up or Y_AXIS
	if math.abs(z:Dot(Vec.unit(upHint, Y_AXIS))) > 0.999 then
		upHint = X_AXIS
	end

	local x = Vec.unit(upHint:Cross(z), X_AXIS)
	local y = Vec.unit(z:Cross(x), Y_AXIS)
	return {
		origin = origin,
		xAxis = x,
		yAxis = y,
		zAxis = z,
	}
end

function Basis.fromCFrame(frame: CFrame): Basis
	return {
		origin = frame.Position,
		xAxis = frame.RightVector,
		yAxis = frame.UpVector,
		zAxis = frame.LookVector,
	}
end

function Basis.toWorldVector(basis: Basis, localVector: Vector3): Vector3
	return basis.xAxis * localVector.X
		+ basis.yAxis * localVector.Y
		+ basis.zAxis * localVector.Z
end

function Basis.toLocalVector(basis: Basis, worldVector: Vector3): Vector3
	return Vector3.new(
		worldVector:Dot(basis.xAxis),
		worldVector:Dot(basis.yAxis),
		worldVector:Dot(basis.zAxis)
	)
end

function Basis.toWorldPoint(basis: Basis, localPoint: Vector3): Vector3
	return basis.origin + Basis.toWorldVector(basis, localPoint)
end

function Basis.toLocalPoint(basis: Basis, worldPoint: Vector3): Vector3
	return Basis.toLocalVector(basis, worldPoint - basis.origin)
end

function Basis.toCFrame(basis: Basis): CFrame
	return CFrame.fromMatrix(basis.origin, basis.xAxis, basis.yAxis, -basis.zAxis)
end

return Basis
