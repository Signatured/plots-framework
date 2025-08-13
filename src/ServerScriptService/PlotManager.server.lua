--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameSettings = require(game.ServerScriptService.Game.GameServerLibrary.GameSettings)
local Saving = require(game.ServerScriptService.Library.Saving)
local ServerPlot = require(game.ServerScriptService.Plot.ServerPlot)
local Assert = require(game.ReplicatedStorage.Library.Assert)
local PivotPlayer = require(game.ReplicatedStorage.Library.Functions.PivotPlayer)

local PLOT_COUNT = GameSettings.PlotCount
local claimedPlots: {[number]: Player} = {}
local templatePlots: {[number]: Model} = {}

task.spawn(function()
    local blueprint = workspace:WaitForChild("PlotBlueprint", 9999)
    blueprint.Parent = ReplicatedStorage
end)

function SetupTemplates()
    local locations = workspace:WaitForChild("__THINGS"):WaitForChild("PlotLocations")
    local templateFolder = workspace:WaitForChild("__THINGS"):WaitForChild("PlotTemplates")

    for i = 1, PLOT_COUNT do
		local model = ReplicatedStorage:WaitForChild("PlotBlueprint", 9999):Clone()
		local loc = assert(locations:WaitForChild(tostring(i)))::BasePart
		loc.Transparency = 1
		loc.CanCollide = false 

        local playerBillboard = model:WaitForChild("PlayerBillboard"):WaitForChild("BillboardGui")::BillboardGui
        playerBillboard.Enabled = false

		model:PivotTo(loc.CFrame)
		model.Parent = templateFolder
		templatePlots[i] = model
    end

    print(templatePlots)
end

function UpdateTemplates()
    local templateFolder = workspace:WaitForChild("__THINGS"):WaitForChild("PlotTemplates")

    for i = 1, PLOT_COUNT do
        local template = templatePlots[i]
        if not template then
            continue
        end
        local isClaimed = claimedPlots[i]::Player? ~= nil
        if isClaimed then
            template.Parent = nil
        else
            template.Parent = templateFolder
        end
    end
end

function GetAvailablePlot(): number?
    for i = 1, PLOT_COUNT do
        if claimedPlots[i]::Player? == nil then
            return i
        end
    end
    return nil
end

function ClaimPlot(player: Player): CFrame?
    local locations = workspace:WaitForChild("__THINGS"):WaitForChild("PlotLocations")

    local index = GetAvailablePlot()
    if not index then
        return nil
    end
    local loc = locations:WaitForChild(tostring(index))::BasePart
    claimedPlots[index] = player
    return loc.CFrame
end

function SetupPlayer(player: Player)
    local cframe = nil
    while player.Parent do
        cframe = ClaimPlot(player)
        if cframe then
            break
        end
        task.wait()
    end

    assert(cframe, "Failed to claim plot")

    local save = Saving.Get(player)
    if not save then
        return
    end

    UpdateTemplates()

    local blueprint = ReplicatedStorage:WaitForChild("PlotBlueprint", 9999):Clone()
    local plot = ServerPlot.new(player, blueprint, cframe)

    plot:OwnerInvoked("ClaimEarnings", function(index: number)
        Assert.IntegerPositive(index)

        local success, amount = plot:ClaimEarnings(index)
        return success, amount
    end)

    plot:OwnerInvoked("SellFish", function(index: number)
        Assert.IntegerPositive(index)

        local success, amount = plot:SellFish(index)
        return success, amount
    end)

    plot:OwnerInvoked("PickupFish", function(index: number)
        Assert.IntegerPositive(index)

        local success = plot:PickupFish(index)
        return success
    end)

    local spawnPart = plot:GetModel():WaitForChild("Spawn")::BasePart
    local teleportCFrame = spawnPart:GetPivot() + Vector3.new(0, 3, 0) 
	task.delay(0.25, function()
		PivotPlayer(player, teleportCFrame)
	end)
    player.CharacterAdded:Connect(function(character: Model)
        task.delay(0.25, function()
            PivotPlayer(player, teleportCFrame)
        end)
    end)

    task.delay(4, function()
        print("Firing")
        plot:Fire("Test", {
            Message = "Hello"
        })
    end)
end

function RemovePlayer(player: Player)
	for i, entryPlayer in pairs(claimedPlots) do 
		if entryPlayer == player then 
			claimedPlots[i] = nil
			break
		end
	end

    task.defer(UpdateTemplates)
end

Saving.SaveAdded:Connect(function(player: Player)
    SetupPlayer(player)
end)

Players.PlayerRemoving:Connect(function(player: Player)
    RemovePlayer(player)
end)

SetupTemplates()
UpdateTemplates()