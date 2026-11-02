-- src/state.lua
local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService        = game:GetService("RunService")
local UserInputService  = game:GetService("UserInputService")

local Pool              = ReplicatedStorage.Libraries.GameSpecific.Pool
local PoolConstants     = require(Pool.PoolConstants)
local PoolGeometry      = require(Pool.PoolGeometry)
local PoolPhysics       = require(Pool.PoolPhysics)
local PoolRules         = require(Pool.PoolRules)
local PoolStepper       = require(Pool.PoolStepper)
local PoolMatchTypes    = require(Pool.PoolMatchTypes)
local PoolInputController = require(Pool.PoolInputController)
local PoolAI            = require(Pool:WaitForChild("PoolAI"))
local PoolAimOverlay    = require(Pool.PoolAimOverlay)
local PoolTableRenderer2D = require(Pool.PoolTableRenderer2D)
local RemoteEnums       = require(ReplicatedStorage.Libraries.Modules.RemoteSignals.RemoteEnums)
local RemoteSignals     = require(ReplicatedStorage.Libraries.Modules.RemoteSignals)

local State = {}

State.Players             = Players
State.ReplicatedStorage   = ReplicatedStorage
State.RunService          = RunService
State.UserInputService    = UserInputService
State.LocalPlayer         = Players.LocalPlayer

State.Pool                = Pool
State.PoolConstants       = PoolConstants
State.PoolGeometry        = PoolGeometry
State.PoolPhysics         = PoolPhysics
State.PoolRules           = PoolRules
State.PoolStepper         = PoolStepper
State.PoolMatchTypes      = PoolMatchTypes
State.PoolInputController = PoolInputController
State.PoolAI              = PoolAI
State.PoolAimOverlay      = PoolAimOverlay
State.PoolTableRenderer2D = PoolTableRenderer2D
State.RemoteEnums         = RemoteEnums
State.RemoteSignals       = RemoteSignals

State.CUEBALL   = PoolConstants.CueBallNumber
State.EIGHTBALL = PoolConstants.EightBallNumber
State.BALL_DIAM = PoolConstants.BallDiameter
State.BALL_RAD  = PoolConstants.BallRadius
State.POCKETS   = PoolGeometry.GetPockets()

State.Config = {
    Enabled          = false,
    ShotDelay        = 1.4,
    PowerMode        = "Auto",
    AutoBIH          = true,
    Humanize         = true,
    ActiveLines      = false,
    BankShotFallback = true,
    AimVisualSpeed   = 8.5,
    AimStyle         = "Smooth",
    AimDuration      = 0.65,
}

State.Bot = {
    MC           = nil,
    Status       = "Idle",
    LastShot     = nil,
    Pending      = false,
    Cooldown     = 0,
    Stats        = { Shots = 0, Pots = 0, Wins = 0, Losses = 0 },
    Remaining    = 0,
    Alive        = true,
}

State.Live = {
    activeSim          = nil,
    currentPower       = 0.75,
    currentSpin        = Vector2.zero,
    lastCuePos         = Vector2.zero,
    lastAimDir         = Vector2.zero,
    lastPower          = -1,
    lastSpin           = Vector2.zero,
    lastLegal          = nil,
    lastBallCount      = -1,
    forceResimulate    = true,
    activeLinesEnabled = false,
    lastOverlaySelf    = nil,
}

State.Connections = {}
State.Randomizer  = Random.new()

function State.waitForReaction()
    local base = State.Config.ShotDelay
    local variance = State.Config.Humanize and State.Randomizer:NextNumber(0.82, 1.18) or 1
    task.wait(math.clamp(base * variance, 0.25, 4))
end

return State
