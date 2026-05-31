--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Signal = require(ReplicatedStorage.Packages.Signal)

local GamepadTargetServiceClient = {}

type SignalConnection = {
	Disconnect: (self: SignalConnection) -> (),
}

type TargetChangedSignal = {
	Connect: (self: TargetChangedSignal, callback: (worldPosition: Vector3?) -> ()) -> SignalConnection,
	Fire: (self: TargetChangedSignal, worldPosition: Vector3?) -> (),
	DisconnectAll: (self: TargetChangedSignal) -> (),
	Destroy: (self: TargetChangedSignal) -> (),
}

local POSITION_EPSILON = 1e-4
local SCREEN_VECTOR_EPSILON = 1e-4

local targetWorldPosition = nil :: Vector3?
local targetScreenVector = nil :: Vector2?

GamepadTargetServiceClient.TargetChanged = Signal.new() :: TargetChangedSignal

local function worldPositionsEqual(a: Vector3?, b: Vector3?): boolean
	if a == nil or b == nil then
		return a == b
	end

	return (a - b).Magnitude <= POSITION_EPSILON
end

local function screenVectorsEqual(a: Vector2?, b: Vector2?): boolean
	if a == nil or b == nil then
		return a == b
	end

	return (a - b).Magnitude <= SCREEN_VECTOR_EPSILON
end

local function sanitizeWorldPosition(worldPositionRaw: any): Vector3?
	return if typeof(worldPositionRaw) == "Vector3" then worldPositionRaw :: Vector3 else nil
end

local function sanitizeScreenVector(screenVectorRaw: any): Vector2?
	return if typeof(screenVectorRaw) == "Vector2" then screenVectorRaw :: Vector2 else nil
end

function GamepadTargetServiceClient.SetTarget(worldPositionRaw: any, screenVectorRaw: any?): boolean
	local nextWorldPosition = sanitizeWorldPosition(worldPositionRaw)
	local nextScreenVector = sanitizeScreenVector(screenVectorRaw)
	local worldChanged = not worldPositionsEqual(targetWorldPosition, nextWorldPosition)
	local screenChanged = not screenVectorsEqual(targetScreenVector, nextScreenVector)
	if not worldChanged and not screenChanged then
		return false
	end

	targetWorldPosition = nextWorldPosition
	targetScreenVector = nextScreenVector
	if worldChanged then
		GamepadTargetServiceClient.TargetChanged:Fire(targetWorldPosition)
	end
	return true
end

function GamepadTargetServiceClient.SetTargetWorldPosition(worldPositionRaw: any): boolean
	return GamepadTargetServiceClient.SetTarget(worldPositionRaw, targetScreenVector)
end

function GamepadTargetServiceClient.SetTargetScreenVector(screenVectorRaw: any): boolean
	return GamepadTargetServiceClient.SetTarget(targetWorldPosition, screenVectorRaw)
end

function GamepadTargetServiceClient.ClearTarget(): boolean
	return GamepadTargetServiceClient.SetTarget(nil, nil)
end

function GamepadTargetServiceClient.GetTargetWorldPosition(): Vector3?
	return targetWorldPosition
end

function GamepadTargetServiceClient.GetTargetScreenVector(): Vector2?
	return targetScreenVector
end

function GamepadTargetServiceClient.OnTargetChanged(callbackRaw: any): () -> ()
	if typeof(callbackRaw) ~= "function" then
		return function() end
	end

	local connection = GamepadTargetServiceClient.TargetChanged:Connect(callbackRaw :: (Vector3?) -> ())
	return function()
		connection:Disconnect()
	end
end

GamepadTargetServiceClient.setTarget = GamepadTargetServiceClient.SetTarget
GamepadTargetServiceClient.setTargetWorldPosition = GamepadTargetServiceClient.SetTargetWorldPosition
GamepadTargetServiceClient.setTargetScreenVector = GamepadTargetServiceClient.SetTargetScreenVector
GamepadTargetServiceClient.clearTarget = GamepadTargetServiceClient.ClearTarget
GamepadTargetServiceClient.getTargetWorldPosition = GamepadTargetServiceClient.GetTargetWorldPosition
GamepadTargetServiceClient.getTargetScreenVector = GamepadTargetServiceClient.GetTargetScreenVector
GamepadTargetServiceClient.onTargetChanged = GamepadTargetServiceClient.OnTargetChanged
GamepadTargetServiceClient.targetChanged = GamepadTargetServiceClient.TargetChanged

return GamepadTargetServiceClient
