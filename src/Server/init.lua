--[=[
    @class ChickynoidServer
    @server

    Server namespace for the Chickynoid package.
]=]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local path = script.Parent

local Enums = require(path.Enums)
local EventType = Enums.EventType
local ServerChickynoid = require(script.ServerChickynoid)
local CharacterData = require(path.Simulation.CharacterData)
local BitBuffer = require(path.Vendor.BitBuffer)
local WeaponsModule = require(script.WeaponsServer)
local CollisionModule = require(path.Simulation.CollisionModule)
local Antilag = require(path.Server.Antilag)
local FastSignal = require(path.Vendor.FastSignal)
local ServerMods = require(script.ServerMods)
local RemoteEvent = Instance.new("RemoteEvent")
RemoteEvent.Name = "ChickynoidReplication"
RemoteEvent.Parent = ReplicatedStorage

local ChickynoidServer = {}

ChickynoidServer.playerRecords = {}
ChickynoidServer.serverStepTimer = 0
ChickynoidServer.serverTotalFrames = 0
ChickynoidServer.serverSimulationTime = 0
ChickynoidServer.framesPerSecondCounter = 0 --Purely for stats
ChickynoidServer.framesPerSecondTimer = 0 --Purely for stats
ChickynoidServer.framesPerSecond = 0 --Purely for stats
ChickynoidServer.accumulatedTime = 0 --fps

ChickynoidServer.startTime = tick()
ChickynoidServer.slots = {}
ChickynoidServer.collisionRootFolder = nil

ChickynoidServer.playerSize = Vector3.new(2, 5, 2)

--[=[
	@interface ServerConfig
	@within ChickynoidServer
	.maxPlayers number -- Theoretical max, use a byte for player id
	.fpsMode FpsMode
	.serverHz number
	Server config for Chickynoid.
]=]
ChickynoidServer.config = {
    maxPlayers = 255,
    fpsMode = Enums.FpsMode.Hybrid,
    serverHz = 20,
}

--API
ChickynoidServer.OnPlayerSpawn = FastSignal.new()
ChickynoidServer.OnPlayerDespawn = FastSignal.new()
ChickynoidServer.OnBeforePlayerSpawn = FastSignal.new()
ChickynoidServer.OnPlayerConnected = FastSignal.new()

ChickynoidServer.flags = {}
ChickynoidServer.flags.DEBUG_ANTILAG = true

--[=[
	Creates connections so that Chickynoid can run on the server.
]=]
function ChickynoidServer:Setup()
    self.worldRoot = self:GetDoNotReplicate()

    Players.PlayerAdded:Connect(function(player)
        self:PlayerConnected(player)
    end)

    --If there are any players already connected, push them through the connection function
    for _, player in pairs(game.Players:GetPlayers()) do
        self:PlayerConnected(player)
    end

    Players.PlayerRemoving:Connect(function(player)
        self:PlayerDisconnected(player.UserId)
    end)

    RunService.Heartbeat:Connect(function(deltaTime)
        self:RobloxHeartbeat(deltaTime)
    end)

    RunService.Stepped:Connect(function(_, deltaTime)
        self:RobloxPhysicsStep(deltaTime)
    end)

    RemoteEvent.OnServerEvent:Connect(function(player: Player, event)
        local playerRecord = self:GetPlayerByUserId(player.UserId)

        if playerRecord then
            if event.t == EventType.ResetConnection then
                print("Player requested a network reset")
                playerRecord:ResetConnection()
                return
            end

            if playerRecord.chickynoid then
                playerRecord.chickynoid:HandleEvent(self, event)
            end
        end
    end)

    WeaponsModule:Setup(self)

    Antilag:Setup(self)

    --Load the mods
    local modules = ServerMods:GetMods("servermods")
    for _, mod in pairs(modules) do
        mod:Setup(self)
		-- print("Loaded", _)
    end
end

function ChickynoidServer:PlayerConnected(player)
    local playerRecord = self:AddConnection(player.UserId, player)

    --Spawn the gui
    for _, child in pairs(game.StarterGui:GetChildren()) do
        local clone = child:Clone() :: ScreenGui
        if clone:IsA("ScreenGui") then
            clone.ResetOnSpawn = false
        end
        clone.Parent = playerRecord.player.PlayerGui
    end

end

function ChickynoidServer:AssignSlot(playerRecord)
    for j = 1, self.config.maxPlayers do
        if self.slots[j] == nil then
            self.slots[j] = playerRecord
            playerRecord.slot = j
            return true
        end
    end
    warn("Slot not found!")
    return false
end

function ChickynoidServer:AddConnection(userId, player)
    if self.playerRecords[userId] ~= nil then
        warn("Player was already connected.", userId)
        self:PlayerDisconnected(userId)
    end

    --Create the players server connection record
    local playerRecord = {}
    self.playerRecords[userId] = playerRecord

    playerRecord.userId = userId

    playerRecord.previousCharacterData = {}
    playerRecord.chickynoid = nil
    playerRecord.frame = 0
    playerRecord.firstSnapshot = false
    

    playerRecord.allowedToSpawn = true
    playerRecord.respawnDelay = 3
    playerRecord.respawnTime = tick() + playerRecord.respawnDelay

    playerRecord.OnBeforePlayerSpawn = FastSignal.new()

    playerRecord.characterMod = "HumanoidChickynoid"

    self:AssignSlot(playerRecord)

    playerRecord.player = player
    if playerRecord.player ~= nil then
        playerRecord.dummy = false
        playerRecord.name = player.name
    else
        --Is a bot
        playerRecord.dummy = true
    end

    -- selene: allow(shadowing)
    function playerRecord:SendEventToClient(event)
        if playerRecord.player then
            RemoteEvent:FireClient(playerRecord.player, event)
        end
    end

    -- selene: allow(shadowing)
    function playerRecord:SendEventToClients(event)
        if playerRecord.player then
            RemoteEvent:FireAllClients(event)
        end
    end

    -- selene: allow(shadowing)
    function playerRecord:SendEventToOtherClients(event)
        for _, record in pairs(self.playerRecords) do
            if record == playerRecord then
                continue
            end
            RemoteEvent:FireClient(record.player, event)
        end
    end

    -- selene: allow(shadowing)
    function playerRecord:SendCollisionData()
       
		if ChickynoidServer.collisionRootFolder ~= nil then
			local event = {}
			event.t = Enums.EventType.CollisionData
            event.playerSize = ChickynoidServer.playerSize
			event.data = ChickynoidServer.collisionRootFolder
			self:SendEventToClient(event)
        end
    end

    -- selene: allow(shadowing)
    function playerRecord:ResetConnection()
        self.firstSnapshot = false
    end

    -- selene: allow(shadowing)
    function playerRecord:Despawn()
        if self.chickynoid then
            ChickynoidServer.OnPlayerDespawn:Fire(self)

            print("Despawned!")
            self.chickynoid:Destroy()
            self.chickynoid = nil
            self.respawnTime = tick() + self.respawnDelay

            local event = { t = EventType.ChickynoidRemoving }
            playerRecord:SendEventToClient(event)
        end
    end

    function playerRecord:SetCharacterMod(characterModName)
        self.characterMod = characterModName
    end

    -- selene: allow(shadowing)
    function playerRecord:Spawn()
        self:Despawn()

        local chickynoid = ServerChickynoid.new(playerRecord)
        self.chickynoid = chickynoid
        chickynoid.playerRecord = self

        local list = {}
        for _, obj: SpawnLocation in pairs(workspace:GetDescendants()) do
            if obj:IsA("SpawnLocation") and obj.Enabled == true then
                table.insert(list, obj)
            end
        end

        if #list > 0 then
            local spawn = list[math.random(1, #list)]
            self.chickynoid:SetPosition(Vector3.new(spawn.Position.x, spawn.Position.y + 5, spawn.Position.z))
        else
            self.chickynoid:SetPosition(Vector3.new(0, 10, 0))
        end

        self.OnBeforePlayerSpawn:Fire()
        ChickynoidServer.OnBeforePlayerSpawn:Fire(self, playerRecord)

        chickynoid:SpawnChickynoid()

        ChickynoidServer.OnPlayerSpawn:Fire(self, playerRecord)
        return self.chickynoid
    end
    
    self.OnPlayerConnected:Fire(self, playerRecord)
    --Connect!
    WeaponsModule:OnPlayerConnected(self, playerRecord)

    --Tell everyone
    --TODO: Replace with a dirty flag?
    for _, record in pairs(self.playerRecords) do
        self:SendWorldstate(record)
    end
	
	playerRecord:SendCollisionData()
    playerRecord:ResetConnection()

    return playerRecord
end

function ChickynoidServer:SendEventToClients(event)
    RemoteEvent:FireAllClients(event)
end

function ChickynoidServer:SendWorldstate(playerRecord)
    local event = {}
    event.t = Enums.EventType.WorldState
    event.worldState = {}
    event.worldState.flags = self.flags

    event.worldState.players = {}
    for _, data in pairs(self.playerRecords) do
        local info = {}
        info.name = data.name
        info.userId = data.userId

        event.worldState.players[data.slot] = info
    end

    event.worldState.serverHz = self.config.serverHz
    event.worldState.fpsMode = self.config.fpsMode

    playerRecord:SendEventToClient(event)
end

function ChickynoidServer:PlayerDisconnected(userId)
    local playerRecord = self.playerRecords[userId]

    if playerRecord then
        print("Player disconnected")

        playerRecord:Despawn()

        self.playerRecords[userId] = nil

        --Clear this out
        for _, record in pairs(self.playerRecords) do
            record.previousCharacterData[userId] = nil
        end

        self.slots[playerRecord.slot] = nil
    end

    --Tell everyone
    for _, data in pairs(self.playerRecords) do
        self:SendWorldstate(data)
    end
end

function ChickynoidServer:GetPlayerByUserId(userId)
    return self.playerRecords[userId]
end

function ChickynoidServer:GetPlayers()
    return self.playerRecords
end

function ChickynoidServer:RobloxHeartbeat(deltaTime)
    if self.accumulatedTime > 0.5 then
        self.accumulatedTime = 0
    end

    self.accumulatedTime += deltaTime
    local frac = 1 / 60
    while self.accumulatedTime > 0 do
        self.accumulatedTime -= frac
        self:Think(frac)
    end

    --Discard accumulated time if its a tiny fraction
    local errorSize = 0.001 --1ms
    if self.accumulatedTime > -errorSize then
        self.accumulatedTime = 0
    end
end

function ChickynoidServer:RobloxPhysicsStep(deltaTime)
    for _, playerRecord in pairs(self.playerRecords) do
        if playerRecord.chickynoid then
            playerRecord.chickynoid:RobloxPhysicsStep(self, deltaTime)
        end
    end
end

function ChickynoidServer:GetDoNotReplicate()
    local camera = game.Workspace:FindFirstChild("DoNotReplicate")
    if camera == nil then
        camera = Instance.new("Camera")
        camera.Name = "DoNotReplicate"
        camera.Parent = game.Workspace
    end
    return camera
end

function ChickynoidServer:Think(deltaTime)
    self.framesPerSecondCounter += 1
    self.framesPerSecondTimer += deltaTime
    if self.framesPerSecondTimer > 1 then
        self.framesPerSecondTimer = math.fmod(self.framesPerSecondTimer, 1)
        self.framesPerSecond = self.framesPerSecondCounter
        self.framesPerSecondCounter = 0
    end

    self.serverSimulationTime = tick() - self.startTime

    --self.worldRoot = game.Workspace

    --Spawn players
    for _, playerRecord in pairs(self.playerRecords) do
        if playerRecord.chickynoid == nil and playerRecord.allowedToSpawn == true then
            if tick() > playerRecord.respawnTime then
                playerRecord:Spawn()
            end
        end
    end

    CollisionModule:UpdateDynamicParts()

    --1st stage, pump the commands
    for _, playerRecord in pairs(self.playerRecords) do
        if playerRecord.dummy == true then
            playerRecord.BotThink(deltaTime)
        end

        if playerRecord.chickynoid then
            playerRecord.chickynoid:Think(self, self.serverSimulationTime, deltaTime)

            if playerRecord.chickynoid.simulation.state.pos.y < -2000 then
                playerRecord:Despawn()
            end
        end
    end

    for _, playerRecord in pairs(self.playerRecords) do
        if playerRecord.chickynoid then
            playerRecord.chickynoid:PostThink(self)
        end
    end
    WeaponsModule:Think(self, deltaTime)

    local modules = ServerMods:GetMods("servermods")
	for _, mod in pairs(modules) do
		if (mod.Step) then
			mod:Step(self, deltaTime)
		end
    end

    -- 2nd stage: Replicate character state to the player
    self.serverStepTimer += deltaTime
    self.serverTotalFrames += 1

    local fraction = (1 / self.config.serverHz)
    if self.serverStepTimer > fraction then
        while self.serverStepTimer > fraction do -- -_-'
            self.serverStepTimer -= fraction
        end

        Antilag:WritePlayerPositions(self.serverSimulationTime)

        for userId, playerRecord in pairs(self.playerRecords) do
            if playerRecord.dummy == true then
                continue
            end

            --Send results of server move
            if playerRecord.chickynoid ~= nil then
                local event = {}
                event.t = EventType.State
                event.lastConfirmed = playerRecord.chickynoid.lastConfirmedCommand

                event.e = playerRecord.chickynoid.errorState
                event.s = self.framesPerSecond
                event.serverTime = self.serverSimulationTime
 
                event.stateDelta = playerRecord.chickynoid:WriteStateDelta()

                playerRecord:SendEventToClient(event)
                playerRecord.chickynoid.errorState = Enums.NetworkProblemState.None
            end

            --Send snapshot
            local snapshot = {}
            snapshot.t = EventType.Snapshot

            local count = 0
            for otherUserId, otherPlayerRecord in pairs(self.playerRecords) do
                if otherUserId ~= userId and otherPlayerRecord.chickynoid ~= nil then
                    count += 1
                end
            end

            local bitBuffer = BitBuffer()
            bitBuffer.writeByte(count)

            for otherUserId, otherPlayerRecord in pairs(self.playerRecords) do
                if otherUserId ~= userId then
                    if otherPlayerRecord.chickynoid == nil then
                        continue
                    end

                    --Todo: delta compress , bitwise compress, etc etc
                    bitBuffer.writeByte(otherPlayerRecord.slot)

                    if playerRecord.firstSnapshot == false then
                        --Make sure the first write is always a full packet
                        otherPlayerRecord.chickynoid.simulation.characterData:SerializeToBitBuffer(nil, bitBuffer)
                    else
                        local previousRecord = playerRecord.previousCharacterData[otherUserId]
                        otherPlayerRecord.chickynoid.simulation.characterData:SerializeToBitBuffer(
                            previousRecord,
                            bitBuffer
                        )
                    end

                    --Make a copy for delta compression against
                    local previousRecord = CharacterData.new()
                    previousRecord:CopySerialized(otherPlayerRecord.chickynoid.simulation.characterData.serialized)
                    playerRecord.previousCharacterData[otherUserId] = previousRecord
                end
            end

            snapshot.full = false
            if playerRecord.firstSnapshot == false then
                snapshot.full = true
                playerRecord.firstSnapshot = true
            end

            snapshot.b = bitBuffer.dumpString()
            snapshot.f = self.serverTotalFrames
            snapshot.serverTime = self.serverSimulationTime
            playerRecord:SendEventToClient(snapshot)
        end
    end
end

function ChickynoidServer:RecreateCollisions(rootFolder)

    self.collisionRootFolder = rootFolder
    CollisionModule:MakeWorld(self.collisionRootFolder, self.playerSize)

    for _, playerRecord in pairs(self.playerRecords) do
        playerRecord:SendCollisionData()
    end
end

return ChickynoidServer
