-- src/planner.lua
return function(State, Match)
    local PoolGeometry = State.PoolGeometry
    local PoolPhysics  = State.PoolPhysics
    local PoolRules    = State.PoolRules
    local PoolStepper  = State.PoolStepper
    local Config       = State.Config
    local CUEBALL      = State.CUEBALL
    local EIGHTBALL    = State.EIGHTBALL
    local BALL_DIAM    = State.BALL_DIAM
    local BALL_RAD     = State.BALL_RAD
    local POCKETS      = State.POCKETS

    local Planner = {}

    function Planner.pathClear(sim, from, to, skip1, skip2)
        local d = to - from
        local len = d.Magnitude
        if len < 0.001 then return true end
        local dir = d / len
        local thresh = BALL_DIAM * 0.95
        for _, n in sim.Order do
            local b = sim.Balls[n]
            if b and not b.Pocketed and n ~= skip1 and n ~= skip2 then
                local r = b.Position - from
                local along = r:Dot(dir)
                if along > 0 and along < len then
                    if math.abs(r.X * dir.Y - r.Y * dir.X) < thresh then
                        return false
                    end
                end
            end
        end
        return true
    end

    function Planner.legalTargets(mc)
        local sim = mc.Simulation
        local t = {}

        if Match.isNineBall(mc) then
            local lowest = PoolRules.LowestBall(sim)
            if lowest and sim.Balls[lowest] and not sim.Balls[lowest].Pocketed then
                table.insert(t, lowest)
            end
        else
            for _, n in sim.Order do
                local b = sim.Balls[n]
                if b and not b.Pocketed and n ~= CUEBALL then
                    if PoolRules.IsLegalFirstContact(mc.Rules, sim, n) then
                        table.insert(t, n)
                    end
                end
            end
        end
        return t
    end

    function Planner.normalizePocketId(value)
        if type(value) == "table" then
            value = value.Id or value.id or value.PocketId or value.Pocket
        end
        for _, pocket in POCKETS do
            if value == pocket.Id or tostring(value) == tostring(pocket.Id) then
                return pocket.Id
            end
        end
        return nil
    end

    function Planner.requiredEightPocket(mc)
        local fieldNames = {
            "RequiredEightPocket", "EightBallPocketId", "EightPocketId",
            "RequiredPocket", "CalledPocket", "CallPocket", "TargetPocket",
        }
        local sources = {}
        if type(mc.Rules) == "table" then table.insert(sources, mc.Rules) end
        local md = Match.matchData(mc)
        if type(md) == "table" then table.insert(sources, md) end
        local replicaData = mc.Replica and mc.Replica.Data
        if type(replicaData) == "table" then table.insert(sources, replicaData) end
        for _, source in sources do
            if type(source) == "table" then
                for _, key in fieldNames do
                    local pocketId = Planner.normalizePocketId(source[key])
                    if pocketId ~= nil then return pocketId end
                end
            end
        end

        for _, functionName in {"GetRequiredEightPocket", "GetEightBallPocket", "GetCalledPocket"} do
            local ruleFunction = PoolRules[functionName]
            if type(ruleFunction) == "function" then
                local ok, value = pcall(ruleFunction, mc.Rules, mc.Simulation, mc.Seat)
                if ok then
                    local pocketId = Planner.normalizePocketId(value)
                    if pocketId ~= nil then return pocketId end
                end
            end
        end
        return nil
    end

    function Planner.pocketForBall(sim, ballNumber)
        local ball = sim.Balls[ballNumber]
        if not ball then return nil end

        for _, key in {"PocketId", "PocketID", "Pocket", "SunkPocket"} do
            local pocketId = Planner.normalizePocketId(ball[key])
            if pocketId ~= nil then return pocketId end
        end

        for _, event in sim.Events do
            local kind = string.lower(tostring(event.Kind or ""))
            if string.find(kind, "pocket", 1, true) or string.find(kind, "pot", 1, true) then
                local eventBall = event.BallNumber or event.BallId or event.Number
                if event.Ball ~= nil then
                    if type(event.Ball) == "number" then
                        eventBall = event.Ball
                    elseif type(event.Ball) == "table" then
                        eventBall = event.Ball.Number or event.Ball.Id or event.Ball.BallNumber
                    end
                end
                if eventBall == ballNumber then
                    for _, key in {"PocketId", "PocketID", "Pocket", "PocketNumber", "PocketIndex"} do
                        local pocketId = Planner.normalizePocketId(event[key])
                        if pocketId ~= nil then return pocketId end
                    end
                end
            end
        end

        if ball.Pocketed and ball.Position then
            local nearestId, nearestDistance = nil, math.huge
            for _, pocket in POCKETS do
                local distance = (ball.Position - pocket.MouthCentre).Magnitude
                if distance < nearestDistance then
                    nearestId, nearestDistance = pocket.Id, distance
                end
            end
            if nearestDistance <= BALL_DIAM * 3 then return nearestId end
        end
        return nil
    end

    function Planner.evalShot(mc, dir, power, spin, targetNumber)
        local sim   = mc.Simulation
        local rules = mc.Rules
        local g     = Match.myGroup(mc)
        local trial = PoolPhysics.Clone(sim)
        PoolPhysics.Shoot(trial, dir, power, spin or Vector2.zero)
        PoolStepper.RunToSettle(trial)
        local firstHit = nil
        for _, ev in trial.Events do
            if ev.Kind == "BallHit" then
                if ev.Ball == CUEBALL and ev.Other then firstHit = ev.Other; break end
                if ev.Other == CUEBALL and ev.Ball then firstHit = ev.Ball;  break end
            end
        end
        local legal      = firstHit ~= nil and PoolRules.IsLegalFirstContact(rules, sim, firstHit)
        local ownPots    = 0
        local oppPots    = 0
        local scratched  = false
        local eightPot   = false
        for _, n in trial.Order do
            local ob = sim.Balls[n]
            local tb = trial.Balls[n]
            if ob and tb and tb.Pocketed and not ob.Pocketed then
                if n == CUEBALL then
                    scratched = true
                elseif n == EIGHTBALL then
                    eightPot = true
                else
                    local bg = Match.ballGroup(n)
                    if g == nil or bg == g then ownPots += 1
                    else oppPots += 1 end
                end
            end
        end
        local cueRest = trial.Balls[CUEBALL]
        local restPos = (cueRest and not cueRest.Pocketed) and cueRest.Position or nil
        return {
            FirstHit  = firstHit,
            Legal     = legal,
            OwnPots   = ownPots,
            OppPots   = oppPots,
            Scratched = scratched,
            EightPot  = eightPot,
            EightPocketId = eightPot and Planner.pocketForBall(trial, EIGHTBALL) or nil,
            TargetPotted = targetNumber ~= nil
                and trial.Balls[targetNumber] ~= nil
                and trial.Balls[targetNumber].Pocketed
                and not sim.Balls[targetNumber].Pocketed,
            TargetPocketId = targetNumber ~= nil
                and trial.Balls[targetNumber]
                and trial.Balls[targetNumber].Pocketed
                and Planner.pocketForBall(trial, targetNumber)
                or nil,
            RestPos   = restPos,
            Trial     = trial,
        }
    end

    function Planner.scoreResult(mc, res, cand, power)
        local sc = 0
        if not res.FirstHit then return -1000 end
        if not res.Legal    then return -800  end
        if cand then
            if res.TargetPotted then
                sc += 300
                if res.TargetPocketId ~= nil
                    and tostring(res.TargetPocketId) == tostring(cand.PocketId) then
                    sc += 80
                elseif PoolRules.NeedsCall(mc.Rules, mc.Simulation) then
                    return -500
                end
            else
                sc -= 50
            end
        end
        sc += res.OwnPots * 250
        sc -= res.OppPots * 300
        if res.Scratched then sc -= 600 end
        if res.EightPot then
            if Match.isNineBall(mc) then
                sc += (res.Scratched and -800 or 400)
            else
                local calledPocketMatches = cand
                    and res.EightPocketId ~= nil
                    and tostring(res.EightPocketId) == tostring(cand.PocketId)
                local callRequired = PoolRules.NeedsCall(mc.Rules, mc.Simulation)
                local validEightPot = Match.onEight(mc) and not res.Scratched
                    and (not callRequired or calledPocketMatches)
                sc += validEightPot and 600 or -800
            end
        end
        if cand then
            sc += (1 - math.clamp(cand.Distance / 800, 0, 1)) * 50
            if not cand.Clear then sc -= 100 end
        end
        return sc
    end

    function Planner.planShot(mc)
        local sim = mc.Simulation
        local cb = sim.Balls[CUEBALL]
        if not cb or cb.Pocketed then return nil end

        local cuePos = cb.Position
        local targets = Planner.legalTargets(mc)
        local requiredPocket = Match.onEight(mc) and Planner.requiredEightPocket(mc) or nil
        if #targets == 0 then return nil end

        if mc.Rules.Phase == "Break" then
            local headBall, headDist = nil, math.huge
            for _, n in sim.Order do
                local b = sim.Balls[n]
                if b and not b.Pocketed and n ~= CUEBALL then
                    local d = (b.Position - cuePos).Magnitude
                    if d < headDist then
                        headBall, headDist = n, d
                    end
                end
            end
            if headBall then
                local pos = sim.Balls[headBall].Position
                return {
                    Target = headBall,
                    PocketId = nil,
                    Direction = (pos - cuePos).Unit,
                    Power = 0.95,
                    Spin = Vector2.zero,
                    Quality = 1,
                    Score = 100,
                    OwnPots = 0,
                    IsBreak = true,
                    IsBankShot = false,
                }
            end
        end

        local cands = {}
        local bankCands = {}
        local halfW = math.max(0.1, PoolGeometry.HalfWidth - BALL_RAD)
        local halfH = math.max(0.1, PoolGeometry.HalfHeight - BALL_RAD)
        local railMargin = BALL_DIAM * 1.65
        local rails = {
            { Name = "Left",   Axis = "X", Value = -halfW },
            { Name = "Right",  Axis = "X", Value =  halfW },
            { Name = "Bottom", Axis = "Y", Value = -halfH },
            { Name = "Top",    Axis = "Y", Value =  halfH },
        }

        for _, tn in targets do
            local targetBall = sim.Balls[tn]
            if targetBall and not targetBall.Pocketed then
                local tp = targetBall.Position

                for _, pk in POCKETS do
                    if tn == EIGHTBALL and requiredPocket ~= nil
                        and tostring(pk.Id) ~= tostring(requiredPocket) then
                        continue
                    end

                    local toP = pk.MouthCentre - tp
                    if toP.Magnitude > 0.001 then
                        local objectDir = toP.Unit
                        local ghost = tp - objectDir * BALL_DIAM
                        local toG = ghost - cuePos
                        if toG.Magnitude > BALL_DIAM * 0.4 then
                            local q = toG.Unit:Dot(objectDir)
                            if q > 0.05 then
                                local cueClear = Planner.pathClear(sim, cuePos, ghost, CUEBALL, tn)
                                local objectClear = Planner.pathClear(sim, tp, pk.MouthCentre, CUEBALL, tn)
                                local clear = cueClear and objectClear
                                table.insert(cands, {
                                    Target = tn,
                                    PocketId = pk.Id,
                                    Direction = toG.Unit,
                                    Quality = q,
                                    Distance = toG.Magnitude + toP.Magnitude,
                                    Clear = clear,
                                    Object = tp,
                                    IsBankShot = false,
                                })
                            end
                        end
                    end
                end
            end
        end

        local powers = { 0.35, 0.50, 0.65, 0.80, 0.95 }
        local best, bestScore = nil, -math.huge

        for _, c in cands do
            for _, pw in powers do
                local res = Planner.evalShot(mc, c.Direction, pw, Vector2.zero, c.Target)
                if Match.onEight(mc) and c.Target == EIGHTBALL and res.EightPot
                    and PoolRules.NeedsCall(mc.Rules, mc.Simulation)
                    and (res.EightPocketId == nil or tostring(res.EightPocketId) ~= tostring(c.PocketId)) then
                    continue
                end

                local score = Planner.scoreResult(mc, res, c, pw)
                if score > bestScore then
                    bestScore = score
                    best = {
                        Target = c.Target,
                        PocketId = c.PocketId,
                        Direction = c.Direction,
                        Power = pw,
                        Spin = Vector2.zero,
                        Quality = c.Quality,
                        Distance = c.Distance,
                        Clear = c.Clear,
                        Score = score,
                        OwnPots = res.OwnPots,
                        Scratched = res.Scratched,
                        EightPot = res.EightPot,
                        EightPocketId = res.EightPocketId,
                        Legal = res.Legal,
                        TargetPotted = res.TargetPotted,
                        IsBankShot = false,
                    }
                end
            end
        end

        if not best or bestScore < 0 then
            for _, tn in targets do
                local ball = sim.Balls[tn]
                if ball and not ball.Pocketed then
                    for _, pk in POCKETS do
                        local toP = (pk.MouthCentre - ball.Position).Unit
                        local ghost = ball.Position - toP * BALL_DIAM
                        local toG = (ghost - cuePos)
                        if toG.Magnitude > 0.01 then
                            return {
                                Target = tn,
                                PocketId = pk.Id,
                                Direction = toG.Unit,
                                Power = 0.5,
                                Spin = Vector2.zero,
                                Quality = 0.1,
                                Score = -1,
                                OwnPots = 0,
                                Fallback = true,
                                IsBankShot = false,
                            }
                        end
                    end
                end
            end
        end

        return best
    end

    function Planner.planPlacement(mc)
        local sim   = mc.Simulation
        local rules = mc.Rules
        local bestP = Vector2.new(0, 0)
        local bestS = -math.huge
        local hw = PoolGeometry.HalfWidth  - BALL_RAD * 2
        local hh = PoolGeometry.HalfHeight - BALL_RAD * 2
        local step = BALL_DIAM * 2
        for x = -hw, hw, step do
            for y = -hh, hh, step do
                local pos = Vector2.new(x, y)
                local cl  = PoolRules.ClampPlacement(rules, pos)
                if (cl - pos).Magnitude < 0.01 and PoolGeometry.IsInsidePlayArea(pos, BALL_RAD) then
                    local blocked = false
                    for _, n in sim.Order do
                        local b = sim.Balls[n]
                        if b and not b.Pocketed and n ~= CUEBALL and (b.Position - pos).Magnitude < BALL_DIAM * 1.05 then
                            blocked = true; break
                        end
                    end
                    if not blocked then
                        local sc = 0
                        for _, n in sim.Order do
                            local b = sim.Balls[n]
                            if b and not b.Pocketed and n ~= CUEBALL
                                and PoolRules.IsLegalFirstContact(rules, sim, n) then
                                for _, pk in POCKETS do
                                    local tp = pk.MouthCentre - b.Position
                                    if tp.Magnitude > 0.001 then
                                        local gh = b.Position - tp.Unit * BALL_DIAM
                                        local tg = gh - pos
                                        if tg.Magnitude > BALL_DIAM then
                                            local q = tg.Unit:Dot(tp.Unit)
                                            if q > 0.1 and Planner.pathClear(sim, pos, gh, CUEBALL, n) then
                                                sc = math.max(sc, q)
                                            end
                                        end
                                    end
                                end
                            end
                        end
                        if sc > bestS then bestS = sc; bestP = pos end
                    end
                end
            end
        end
        return bestP
    end

    return Planner
end
