--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Player = require(game.ReplicatedStorage.Library.Player)
local GameSettings = require(game.ServerScriptService.Game.Library.GameSettings)
local Saving = require(game.ServerScriptService.Library.Saving)
local ServerPlot = require(game.ServerScriptService.Plot.ServerPlot)
local Assert = require(game.ReplicatedStorage.Library.Assert)
local PivotPlayer = require(game.ReplicatedStorage.Library.Functions.PivotPlayer)
local Fish = require(game.ServerScriptService.Game.Library.Fish)
local Functions = require(game.ReplicatedStorage.Library.Functions)
local Directory = require(game.ReplicatedStorage.Game.Library.Directory)
local Network = require(game.ServerScriptService.Library.Network)
local FishTypes = require(game.ReplicatedStorage.Game.Library.Types.Fish)

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

        local pedestals = model:WaitForChild("Pedestals")::Model
        pedestals:Destroy()

        local trashcan = model:WaitForChild("TrashCan")::BasePart
        trashcan:Destroy()

        local packOffers = model:WaitForChild("PackOffers")::Model
        packOffers:Destroy()

        local groupOffer = model:WaitForChild("GroupOffer")::BasePart
        groupOffer:Destroy()

        local advertSign = model:WaitForChild("AdvertSign")::BasePart
        advertSign:Destroy()

        local lockButton = model:WaitForChild("LockButton")::BasePart
        lockButton:Destroy()

        local lock = model:WaitForChild("Lock")::BasePart
        lock:Destroy()

		model:PivotTo(loc.CFrame)
		model.Parent = templateFolder
		templatePlots[i] = model
    end
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

function IsPlayerSafe(player: Player): boolean
    local safeZone = workspace:WaitForChild("__THINGS"):WaitForChild("HomeBase")::Part
    local position = Player.Optional.Position(player)

    return position ~= nil and Functions.IsPositionInPart(position, safeZone)
end

function CreateFishData(fishId: string, type: FishTypes.fish_type): FishTypes.data_schema
    local now = workspace:GetServerTimeNow()
    local uid = Functions.GenerateUID()
    local fishData: FishTypes.data_schema = {
        UID = uid,
        FishId = fishId,
        Type = type,
        Shiny = false,
        Level = 1,
        CreateTime = now,
        BaseTime = now,
    }

    return fishData
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

        if not IsPlayerSafe(player) then
            return false, "You are not in a safe zone!"
        end

        local success, amount = plot:ClaimEarnings(index)
        return success, amount
    end)

    plot:OwnerInvoked("CreateFish", function(index: number, uid: string)
        Assert.String(uid)

        if not IsPlayerSafe(player) then
            return false, "You are not in a safe zone!"
        end

        local fishData = Fish.GetFromInventory(player, uid)
        if not fishData then
            return false
        end

        local success = plot:CreateFish(fishData, index)

        if success then
            Fish.Take(player, uid)
        end

        return success ~= nil
    end)

    plot:OwnerInvoked("UpgradeFish", function(index: number)
        Assert.IntegerPositive(index)

        if not IsPlayerSafe(player) then
            return false, "You are not in a safe zone!"
        end
        
        local success = plot:UpgradeFish(index)
        return success ~= nil
    end)

    plot:OwnerInvoked("SellFish", function(index: number)
        Assert.IntegerPositive(index)

        if not IsPlayerSafe(player) then
            return false, "You are not in a safe zone!"
        end

        local success, amount = plot:SellFish(index)
        return success, amount
    end)

    plot:OwnerInvoked("PickupFish", function(index: number)
        Assert.IntegerPositive(index)

        if not IsPlayerSafe(player) then
            return false, "You are not in a safe zone!"
        end

        local success = plot:PickupFish(index)
        return success
    end)

    plot:OwnerInvoked("DeleteFish", function(uid: string)
        local fish = Fish.GetFromInventory(player, uid)
        if not fish then
            return false
        end

        Fish.Take(player, uid)
        return true
    end)

    plot:OwnerInvoked("OpenLuckyBlock", function(index: number): boolean
        Assert.IntegerPositive(index)
        
        local luckyBlock = plot:GetFish(index)
        if not luckyBlock then
            return false
        end

        local dir = Directory.Fish[luckyBlock.FishId]
        if not dir then
            return false
        end

        if not dir.LuckyBlockId then
            return false
        end

        local luckyBlockDir = Directory.LuckyBlocks[dir.LuckyBlockId]
        if not luckyBlockDir then
            return false
        end

        local loot = luckyBlockDir.Loot
        local resultFishId = Functions.Lottery(loot)

        if not resultFishId then
            return false
        end

        local typeChances = {
			["Normal"] = 79,
			["Shiny"] = 15,
			["Gold"] = 5,
			["Rainbow"] = 1,
		}

        local data = CreateFishData(resultFishId, Functions.Lottery(typeChances))

        if data then
            plot:DeleteFish(index)
            plot:CreateFish(data, index)
        else
            return false
        end

        -- Generate visual data for animation
        local visualData = {}
        local lastFishId = nil
        local resultType = data.Type
        
        local totalVisualData = 29
        for i = 1, totalVisualData do
            local randomFishId, randomType
            
            -- Ensure no consecutive duplicate fish IDs
            repeat
                randomFishId = Functions.Lottery(loot)
            until randomFishId ~= lastFishId
            
            -- For the last item, ensure type is different from result
            if i == totalVisualData then
                repeat
                    randomType = Functions.Lottery(typeChances)
                until randomType ~= resultType
            else
                randomType = Functions.Lottery(typeChances)
            end

            table.insert(visualData, {
                FishId = randomFishId,
                Type = randomType,
            })
            
            lastFishId = randomFishId
        end

        -- Broadcast the animation to all players (server authority)
        Network.FireAll("LuckyBlockAnimation", tostring(plot:GetId()), index, visualData)

        return true
    end)

    local boostTime = 60 * 5
    plot:OtherInvoked("PlayerBoost", function(player: Player, index: number)
        Assert.IntegerPositive(index)
        
        if player == plot:GetOwner() then
            return false
        end

        if not plot:GetFish(index) then
            return false, "They need to place a fish first!"
        end

        local boosts = plot:Session("PlayerBoosts")::{[string]: number}
        boosts[tostring(index)] = workspace:GetServerTimeNow() + boostTime
        plot:SessionSet("PlayerBoosts", boosts)
        return true
    end)

    local spawnPart = plot:GetModel():WaitForChild("Spawn")::BasePart
    local teleportCFrame = spawnPart:GetPivot() + Vector3.new(0, 3, 0) 
	task.delay(0.1, function()
		PivotPlayer(player, teleportCFrame)
	end)
    player.CharacterAdded:Connect(function(character: Model)
        task.delay(0.1, function()
            PivotPlayer(player, teleportCFrame)
        end)
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