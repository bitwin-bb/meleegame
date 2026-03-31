--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local TestEZ = require(ReplicatedStorage.Packages.TestEZ)
local sharedTests = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Tests")

TestEZ.TestBootstrap:run({
	sharedTests:WaitForChild("Specs"),
})
