--!strict

--// Services
local RunService = game:GetService("RunService")

--// Modules
local Config = require(script.Parent.Config)
local Events = require(script.Parent.Events)
local TypeDefs = require(script.Parent.TypeDefinitions)
local TypeMarshaller = require(script.Parent.TypeMarshaller)
local table = require(script.Parent.Parent.VendorTable)

--// Types
type ClassData = {
	Events: Events.Class,
	StateInfo: TypeDefs.CastStateInfo,
	RayInfo: TypeDefs.CastRayInfo,
	UserData: { [any]: any },
}

--// Variables
-- local FastCast = nil -- Static reference to the FastCast static module.

-- Format params: methodName, ctorName
local ERR_NOT_INSTANCE =
	"Cannot statically invoke method '%s' - It is an instance method. Call it on an instance of this class created via %s"

-- The name of the folder containing the 3D GUI elements for visualizing casts in debug mode.
local FC_VIS_OBJ_NAME = "FastCastVisualizationObjects"

-- Format params: N/A
local ERR_OBJECT_DISPOSED = "This ActiveCast has been terminated. It can no longer be used."

-- If pierce callback has to run more than this many times, it will register a hit and stop calculating pierces.
-- This only applies for repeated piercings, e.g. the amount of parts that fit within the space of a single cast segment (NOT the whole bullet's trajectory over its entire lifetime)
local MAX_PIERCE_TEST_COUNT = 100

--// Functions
-- Looks for a folder within workspace.Terrain that contains elements to visualize casts.
local function GetFastCastVisualizationContainer(): Instance
	local foundObj = workspace.Terrain:FindFirstChild(FC_VIS_OBJ_NAME)
	if foundObj then
		return foundObj
	end

	local folder = Instance.new("Folder")
	folder.Name = FC_VIS_OBJ_NAME
	folder.Archivable = false -- TODO: Keep this as-is? You can't copy/paste it if this is false. I have it false so that it doesn't linger in studio if you save with the debug data in there.
	folder.Parent = workspace.Terrain
	return folder
end

-- Print that runs only if debug mode is active.
local function PrintDebug(message: string)
	if Config.DebugLogging then
		print(message)
	end
end

-- Visualizes a ray. This will not run if FastCast.VisualizeCasts is false.
function DbgVisualizeSegment(castStartCFrame: CFrame, castLength: number): ConeHandleAdornment?
	if not Config.VisualizeCasts then
		return
	end

	local adornment = Instance.new("ConeHandleAdornment")
	adornment.Adornee = workspace.Terrain
	adornment.CFrame = castStartCFrame
	adornment.Height = castLength
	adornment.Color3 = Color3.new()
	adornment.Radius = 0.25
	adornment.Transparency = 0.5
	adornment.Parent = GetFastCastVisualizationContainer()
	return adornment
end

-- Visualizes an impact. This will not run if FastCast.VisualizeCasts is false.
function DbgVisualizeHit(atCF: CFrame, wasPierce: boolean): SphereHandleAdornment?
	if not Config.VisualizeCasts then
		return
	end

	local adornment = Instance.new("SphereHandleAdornment")
	adornment.Adornee = workspace.Terrain
	adornment.CFrame = atCF
	adornment.Radius = 0.4
	adornment.Transparency = 0.25
	adornment.Color3 = (wasPierce == false) and Color3.new(0.2, 1, 0.5) or Color3.new(1, 0.2, 0.2)
	adornment.Parent = GetFastCastVisualizationContainer()
	return adornment
end

-- Thanks to zoebasil for supplying the velocity and position functions below. (I've modified these functions)
-- I was having a huge issue trying to get it to work and I had overcomplicated a bunch of stuff.
-- GetPositionAtTime is used in physically simulated rays (Where Caster.HasPhysics == true or the specific Fire has a specified acceleration).
-- This returns the location that the bullet will be at when you specify the amount of time the bullet has existed, the original location of the bullet, and the velocity it was launched with.
local function GetPositionAtTime(
	time: number,
	origin: Vector3,
	initialVelocity: Vector3,
	acceleration: Vector3
): Vector3
	local force =
		Vector3.new((acceleration.X * time ^ 2) / 2, (acceleration.Y * time ^ 2) / 2, (acceleration.Z * time ^ 2) / 2)
	return origin + (initialVelocity * time) + force
end

-- A variant of the function above that returns the velocity at a given point in time.
local function GetVelocityAtTime(time: number, initialVelocity: Vector3, acceleration: Vector3): Vector3
	return initialVelocity + acceleration * time
end

local function GetLatestTrajectoryEndInfo(cast: Class): { [number]: Vector3 }
	assert(cast.StateInfo.UpdateConnection, ERR_OBJECT_DISPOSED)

	local trajectories = cast.StateInfo.Trajectories
	local trajectory = trajectories[#trajectories]
	local duration = trajectory.EndTime - trajectory.StartTime

	local origin = trajectory.Origin
	local vel = trajectory.InitialVelocity
	local accel = trajectory.Acceleration

	return { GetPositionAtTime(duration, origin, vel, accel), GetVelocityAtTime(duration, vel, accel) }
end

local function CloneCastParams(params: RaycastParams): RaycastParams
	local clone = RaycastParams.new()
	clone.CollisionGroup = params.CollisionGroup
	clone.FilterType = params.FilterType
	clone.FilterDescendantsInstances = params.FilterDescendantsInstances
	clone.IgnoreWater = params.IgnoreWater
	return clone
end

local function SendRayHit(
	cast: Class,
	resultOfCast: RaycastResult,
	segmentVelocity: Vector3,
	cosmeticBulletObject: Instance?
)
	cast.Events.RayHit:Fire(cast, resultOfCast, segmentVelocity, cosmeticBulletObject)
end

local function SendRayPierced(
	cast: Class,
	resultOfCast: RaycastResult,
	segmentVelocity: Vector3,
	cosmeticBulletObject: Instance?
)
	cast.Events.RayPierced:Fire(cast, resultOfCast, segmentVelocity, cosmeticBulletObject)
end

local function SendLengthChanged(
	cast: Class,
	lastPoint: Vector3,
	rayDir: Vector3,
	rayDisplacement: number,
	segmentVelocity: Vector3,
	cosmeticBulletObject: Instance?
)
	cast.Events.LengthChanged:Fire(cast, lastPoint, rayDir, rayDisplacement, segmentVelocity, cosmeticBulletObject)
end

-- Simulate a raycast by one tick.
local function SimulateCast(cast: Class, delta: number, expectingShortCall: boolean)
	assert(cast.StateInfo.UpdateConnection, ERR_OBJECT_DISPOSED)
	PrintDebug("Casting for frame.")

	local latestTrajectory = cast.StateInfo.Trajectories[#cast.StateInfo.Trajectories]

	local origin = latestTrajectory.Origin
	local totalDelta = cast.StateInfo.TotalRuntime - latestTrajectory.StartTime
	local initialVelocity = latestTrajectory.InitialVelocity
	local acceleration = latestTrajectory.Acceleration

	local lastPoint = GetPositionAtTime(totalDelta, origin, initialVelocity, acceleration)
	local lastDelta = cast.StateInfo.TotalRuntime - latestTrajectory.StartTime

	cast.StateInfo.TotalRuntime += delta

	-- Recalculate this.
	totalDelta = cast.StateInfo.TotalRuntime - latestTrajectory.StartTime

	local currentTarget = GetPositionAtTime(totalDelta, origin, initialVelocity, acceleration)
	local segmentVelocity = GetVelocityAtTime(totalDelta, initialVelocity, acceleration)
	local totalDisplacement = currentTarget - lastPoint -- This is the displacement from where the ray was on the last from to where the ray is now.

	local rayDir = totalDisplacement.Unit * segmentVelocity.Magnitude * delta
	local targetWorldRoot = cast.RayInfo.WorldRoot
	local resultOfCast = targetWorldRoot:Raycast(lastPoint, rayDir, cast.RayInfo.Parameters)

	local point = currentTarget
	local part: Instance? = nil
	local material = Enum.Material.Air
	if resultOfCast then
		point = resultOfCast.Position
		part = resultOfCast.Instance
		material = resultOfCast.Material
	end

	local rayDisplacement = (point - lastPoint).Magnitude
	-- For clarity -- totalDisplacement is how far the ray would have traveled if it hit nothing,
	-- and rayDisplacement is how far the ray really traveled (which will be identical to totalDisplacement if it did indeed hit nothing)

	SendLengthChanged(cast, lastPoint, rayDir.Unit, rayDisplacement, segmentVelocity, cast.RayInfo.CosmeticBulletObject)
	cast.StateInfo.DistanceCovered += rayDisplacement

	local rayVisualization: ConeHandleAdornment? = nil
	if delta > 0 then
		rayVisualization = DbgVisualizeSegment(CFrame.new(lastPoint, lastPoint + rayDir), rayDisplacement)
	end

	-- HIT DETECTED. Handle all that garbage, and also handle behaviors 1 and 2 (default behavior, go high res when hit) if applicable.
	-- CAST BEHAVIOR 2 IS HANDLED IN THE CODE THAT CALLS THIS FUNCTION.
	--task.synchronize()

	if part and not (part == cast.RayInfo.CosmeticBulletObject) then
		PrintDebug("Hit something, testing now.")

		-- SANITY CHECK: Don't allow the user to yield or run otherwise extensive code that takes longer than one frame/heartbeat to execute.
		if cast.RayInfo.CanPierceCallback ~= nil then
			if expectingShortCall == false then
				if cast.StateInfo.IsActivelySimulatingPierce then
					cast:Terminate()
					error(
						"ERROR: The latest call to CanPierceCallback took too long to complete! This cast is going to suffer desyncs which WILL cause unexpected behavior and errors. Please fix your performance problems, or remove statements that yield (e.g. wait() calls)"
					)
					-- Use error. This should absolutely abort the cast.
				end
			end
			-- expectingShortCall is used to determine if we are doing a forced resolution increase, in which case this will be called several times in a single frame, which throws this error.
			cast.StateInfo.IsActivelySimulatingPierce = true
		end

		if
			not cast.RayInfo.CanPierceCallback
			or (
				cast.RayInfo.CanPierceCallback
				and resultOfCast
				and not cast.RayInfo.CanPierceCallback(cast, resultOfCast, segmentVelocity)
			)
		then
			PrintDebug("Piercing function is nil or it returned FALSE to not pierce this hit.")
			cast.StateInfo.IsActivelySimulatingPierce = false

			if
				cast.StateInfo.HighFidelityBehavior == 2
				and latestTrajectory.Acceleration ~= Vector3.new()
				and cast.StateInfo.HighFidelitySegmentSize ~= 0
			then
				cast.StateInfo.CancelHighResCast = false -- Reset this here.

				if cast.StateInfo.IsActivelyResimulating then
					cast:Terminate()
					error(
						"Cascading cast lag encountered! The caster attempted to perform a high fidelity cast before the previous one completed, resulting in exponential cast lag. Consider increasing HighFidelitySegmentSize."
					)
				end

				cast.StateInfo.IsActivelyResimulating = true

				-- This is a physics based cast and it needs to be recalculated.
				PrintDebug(
					"Hit was registered, but recalculation is on for physics based casts. Recalculating to verify a real hit..."
				)

				-- Split this ray segment into smaller segments of a given size.
				-- In 99% of cases, it won't divide evently (e.g. I have a distance of 1.25 and I want to divide into 0.1 -- that won't work)
				-- To fix this, the segments need to be stretched slightly to fill the space (rather than having a single shorter segment at the end)

				local numSegmentsDecimal = rayDisplacement / cast.StateInfo.HighFidelitySegmentSize -- say rayDisplacement is 5.1, segment size is 0.5 -- 10.2 segments
				local numSegmentsReal = math.floor(numSegmentsDecimal) -- 10 segments + 0.2 extra segments

				-- Now the real hard part is converting this to time.
				local timeIncrement = delta / numSegmentsReal
				for segmentIndex = 1, numSegmentsReal do
					if cast.StateInfo.CancelHighResCast then
						cast.StateInfo.CancelHighResCast = false
						break
					end

					local subPosition = GetPositionAtTime(
						lastDelta + (timeIncrement * segmentIndex),
						origin,
						initialVelocity,
						acceleration
					)
					local subVelocity =
						GetVelocityAtTime(lastDelta + (timeIncrement * segmentIndex), initialVelocity, acceleration)
					local subRayDir = subVelocity * delta
					local subResult = targetWorldRoot:Raycast(subPosition, subRayDir, cast.RayInfo.Parameters)

					local subDisplacement = (subPosition - (subPosition + subVelocity)).Magnitude

					if subResult then
						subDisplacement = (subPosition - subResult.Position).Magnitude
						local dbgSeg =
							DbgVisualizeSegment(CFrame.new(subPosition, subPosition + subVelocity), subDisplacement)
						if dbgSeg ~= nil then
							dbgSeg.Color3 = Color3.new(0.286275, 0.329412, 0.247059)
						end

						if
							not cast.RayInfo.CanPierceCallback
							or (
								cast.RayInfo.CanPierceCallback
								and not cast.RayInfo.CanPierceCallback(cast, subResult, subVelocity)
							)
						then
							-- Still hit even at high res
							cast.StateInfo.IsActivelyResimulating = false

							SendRayHit(cast, subResult, subVelocity, cast.RayInfo.CosmeticBulletObject)
							cast:Terminate()
							local vis = DbgVisualizeHit(CFrame.new(point), false)
							if vis ~= nil then
								vis.Color3 = Color3.new(0.0588235, 0.87451, 1)
							end
							return
						else
							-- Recalculating hit something pierceable instead.
							SendRayPierced(cast, subResult, subVelocity, cast.RayInfo.CosmeticBulletObject) -- This may result in CancelHighResCast being set to true.
							local vis = DbgVisualizeHit(CFrame.new(point), true)
							if vis ~= nil then
								vis.Color3 = Color3.new(1, 0.113725, 0.588235)
							end
							if dbgSeg ~= nil then
								dbgSeg.Color3 = Color3.new(0.305882, 0.243137, 0.329412)
							end
						end
					else
						local dbgSeg =
							DbgVisualizeSegment(CFrame.new(subPosition, subPosition + subVelocity), subDisplacement)
						if dbgSeg ~= nil then
							dbgSeg.Color3 = Color3.new(0.286275, 0.329412, 0.247059)
						end
					end
				end

				-- If the script makes it here, then it wasn't a real hit (higher resolution revealed that the low-res hit was faulty)
				-- Just let it keep going.
				cast.StateInfo.IsActivelyResimulating = false
			elseif cast.StateInfo.HighFidelityBehavior ~= 1 and cast.StateInfo.HighFidelityBehavior ~= 3 then
				cast:Terminate()
				error("Invalid value " .. cast.StateInfo.HighFidelityBehavior .. " for HighFidelityBehavior.")
			else
				-- This is not a physics cast, or recalculation is off.
				PrintDebug("Hit was successful. Terminating.")
				SendRayHit(cast, resultOfCast, segmentVelocity, cast.RayInfo.CosmeticBulletObject)
				cast:Terminate()
				DbgVisualizeHit(CFrame.new(point), false)
				return
			end
		else
			PrintDebug("Piercing function returned TRUE to pierce this part.")
			if rayVisualization ~= nil then
				rayVisualization.Color3 = Color3.new(0.4, 0.05, 0.05) -- Turn it red to signify that the cast was scrapped.
			end
			DbgVisualizeHit(CFrame.new(point), true)

			local params = cast.RayInfo.Parameters
			local alteredParts = {}
			local currentPierceTestCount = 0
			local originalFilter = params.FilterDescendantsInstances
			local brokeFromSolidObject = false
			while true do
				if not resultOfCast then
					continue
				end
				-- So now what I need to do is redo this entire cast, just with the new filter list

				-- Catch case: Is it terrain?
				if resultOfCast.Instance:IsA("Terrain") then
					if material == Enum.Material.Water then
						-- Special case: Pierced on water?
						cast:Terminate()
						error(
							"Do not add Water as a piercable material. If you need to pierce water, set cast.RayInfo.Parameters.IgnoreWater = true instead",
							0
						)
					end
					warn(
						"WARNING: The pierce callback for this cast returned TRUE on Terrain! This can cause severely adverse effects."
					)
				end

				if params.FilterType == Enum.RaycastFilterType.Exclude then
					-- blacklist
					-- DO NOT DIRECTLY TABLE.INSERT ON THE PROPERTY
					local filter = params.FilterDescendantsInstances
					table.insert(filter, resultOfCast.Instance)
					table.insert(alteredParts, resultOfCast.Instance)
					params.FilterDescendantsInstances = filter
				else
					-- whitelist
					-- method implemeneted by custom table system
					-- DO NOT DIRECTLY TABLE.REMOVEOBJECT ON THE PROPERTY
					local filter = params.FilterDescendantsInstances
					table.removeObject(filter, resultOfCast.Instance)
					table.insert(alteredParts, resultOfCast.Instance)
					params.FilterDescendantsInstances = filter
				end

				SendRayPierced(cast, resultOfCast, segmentVelocity, cast.RayInfo.CosmeticBulletObject)

				-- List has been updated, so let's cast again.
				local newResultOfCast = targetWorldRoot:Raycast(lastPoint, rayDir, params)

				-- No hit? No simulation. Break.
				if not newResultOfCast then
					break
				end

				-- Set result of cast to new cast
				resultOfCast = newResultOfCast

				if currentPierceTestCount >= MAX_PIERCE_TEST_COUNT then
					warn(
						"WARNING: Exceeded maximum pierce test budget for a single ray segment (attempted to test the same segment "
							.. MAX_PIERCE_TEST_COUNT
							.. " times!)"
					)
					break
				end
				currentPierceTestCount = currentPierceTestCount + 1

				if
					not cast.RayInfo.CanPierceCallback
					or not cast.RayInfo.CanPierceCallback(cast, resultOfCast, segmentVelocity)
				then
					brokeFromSolidObject = true
					break
				end
			end

			-- Restore the filter to its default state.
			cast.RayInfo.Parameters.FilterDescendantsInstances = originalFilter
			cast.StateInfo.IsActivelySimulatingPierce = false

			if resultOfCast and brokeFromSolidObject then
				-- We actually hit something while testing.
				PrintDebug(
					"Broke because the ray hit something solid ("
						.. tostring(resultOfCast.Instance)
						.. ") while testing for a pierce. Terminating the cast."
				)
				SendRayHit(cast, resultOfCast, segmentVelocity, cast.RayInfo.CosmeticBulletObject)
				cast:Terminate()
				DbgVisualizeHit(CFrame.new(resultOfCast.Position), false)
				return
			end

			-- And exit the function here too.
		end
	end

	if cast.StateInfo.DistanceCovered >= cast.RayInfo.MaxDistance then
		-- SendRayHit(cast, nil, segmentVelocity, cast.RayInfo.CosmeticBulletObject)
		cast:Terminate()
		DbgVisualizeHit(CFrame.new(currentTarget), false)
	end
end

local function ModifyTransformation(cast: Class, velocity: Vector3?, acceleration: Vector3?, position: Vector3?)
	local trajectories = cast.StateInfo.Trajectories
	local lastTrajectory = trajectories[#trajectories]

	-- NEW BEHAVIOR: Don't create a new trajectory if we haven't even used the current one.
	if lastTrajectory.StartTime == cast.StateInfo.TotalRuntime then
		-- This trajectory is fresh out of the box. Let's just change it since it hasn't actually affected the cast yet, so changes won't have adverse effects.
		lastTrajectory.Origin = position or lastTrajectory.Origin
		lastTrajectory.InitialVelocity = velocity or lastTrajectory.InitialVelocity
		lastTrajectory.Acceleration = acceleration or lastTrajectory.Acceleration
	else
		-- The latest trajectory is done. Set its end time and get its location.
		lastTrajectory.EndTime = cast.StateInfo.TotalRuntime

		local point, velAtPoint = unpack(GetLatestTrajectoryEndInfo(cast))
		table.insert(cast.StateInfo.Trajectories, {
			StartTime = cast.StateInfo.TotalRuntime,
			EndTime = -1,
			Origin = position or point,
			InitialVelocity = velocity or velAtPoint,
			Acceleration = acceleration or lastTrajectory.Acceleration,
		})
		cast.StateInfo.CancelHighResCast = true
	end
end

--// Class Setup
local Class = {}
Class.__index = Class
Class.__type = "ActiveCast" -- For compatibility with TypeMarshaller
export type Class = typeof(setmetatable({} :: ClassData, Class))

function Class.new(
	events: Events.Class,
	origin: Vector3,
	direction: Vector3,
	inputVelo: Vector3 | number,
	castDataPacket: TypeDefs.FastCastBehavior
)
	-- Validation
	if castDataPacket.HighFidelitySegmentSize <= 0 then
		error("Cannot set FastCastBehavior.HighFidelitySegmentSize <= 0!")
	end

	local self = setmetatable({}, Class) :: Class

	-- Obtain velocity
	local velocity: Vector3
	if typeof(inputVelo) == "number" then
		velocity = inputVelo * direction.Unit
	else
		velocity = inputVelo :: Vector3
	end

	-- Set attributes
	self.Events = events
	self.StateInfo = {
		UpdateConnection = nil,
		Paused = false,
		TotalRuntime = 0,
		DistanceCovered = 0,
		HighFidelitySegmentSize = castDataPacket.HighFidelitySegmentSize,
		HighFidelityBehavior = castDataPacket.HighFidelityBehavior,
		IsActivelySimulatingPierce = false,
		IsActivelyResimulating = false,
		CancelHighResCast = false,
		Trajectories = {
			{
				StartTime = 0,
				EndTime = -1,
				Origin = origin,
				InitialVelocity = velocity,
				Acceleration = castDataPacket.Acceleration,
			},
		},
	}
	self.RayInfo = {
		Parameters = castDataPacket.RaycastParams and CloneCastParams(castDataPacket.RaycastParams)
			or RaycastParams.new(),
		WorldRoot = workspace,
		MaxDistance = castDataPacket.MaxDistance or 1000,
		CosmeticBulletObject = castDataPacket.CosmeticBulletTemplate, -- This is intended. We clone it a smidge of the way down.
		CanPierceCallback = castDataPacket.CanPierceFunction,
	}
	self.UserData = {}

	-- Tweak attributes
	if self.StateInfo.HighFidelityBehavior == 2 then
		self.StateInfo.HighFidelityBehavior = 3
	end

	local usingProvider = false
	if not castDataPacket.CosmeticBulletProvider then
		-- The provider is nil. Use a cosmetic object clone.
		local RayInfo = self.RayInfo
		if RayInfo.CosmeticBulletObject then
			RayInfo.CosmeticBulletObject = RayInfo.CosmeticBulletObject:Clone()
			RayInfo.CosmeticBulletObject.CFrame = CFrame.new(origin, origin + direction)
			RayInfo.CosmeticBulletObject.Parent = castDataPacket.CosmeticBulletContainer
		end
	else
		-- The provider is not nil.
		-- Is it what we want?
		if TypeMarshaller(castDataPacket.CosmeticBulletProvider) == "PartCache" then
			-- this modded version of typeof is implemented up top.
			-- Aside from that, yes, it's a part cache. Good to go!

			if self.RayInfo.CosmeticBulletObject then
				-- They also set the template. Not good. Warn + clear this up.
				warn(
					"Do not define FastCastBehavior.CosmeticBulletTemplate and FastCastBehavior.CosmeticBulletProvider at the same time! The provider will be used, and CosmeticBulletTemplate will be set to nil."
				)
				self.RayInfo.CosmeticBulletObject = nil
				castDataPacket.CosmeticBulletTemplate = nil
			end

			local CosmeticBulletObject = castDataPacket.CosmeticBulletProvider:GetPart()
			CosmeticBulletObject.CFrame = CFrame.new(origin, origin + direction)
			self.RayInfo.CosmeticBulletObject = CosmeticBulletObject
			usingProvider = true
		else
			warn(
				"FastCastBehavior.CosmeticBulletProvider was not an instance of the PartCache module (an external/separate model)! Are you inputting an instance created via PartCache.new? If so, are you on the latest version of PartCache? Setting FastCastBehavior.CosmeticBulletProvider to nil."
			)
			castDataPacket.CosmeticBulletProvider = nil
		end
	end

	local targetContainer: Instance?
	if usingProvider and castDataPacket.CosmeticBulletProvider then
		targetContainer = castDataPacket.CosmeticBulletProvider.CurrentCacheParent
	else
		targetContainer = castDataPacket.CosmeticBulletContainer
	end

	if castDataPacket.AutoIgnoreContainer and targetContainer then
		local ignoreList = self.RayInfo.Parameters.FilterDescendantsInstances
		if not table.find(ignoreList, targetContainer) then
			table.insert(ignoreList, targetContainer)
			self.RayInfo.Parameters.FilterDescendantsInstances = ignoreList
		end
	end

	local event: RBXScriptSignal<number> = RunService:IsClient() and RunService.RenderStepped or RunService.Heartbeat

	local function Stepped(delta: number)
		if self.StateInfo.Paused then
			return
		end

		PrintDebug("Casting for frame.")
		local latestTrajectory = self.StateInfo.Trajectories[#self.StateInfo.Trajectories]
		if
			self.StateInfo.HighFidelityBehavior == 3
			and latestTrajectory.Acceleration ~= Vector3.new()
			and self.StateInfo.HighFidelitySegmentSize > 0
		then
			local timeAtStart = tick()

			if self.StateInfo.IsActivelyResimulating then
				self:Terminate()
				error(
					"Cascading cast lag encountered! The caster attempted to perform a high fidelity cast before the previous one completed, resulting in exponential cast lag. Consider increasing HighFidelitySegmentSize."
				)
			end

			self.StateInfo.IsActivelyResimulating = true

			-- Actually want to calculate this early to find displacement
			local trajectoryOrigin = latestTrajectory.Origin
			local totalDelta = self.StateInfo.TotalRuntime - latestTrajectory.StartTime
			local initialVelocity = latestTrajectory.InitialVelocity
			local acceleration = latestTrajectory.Acceleration
			local lastPoint = GetPositionAtTime(totalDelta, trajectoryOrigin, initialVelocity, acceleration)

			self.StateInfo.TotalRuntime += delta

			-- Recalculate this.
			totalDelta = self.StateInfo.TotalRuntime - latestTrajectory.StartTime

			local currentPoint = GetPositionAtTime(totalDelta, trajectoryOrigin, initialVelocity, acceleration)
			local currentVelocity = GetVelocityAtTime(totalDelta, initialVelocity, acceleration)
			local totalDisplacement = currentPoint - lastPoint -- This is the displacement from where the ray was on the last from to where the ray is now.

			local rayDir = totalDisplacement.Unit * currentVelocity.Magnitude * delta
			local targetWorldRoot = self.RayInfo.WorldRoot
			local resultOfCast = targetWorldRoot:Raycast(lastPoint, rayDir, self.RayInfo.Parameters)

			local point = currentPoint

			if resultOfCast ~= nil then
				point = resultOfCast.Position
			end

			local rayDisplacement = (point - lastPoint).Magnitude

			-- Now undo this. The line below in the for loop will add this time back gradually.
			self.StateInfo.TotalRuntime -= delta

			-- And now that we have displacement, we can calculate segment size.
			local numSegmentsDecimal = rayDisplacement / self.StateInfo.HighFidelitySegmentSize -- say rayDisplacement is 5.1, segment size is 0.5 -- 10.2 segments
			local numSegmentsReal = math.floor(numSegmentsDecimal) -- 10 segments + 0.2 extra segments
			if numSegmentsReal == 0 then
				numSegmentsReal = 1
			end

			local timeIncrement = delta / numSegmentsReal

			for segmentIndex = 1, numSegmentsReal do
				if getmetatable(self) == nil then
					return
				end -- Could have been disposed.
				if self.StateInfo.CancelHighResCast then
					self.StateInfo.CancelHighResCast = false
					break
				end
				PrintDebug("[" .. segmentIndex .. "] Subcast of time increment " .. timeIncrement)
				SimulateCast(self, timeIncrement, true)
			end

			if getmetatable(self) == nil then
				return
			end -- Could have been disposed.
			self.StateInfo.IsActivelyResimulating = false

			if (tick() - timeAtStart) > 0.016 * 5 then
				warn("Extreme cast lag encountered! Consider increasing HighFidelitySegmentSize.")
			end
		else
			SimulateCast(self, delta, false)
		end
	end

	self.StateInfo.UpdateConnection = (
		castDataPacket.Parallel and event:ConnectParallel(Stepped) or event:Connect(Stepped)
	)

	return self
end

--// Getters and Setters
function Class.GetVelocity(self: Class): Vector3
	assert(getmetatable(self) == Class, ERR_NOT_INSTANCE:format("GetVelocity", "ActiveCast.new(...)"))
	assert(self.StateInfo.UpdateConnection ~= nil, ERR_OBJECT_DISPOSED)

	local currentTrajectory = self.StateInfo.Trajectories[#self.StateInfo.Trajectories]
	return GetVelocityAtTime(
		self.StateInfo.TotalRuntime - currentTrajectory.StartTime,
		currentTrajectory.InitialVelocity,
		currentTrajectory.Acceleration
	)
end

function Class.GetAcceleration(self: Class): Vector3
	assert(getmetatable(self) == Class, ERR_NOT_INSTANCE:format("GetAcceleration", "ActiveCast.new(...)"))
	assert(self.StateInfo.UpdateConnection ~= nil, ERR_OBJECT_DISPOSED)

	local currentTrajectory = self.StateInfo.Trajectories[#self.StateInfo.Trajectories]
	return currentTrajectory.Acceleration
end

function Class.GetPosition(self: Class): Vector3
	assert(getmetatable(self) == Class, ERR_NOT_INSTANCE:format("GetPosition", "ActiveCast.new(...)"))
	assert(self.StateInfo.UpdateConnection ~= nil, ERR_OBJECT_DISPOSED)

	local currentTrajectory = self.StateInfo.Trajectories[#self.StateInfo.Trajectories]
	return GetPositionAtTime(
		self.StateInfo.TotalRuntime - currentTrajectory.StartTime,
		currentTrajectory.Origin,
		currentTrajectory.InitialVelocity,
		currentTrajectory.Acceleration
	)
end

function Class.SetVelocity(self: Class, velocity: Vector3)
	assert(getmetatable(self) == Class, ERR_NOT_INSTANCE:format("SetVelocity", "ActiveCast.new(...)"))
	assert(self.StateInfo.UpdateConnection ~= nil, ERR_OBJECT_DISPOSED)
	ModifyTransformation(self, velocity, nil, nil)
end

function Class.SetAcceleration(self: Class, acceleration: Vector3)
	assert(getmetatable(self) == Class, ERR_NOT_INSTANCE:format("SetAcceleration", "ActiveCast.new(...)"))
	assert(self.StateInfo.UpdateConnection ~= nil, ERR_OBJECT_DISPOSED)
	ModifyTransformation(self, nil, acceleration, nil)
end

function Class.SetPosition(self: Class, position: Vector3)
	assert(getmetatable(self) == Class, ERR_NOT_INSTANCE:format("SetPosition", "ActiveCast.new(...)"))
	assert(self.StateInfo.UpdateConnection ~= nil, ERR_OBJECT_DISPOSED)
	ModifyTransformation(self, nil, nil, position)
end

--// Arithmetic
function Class.AddVelocity(self: Class, velocity: Vector3)
	assert(getmetatable(self) == Class, ERR_NOT_INSTANCE:format("AddVelocity", "ActiveCast.new(...)"))
	assert(self.StateInfo.UpdateConnection ~= nil, ERR_OBJECT_DISPOSED)

	self:SetVelocity(self:GetVelocity() + velocity)
end

function Class.AddAcceleration(self: Class, acceleration: Vector3)
	assert(getmetatable(self) == Class, ERR_NOT_INSTANCE:format("AddAcceleration", "ActiveCast.new(...)"))
	assert(self.StateInfo.UpdateConnection ~= nil, ERR_OBJECT_DISPOSED)

	self:SetAcceleration(self:GetAcceleration() + acceleration)
end

function Class.AddPosition(self: Class, position: Vector3)
	assert(getmetatable(self) == Class, ERR_NOT_INSTANCE:format("AddPosition", "ActiveCast.new(...)"))
	assert(self.StateInfo.UpdateConnection ~= nil, ERR_OBJECT_DISPOSED)

	self:SetPosition(self:GetPosition() + position)
end

--// State Modification
function Class.Pause(self: Class)
	assert(getmetatable(self) == Class, ERR_NOT_INSTANCE:format("Pause", "ActiveCast.new(...)"))
	assert(self.StateInfo.UpdateConnection ~= nil, ERR_OBJECT_DISPOSED)

	self.StateInfo.Paused = true
end

function Class.Resume(self: Class)
	assert(getmetatable(self) == Class, ERR_NOT_INSTANCE:format("Resume", "ActiveCast.new(...)"))
	assert(self.StateInfo.UpdateConnection ~= nil, ERR_OBJECT_DISPOSED)

	self.StateInfo.Paused = false
end

function Class.Terminate(self: Class)
	assert(getmetatable(self) == Class, ERR_NOT_INSTANCE:format("Terminate", "ActiveCast.new(...)"))
	assert(self.StateInfo.UpdateConnection ~= nil, ERR_OBJECT_DISPOSED)

	-- First: Set EndTime on the latest trajectory since it is now done simulating.
	local trajectories = self.StateInfo.Trajectories
	local lastTrajectory = trajectories[#trajectories]
	lastTrajectory.EndTime = self.StateInfo.TotalRuntime

	-- Disconnect the update connection.
	self.StateInfo.UpdateConnection:Disconnect()

	-- Now fire CastTerminating
	self.Events.CastTerminating:FireSync(self)

	-- And now set the update connection object to nil.
	self.StateInfo.UpdateConnection = nil
end

return Class.new
