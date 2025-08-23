--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")

local Event = require(ReplicatedStorage.Library.Modules.Event)
local FishTypes = require(ReplicatedStorage.Game.Library.Types.Fish)
local PlotTypes = require(ReplicatedStorage.Game.Library.Types.Plots)
local Directory = require(ReplicatedStorage.Game.Library.Directory)
local Saving = require(ServerScriptService.Library.Saving)
local Network = require(ServerScriptService.Library.Network)
local Functions = require(ReplicatedStorage.Library.Functions)
local Assert = require(ReplicatedStorage.Library.Assert)
local Fish = require(ServerScriptService.Game.Library.Fish)
local BadgeManager = require(ServerScriptService.Game.Library.BadgeManager)
local SharedGameSettings = require(ReplicatedStorage.Game.Library.GameSettings)
local Gamepasses = require(ServerScriptService.Library.Gamepasses)

type Fields<self> = {
	Id: number,
	Owner: Player,
	CFrame: CFrame,
	Model: Model,
	Destroyed: boolean,
	Created: number,

	Joins: {[Player]: boolean},
	OwnerInvokeHandlers: {[string]: (...any) -> (...any)},
	OtherInvokeHandlers: {[string]: (Player, ...any) -> (...any)},
	InvokeHandlers: {[string]: (Player, ...any) -> (...any)},

	SaveVariables: {[string]: any},
	SaveVariableUpdates: {[string]: any},
	SaveVariableChanged: {[string]: Event.EventInstance},
	SessionVariables: {[string]: any},
	SessionVariableUpdates: {[string]: any},
	SessionVariableChanged: {[string]: Event.EventInstance},
	LocalVariables: {[any]: any},

	Destroying: Event.EventInstance,
	Heartbeat: Event.EventInstance,
	FishAdded: Event.EventInstance,
	FishRemoved: Event.EventInstance
}

type Functions<self> = {
	IsDestroyed: (self) -> boolean,
	Destroy: (self) -> boolean,

	GetId: (self) -> number,
	GetOwner: (self) -> Player,
	GetCFrame: (self) -> CFrame,
	GetModel: (self) -> Model,

	CreateFish: (self, fish: FishTypes.data_schema, index: number) -> PlotTypes.Fish?,
	SetFish: (self, fish: PlotTypes.Fish, index: number) -> PlotTypes.Fish?,
	GetFish: (self, index: number) -> PlotTypes.Fish?,
	GetFishLevel: (self, index: number) -> number?,
	DeleteFish: (self, index: number) -> (),
	GetMoneyPerSecond: (self, index: number) -> number?,
	GetUpgradeCost: (self, index: number) -> number?,
	GetSellPrice: (self, index: number) -> number?,
	GetAllFish: (self) -> {[string]: PlotTypes.Fish},

	ClaimEarnings: (self, index: number) -> (boolean, number?),
	SellFish: (self, index: number) -> (boolean, number?),
	UpgradeFish: (self, index: number) -> boolean,
	PickupFish: (self, index: number) -> boolean,
	GetMoney: (self) -> number,
	AddMoney: (self, amount: number) -> boolean,
	CanAfford: (self, amount: number) -> boolean,
	GetMultiplier: (self) -> number,

	Join: (self, player: Player) -> boolean,
	Unjoin: (self, player: Player) -> boolean,
	IsJoined: (self, player: Player) -> boolean,
	GetJoins: (self) -> {Player},
	Broadcast: (self, packet: PlotTypes.Packet) -> (),
	OwnerInvoked: (self, name: string, callback: (...any) -> ...any) -> (),
	OtherInvoked: (self, name: string, callback: (Player, ...any) -> ...any) -> (),
	Invoked: (self, name: string, callback: (Player, ...any) -> ...any) -> (),
	Fire: (self, name: string, ...any) -> (),

	Save: (self, key: string) -> any,
	SaveSet: (self, key: string, val: any?) -> any?,
	SaveChanged: (self, key: string) -> Event.EventInstance,
	Session: (self, key: string) -> any,
	SessionSet: (self, key: string, val: any?) -> any?,
	SessionChanged: (self, key: string) -> Event.EventInstance,
	Local: (self, key: any) -> any,
	LocalSet: (self, key: any, val: any?) -> any?,

	RunHeartbeat: (self, dt: number) -> (),
}
export type Type = Fields<Type> & Functions<Type>

local prototype = {}::(Functions<Type>)

-- Forward declarations for globals used across methods
local GlobalById: {[number]: Type} = {}
local GlobalByPlayer: {[Player]: Type} = {}
local GlobalPlayerPacketQueues: {[Player]: {PlotTypes.Packet}} = {}

local FakeNil = {}
local IdCounter = 0
local Created = Event.new()
local Destroying = Event.new()

function prototype:Save(key: string)
    return Functions.DeepCopy(self.SaveVariables[key])
end

function prototype:SaveSet(key: string, val: any?)
    local oldVal = self.SaveVariables[key]

	if Functions.DeepEquals(oldVal, val) then
		return oldVal
	end

    self.SaveVariables[key] = val

	local event = self.SaveVariableChanged[key]
	if event then
		event:FireAsync(val, oldVal)
	end

	if not self.SaveVariableUpdates[key] then
		self.SaveVariableUpdates[key] = oldVal ~= nil and oldVal or FakeNil
	end

    return oldVal
end

function prototype:SaveChanged(key: string)
	local event = self.SaveVariableChanged[key]
	if not event then
		event = Event.new()
		self.SaveVariableChanged[key] = event
	end
	return event
end

function prototype:Session(key: string)
    return Functions.DeepCopy(self.SessionVariables[key])
end

function prototype:SessionSet(key: string, val: any?)
	local oldVal = self.SessionVariables[key]

	if Functions.DeepEquals(oldVal, val) then
		return oldVal
	end

	self.SessionVariables[key] = val

	local event = self.SessionVariableChanged[key]
	if event then
		event:FireAsync(val, oldVal)
	end

	if not self.SessionVariableUpdates[key] then
		self.SessionVariableUpdates[key] = oldVal ~= nil and oldVal or FakeNil
	end

	return oldVal
end

function prototype:SessionChanged(key: string)
	local event = self.SessionVariableChanged[key]
	if not event then
		event = Event.new()
		self.SessionVariableChanged[key] = event
	end
	return event
end

function prototype:Local(key: any)
    return self.LocalVariables[key]
end

function prototype:LocalSet(key: any, val: any?)
	local oldVal = self.LocalVariables[key]
	if Functions.DeepEquals(oldVal, val) then
		return oldVal
	end
	self.LocalVariables[key] = val
	return oldVal
end	

function prototype:RunHeartbeat(dt: number)
	self.Heartbeat:FireAsync(dt)

	-- Accumulate online earnings each whole second using current multiplier
	local accum = self:Local("EarningsAccumulatorTime") or 0
	accum += dt
	local wholeSeconds = 0
	while accum >= 1 do
		wholeSeconds += 1
		accum -= 1
	end
	self:LocalSet("EarningsAccumulatorTime", accum)
	if wholeSeconds > 0 then
		local fishes = self:GetAllFish()
		local multiplier = self:GetMultiplier()
		local boosts = self:Session("PlayerBoosts")::{[string]: number}
		local changed = false
		for indexStr, fish in pairs(fishes) do
			local index = tonumber(indexStr)
			if index then
				local boostedTime = boosts[tostring(index)]
				local isBoosted = boostedTime and workspace:GetServerTimeNow() < boostedTime
				local basePerSecond = self:GetMoneyPerSecond(index) or 0

				local typeMultiplier = SharedGameSettings.TypeMultipliers[fish.FishData.Type] or 1
				local fishMultiplier = (multiplier * typeMultiplier) + (isBoosted and 0.5 or 0)
				local addAmount = math.ceil(basePerSecond * fishMultiplier * wholeSeconds)

				fish.Earnings = (fish.Earnings or 0) + addAmount
				changed = true
			end
		end
		if changed then
			self:SaveSet("Fish", fishes)
		end
	end

	local saveUpdates = ComputeUpdate(self.SaveVariables, self.SaveVariableUpdates)
	local sessionUpdates = ComputeUpdate(self.SessionVariables, self.SessionVariableUpdates)
	if next(saveUpdates) or next(sessionUpdates) then
		local packet: PlotTypes.Packet = {
			PacketType = "Update",
			PlotId = self.Id,
			Data = {
				Save = saveUpdates,
				Session = sessionUpdates,
			},
		}
		self:Broadcast(packet)
	end
end

function prototype:IsDestroyed()
	return self.Destroyed
end

function prototype:Destroy()
    if self.Destroyed then
        return false
    end
    self.Destroyed = true
    -- Destroy model if present
    local model = self.Model
    if model and model.Parent then
        pcall(function()
            model:Destroy()
        end)
    end
	for _, player in pairs(self:GetJoins()) do
		self:Unjoin(player)
	end
    -- Remove from global indices
    if GlobalById and GlobalById[self.Id] == self then
        GlobalById[self.Id] = nil
    end
    if GlobalByPlayer and GlobalByPlayer[self.Owner] == self then
        GlobalByPlayer[self.Owner] = nil
    end
	-- Fire destroying signal
	self.Destroying:FireAsync(self)
	Destroying:FireAsync(self)
    return true
end

function prototype:GetId()
    return self.Id
end

function prototype:GetOwner()
    return self.Owner
end

function prototype:GetCFrame()
    return self.CFrame
end

function prototype:GetModel()
    return self.Model
end

function prototype:CreateFish(fishData: FishTypes.data_schema, index: number): PlotTypes.Fish?
    local fishes = self:GetAllFish()
	if fishes[tostring(index)] then
		return nil
	end

	local now = workspace:GetServerTimeNow()
	local fish: PlotTypes.Fish = {
		UID = fishData.UID,
		FishData = fishData,
		FishId = fishData.FishId,
		LastClaimTime = now,
		CreateTime = now,
		Earnings = 0,
		OfflineEarnings = 0,
	}
	self:SetFish(fish, index)
	return fish
end

function prototype:SetFish(fish: PlotTypes.Fish, index: number): PlotTypes.Fish?
    local fishes = self:GetAllFish()
	fishes[tostring(index)] = fish
	self.FishAdded:FireAsync(fish)
	fishes[tostring(index)] = fish
	self:SaveSet("Fish", fishes)
	return fish
end

function prototype:DeleteFish(index: number)
    local fishes = self:GetAllFish()
	if not fishes[tostring(index)] then
		return
	end
	fishes[tostring(index)] = nil
	self:SaveSet("Fish", fishes)
end

function prototype:GetFish(index: number): PlotTypes.Fish?
    local stringIndex = tostring(index)
	local fishes = self:GetAllFish()
	return fishes[stringIndex]
end

function prototype:GetFishLevel(index: number): number?
    local fish = self:GetFish(index)
    if not fish then
        return nil
    end
    return fish.FishData.Level
end

function prototype:GetMoneyPerSecond(index: number): number?
	local fish = self:GetFish(index)
	if not fish then
		return nil
	end
    local dir = Directory.Fish[fish.FishId]
    return dir.MoneyPerSecond * fish.FishData.Level
end

function prototype:GetUpgradeCost(index: number): number?
	local fish = self:GetFish(index)
	if not fish then
		return nil
	end
    local fishLevel = self:GetFishLevel(index)
	if not fishLevel then
		return nil
	end
	local nextLevel = fishLevel + 1
	if nextLevel > SharedGameSettings.MaxLevel then
		return nil
	end

    local dir = Directory.Fish[fish.FishId]
	return dir.BaseUpgradeCost * (1.5 ^ (nextLevel - 1))
end

function prototype:GetSellPrice(index: number): number?
	local moneyPerSecond = self:GetMoneyPerSecond(index)
	if not moneyPerSecond then
		return nil
	end
    return math.ceil(moneyPerSecond * 20)
end

function prototype:GetAllFish(): {[string]: PlotTypes.Fish}
	local fishes = self:Save("Fish")
    if not fishes then
        return {}
    end
	return fishes
end

function prototype:ClaimEarnings(index: number): (boolean, number?)
	Assert.IntegerPositive(index)

	local fish = self:GetFish(index)
	if not fish then
		return false
	end
	local save = Saving.Get(self.Owner)
	if not save then
		return false
	end
	local giveUpgradeCost = not save.FinishedTutorial and not save.TutorialClaim
	local total = (fish.Earnings or 0) + (fish.OfflineEarnings or 0)

	if giveUpgradeCost then
		local upgradeCost = self:GetUpgradeCost(index)
		if upgradeCost then
			total = math.max(total, upgradeCost)

			save.TutorialClaim = true
		end
	end

	local payout = math.floor(total)
	if payout <= 0 then
		return false
	end
	fish.Earnings = math.max(0, total - payout)
	fish.OfflineEarnings = 0
	fish.LastClaimTime = workspace:GetServerTimeNow()
	self:SetFish(fish, index)
	self:AddMoney(payout)
	return true, payout
end

function prototype:SellFish(index: number)
	Assert.IntegerPositive(index)

	local sellPrice = self:GetSellPrice(index)
	if not sellPrice then
		return false
	end
    self:ClaimEarnings(index)
	self:AddMoney(sellPrice)
    self:DeleteFish(index)
	return true, sellPrice
end

function prototype:UpgradeFish(index: number)
	Assert.IntegerPositive(index)

	local fish = self:GetFish(index)
	if not fish then
		return false
	end

	local dir = Directory.Fish[fish.FishId]
	if not dir then
		return false
	end

	local cost = self:GetUpgradeCost(index)
	if not cost then
		return false
	end	

	if not self:CanAfford(cost) then
		return false
	end

	fish.FishData.Level = fish.FishData.Level + 1
	self:SetFish(fish, index)
	self:AddMoney(-cost)
	return true
end

function prototype:PickupFish(index: number)
    local invLimit = self:Save("InventorySize")::number?
    local saveData = Saving.Get(self.Owner)
    if not saveData or not saveData.Inventory or not saveData.PlotSave.Variables.InventorySize then
        return false
    end
    local invCount = #(saveData.Inventory :: {any})
    if invCount >= (invLimit :: number) then
        return false
    end
    local fish = self:GetFish(index)
    if not fish then
        return false
    end
    self:DeleteFish(index)
	local data = Fish.Give(self.Owner, fish.FishData)
	if data then
		Fish.ForceHoldFish(self.Owner, data)
	end
	return true
end

function prototype:GetMoney(): number
    return self:Save("Money") or 0
end

function prototype:AddMoney(amount: number)
	amount = math.ceil(amount)
	Assert.Integer(amount)

    local money = math.max(0, (self:Save("Money") or 0) + amount)
    self:SaveSet("Money", money)

	task.spawn(function()
		BadgeManager.GiveMoneyBadge(self.Owner, money)
	end)

	return true
end

function prototype:CanAfford(amount: number): boolean
	Assert.Number(amount)
	return self:GetMoney() >= amount
end

function prototype:GetMultiplier(): number
    local multiplier = 1
	local friendBoost = self:Session("FriendBoost") or 0
	local paidIndex = self:Save("PaidIndex") or 0
	local paidMultiplier = 0.5 * paidIndex

	local ownsGamepass = Gamepasses.Owns(self.Owner, "Double Money")
	if ownsGamepass then
		multiplier = multiplier + 1
	end

	multiplier = multiplier + (Functions.Round(friendBoost / 100, 1) + paidMultiplier)
	return multiplier
end

function prototype:Join(player: Player): boolean
	if self:IsDestroyed() then
		return false
	end
	if self:IsJoined(player) then
		return false
	end
	self.Joins[player] = true
	local packet: PlotTypes.Packet = {
		PacketType = "Join",
		PlotId = self.Id,
		Data = {
			Owner = self.Owner,
			CFrame = self.CFrame,
			Model = self.Model,
			SaveVariables = self.SaveVariables,
			SessionVariables = self.SessionVariables,
		}
	}
	SendPacket(player, packet)
	return true
end

function prototype:Unjoin(player: Player): boolean
	if not self:IsJoined(player) then
		return false
	end
	self.Joins[player] = nil
	local packet: PlotTypes.Packet = {
		PacketType = "Leave",
		PlotId = self:GetId(),
		Data = {
			Owner = self:GetOwner(),
		}
	}
	SendPacket(player, packet)
	return true
end

function prototype:IsJoined(player: Player): boolean
	return self.Joins[player] ~= nil
end

function prototype:GetJoins(): {Player}
	return Functions.Keys(self.Joins)
end

function prototype:Broadcast(packet: PlotTypes.Packet)
	for _, player in pairs(self:GetJoins()) do
		SendPacket(player, packet)
	end
end

function prototype:OwnerInvoked(name: string, callback: (...any) -> ...any)
	self.OwnerInvokeHandlers[name] = callback
end

function prototype:OtherInvoked(name: string, callback: (Player, ...any) -> ...any)
	self.OtherInvokeHandlers[name] = callback
end

function prototype:Invoked(name: string, callback: (Player, ...any) -> ...any)
	self.InvokeHandlers[name] = callback
end

function prototype:Fire(name: string, data: any)
	SendPacket(self.Owner, {
		PacketType = name,
		PlotId = self.Id,
		Data = data
	})
end

local Metatable = table.freeze({ __index = table.freeze(prototype) })

local module = {}

module.Created = Created

local defaultSessionVariables = {
	FriendBoost = 0,
	PlayerBoosts = {},
}

function module.new(owner: Player, blueprint: Model, cFrame: CFrame): Type
	local save = Saving.Get(owner)
	assert(save, "NoSave")
	local plotSave = save.PlotSave

	local id = IdCounter + 1
	IdCounter = id

	local model = blueprint:Clone()
	model.ModelStreamingMode = Enum.ModelStreamingMode.Persistent
	model.Name = tostring(id)
	model:PivotTo(cFrame)
	model.Parent = workspace:WaitForChild("__THINGS"):WaitForChild("Plots")

	-- Instance
	local self: Fields<Type> = {
		Id = id,
		Owner = owner,
		CFrame = cFrame,
		Model = model,
		Destroyed = false,
		Created = workspace:GetServerTimeNow(),

		Joins = {},
		OwnerInvokeHandlers = {},
		OtherInvokeHandlers = {},
		InvokeHandlers = {},

		SaveVariables = plotSave.Variables,
		SaveVariableUpdates = {},
		SaveVariableChanged = {},
		SessionVariables = Functions.DeepCopy(defaultSessionVariables),
		SessionVariableUpdates = {},
		SessionVariableChanged = {},
		LocalVariables = {},

		Destroying = Event.new(),
		Heartbeat = Event.new(),
		FishAdded = Event.new(),
		FishRemoved = Event.new()
	}
	
	local self: Type = setmetatable(self::any, Metatable)

	GlobalById[id] = self
	GlobalByPlayer[owner] = self
	
	-- Compute offline earnings based on LastLogout (if available)
	local lastLogout = save.LastLogout
	if lastLogout then
		local nowTime = workspace:GetServerTimeNow()
		local offlineSeconds = math.max(0, nowTime - lastLogout)
		if offlineSeconds > 0 then
			local fishes = self:GetAllFish()
			local changed = false
			for _, fish in pairs(fishes) do
				local dir = Directory.Fish[fish.FishId]
				if dir then
					local basePerSecond = dir.MoneyPerSecond * (fish.FishData.Level or 1)
					fish.OfflineEarnings = math.max(0, (fish.OfflineEarnings or 0) + math.floor(basePerSecond * offlineSeconds))
					changed = true
				end
			end
			if changed then
				self:SaveSet("Fish", fishes)
			end
		end
		save.LastLogout = nil
	end
	
	Created:FireAsync(self)

	for _, player in ipairs(game.Players:GetPlayers()) do 
		self:Join(player)
	end
	
	return self
end

function SendPacket(player: Player, packet: PlotTypes.Packet)
	assert(typeof(player) == "Instance" and player:IsA("Player"))
	if not player.Parent then
		return
	end
	local q = GlobalPlayerPacketQueues[player]
	if not q then
		q = {}
		GlobalPlayerPacketQueues[player] = q
	end
	table.insert(q, packet)
end

function DispatchPackets()
	for player, q in pairs(GlobalPlayerPacketQueues) do
		if not player.Parent then
			GlobalPlayerPacketQueues[player] = nil
			continue
		end
		if not player:GetAttribute("Loaded") then
			continue
		end
		if next(q) then
			Network.Fire(player, "Plots", q)
			table.clear(q)
		end
	end
end

function ComputeUpdate(
	currents: {[string]: any},
	originals: {[string]: any}
): {{any}}
	local results = {}
	for key, prevVal in pairs(originals) do
		local prevVal = if prevVal ~= FakeNil then prevVal else nil
		local val = currents[key]
		if not Functions.DeepEquals(prevVal, val) then
			table.insert(results, {key,val})
		end
	end
	table.clear(originals)
	return results
end

function module.GetByPlayer(player: Player)
	return GlobalByPlayer[player]
end

function module.GetById(id: number)
	return GlobalById[id]
end

function module.GetAll()
	return Functions.Values(GlobalById)
end

RunService.Heartbeat:Connect(function(deltaTime)
	-- Heartbeat
	for id, inst in pairs(GlobalById) do
		if not inst:IsDestroyed() then
			pcall(function()
				inst:RunHeartbeat(deltaTime)
			end)
		end
		if inst:IsDestroyed() then
			GlobalById[id] = nil
		end
	end
	-- Packets
	DispatchPackets()
end)

function PlayerRemoving(player: Player)
	local inst = module.GetByPlayer(player)
	if inst then
		inst:Destroy()
	end
	for _, otherIsnt in pairs(GlobalByPlayer) do
		otherIsnt:Unjoin(player)
	end
	GlobalPlayerPacketQueues[player] = nil
end
Players.PlayerRemoving:Connect(PlayerRemoving)

Saving.SaveAdded:Connect(function(player) 
	for _, inst in pairs(GlobalById) do 
		inst:Join(player)
	end
end)

Network.Invoked("Plots_Invoke", function(player, id: number, name: string, ...: any): (...any)
	Assert.IntegerPositive(id)
	Assert.String(name)

	local inst = module.GetById(id)
	if not inst or not inst:IsJoined(player) then
		return
	end
	local globalHandler = inst.InvokeHandlers[name]
	if globalHandler then 
		return globalHandler(player, ...)
	end
	if inst:GetOwner() == player then
		local handler = inst.OwnerInvokeHandlers[name]
		if not handler then
			error(`UnhandledOwnerInvoke: {name}`)
		end
		return handler(...)
	else
		local handler = inst.OtherInvokeHandlers[name]
		if not handler then
			error(`UnhandledOtherInvoke: {name}`)
		end
		return handler(player, ...)
	end
end)

Saving.SaveRemoving:Connect(function(player, save)
	save.LastLogout = workspace:GetServerTimeNow()
end)

module.Prototype = prototype

return module