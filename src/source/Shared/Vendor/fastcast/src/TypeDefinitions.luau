--!strict

-- Defines all FC types.
-- Any script that requires this will have these types defined.

--[[
local TypeDefs = require(script.TypeDefinitions)
type CanPierceFunction = TypeDefs.CanPierceFunction
type Caster = TypeDefs.Caster
type FastCastBehavior = TypeDefs.FastCastBehavior
type CastTrajectory = TypeDefs.CastTrajectory
type CastStateInfo = TypeDefs.CastStateInfo
type CastRayInfo = TypeDefs.CastRayInfo
type ActiveCast = TypeDefs.ActiveCast
--]]

local PartCache = require(script.Parent.Parent.PartCache)

-- Represents the function to determine piercing.
export type CanPierceFunction = (ActiveCast, RaycastResult, Vector3) -> boolean

-- Represents a FastCastBehavior :: https://etithespirit.github.io/FastCastAPIDocs/fastcast-objects/fcbehavior/
export type FastCastBehavior = {
	Parallel: boolean,
	RaycastParams: RaycastParams?,
	MaxDistance: number,
	Acceleration: Vector3,
	HighFidelityBehavior: number,
	HighFidelitySegmentSize: number,
	CosmeticBulletTemplate: BasePart?,
	CosmeticBulletProvider: PartCache.Class?,
	CosmeticBulletContainer: Instance?,
	AutoIgnoreContainer: boolean,
	CanPierceFunction: CanPierceFunction?,
}

-- Represents a CastTrajectory :: https://etithespirit.github.io/FastCastAPIDocs/fastcast-objects/casttrajectory/
export type CastTrajectory = {
	StartTime: number,
	EndTime: number,
	Origin: Vector3,
	InitialVelocity: Vector3,
	Acceleration: Vector3,
}

-- Represents a CastStateInfo :: https://etithespirit.github.io/FastCastAPIDocs/fastcast-objects/caststateinfo/
export type CastStateInfo = {
	UpdateConnection: RBXScriptConnection?,
	HighFidelityBehavior: number,
	HighFidelitySegmentSize: number,
	Paused: boolean,
	TotalRuntime: number,
	DistanceCovered: number,
	IsActivelySimulatingPierce: boolean,
	IsActivelyResimulating: boolean,
	CancelHighResCast: boolean,
	Trajectories: { CastTrajectory },
}

-- Represents a CastRayInfo :: https://etithespirit.github.io/FastCastAPIDocs/fastcast-objects/castrayinfo/
export type CastRayInfo = {
	Parameters: RaycastParams,
	WorldRoot: WorldRoot,
	MaxDistance: number,
	CosmeticBulletObject: BasePart?,
	CanPierceCallback: CanPierceFunction?,
}

-- Represents an ActiveCast :: https://etithespirit.github.io/FastCastAPIDocs/fastcast-objects/activecast/
export type ActiveCast = typeof(setmetatable(
	{} :: {
		StateInfo: CastStateInfo,
		RayInfo: CastRayInfo,
		UserData: { [any]: any },
	},
	{} :: {
		GetVelocity: (any) -> Vector3,
		GetAcceleration: (any) -> Vector3,
		GetPosition: (any) -> Vector3,

		Pause: (any) -> (),
		Resume: (any) -> (),
		Terminate: (any) -> (),
	}
))

return {}
