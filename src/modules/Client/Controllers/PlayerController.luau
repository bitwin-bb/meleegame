--!strict

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local gameRoot = script:FindFirstAncestor("game")
local Handlers = require(gameRoot.Client.Handlers)
local StateMachinePackage = require(gameRoot.Shared.StateMachine)

local Nevermore = StateMachinePackage.Nevermore
local Maid = Nevermore.Get("Maid")
local Promise = Nevermore.Get("Promise")
local Signal = Nevermore.Get("Signal")

local PlayerController = {}
PlayerController.__index = PlayerController

export type PlayerController = typeof(setmetatable(
	{} :: {
		maid: any,
		CharacterChanged: any,
		player: Player,
		character: Model?,
		machine: any?,
		inputHandler: any,
		movementHandler: any?,
		animationHandler: any?,
		effectHandler: any,
		cameraHandler: any,
		running: boolean,
	},
	PlayerController
))

function PlayerController.new(playerRaw: Player?): PlayerController
	local self = setmetatable({
		maid = Maid.new(),
		CharacterChanged = Signal.new(),
		player = playerRaw or Players.LocalPlayer,
		character = nil,
		machine = nil,
		inputHandler = Handlers.InputHandler.new(),
		movementHandler = nil,
		animationHandler = nil,
		effectHandler = Handlers.EffectHandler.new(),
		cameraHandler = Handlers.CameraHandler.new(),
		running = false,
	}, PlayerController)

	self.maid:GiveTask(self.CharacterChanged)
	self.maid:GiveTask(self.inputHandler)
	self.maid:GiveTask(self.effectHandler)
	self.maid:GiveTask(self.cameraHandler)
	return self
end

function PlayerController.SetCharacter(self: PlayerController, characterRaw: any?)
	local character = if typeof(characterRaw) == "Instance" and characterRaw:IsA("Model") then characterRaw else nil
	if self.character == character then
		return
	end

	self.maid.Character = Maid.new()
	self.character = character
	self.machine = nil
	self.CharacterChanged:Fire(character)

	if character == nil then
		self.movementHandler = nil
		self.animationHandler = nil
		return
	end

	local characterMaid = self.maid.Character
	local movementHandler = Handlers.MovementHandler.new(character)
	local humanoid = movementHandler.humanoid
	local animator = if humanoid ~= nil then humanoid:FindFirstChildOfClass("Animator") else nil
	local animationHandler = Handlers.AnimationHandler.new(animator or humanoid)

	characterMaid:GiveTask(movementHandler)
	characterMaid:GiveTask(animationHandler)
	self.movementHandler = movementHandler
	self.animationHandler = animationHandler

	self.machine = StateMachinePackage.Machines.Player.PlayerMachine.new({
		Character = character,
		Humanoid = humanoid,
		Root = movementHandler.root,
		Input = self.inputHandler,
		Movement = movementHandler,
		Animation = animationHandler,
		Effects = self.effectHandler,
		Camera = self.cameraHandler,
	})
	characterMaid:GiveTask(self.machine)
end

function PlayerController.Start(self: PlayerController): boolean
	if self.running then
		return true
	end
	self.running = true

	self:SetCharacter(self.player.Character)
	self.maid.CharacterAdded = self.player.CharacterAdded:Connect(function(character)
		self:SetCharacter(character)
	end)
	self.maid.Update = RunService.Heartbeat:Connect(function(dt)
		self:Update(dt)
	end)
	return true
end

function PlayerController.PromiseStarted(self: PlayerController): any
	return Promise.new(function(resolve, reject)
		if self:Start() then
			resolve(self)
		else
			reject("failed to start player controller")
		end
	end)
end

function PlayerController.Update(self: PlayerController, dt: number)
	local movementHandler = self.movementHandler
	local machine = self.machine
	if movementHandler ~= nil and movementHandler.humanoid ~= nil then
		self.inputHandler:SetMoveVector(movementHandler.humanoid.MoveDirection)
	end
	if machine ~= nil and typeof(machine.Update) == "function" then
		machine:Update(dt)
	end
end

function PlayerController.Stop(self: PlayerController)
	if not self.running then
		return
	end
	self.running = false
	self.maid.Update = nil
	if self.machine ~= nil and typeof(self.machine.Stop) == "function" then
		self.machine:Stop()
	end
end

function PlayerController.Destroy(self: PlayerController)
	self:Stop()
	self.maid:DoCleaning()
	self.character = nil
	self.machine = nil
	self.movementHandler = nil
	self.animationHandler = nil
end

PlayerController.setCharacter = PlayerController.SetCharacter
PlayerController.start = PlayerController.Start
PlayerController.promiseStarted = PlayerController.PromiseStarted
PlayerController.update = PlayerController.Update
PlayerController.stop = PlayerController.Stop
PlayerController.destroy = PlayerController.Destroy

return PlayerController
