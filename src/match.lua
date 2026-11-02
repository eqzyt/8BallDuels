-- src/match.lua
return function(State)
    local PoolRules = State.PoolRules
    local CUEBALL   = State.CUEBALL
    local EIGHTBALL = State.EIGHTBALL

    local Match = {}

    function Match.findMC()
        local ok, mc = pcall(function()
            for _, obj in getgc(true) do
                if typeof(obj) == "table"
                    and rawget(obj, "Simulation")
                    and rawget(obj, "Replica")
                    and rawget(obj, "Seat")
                    and rawget(obj, "Rules")
                    and rawget(obj, "Input")
                    and rawget(obj, "Dropped") then

                    local replica = rawget(obj, "Replica")
                    local data = replica and replica.Data
                    local md = data and data.poolMatch
                    local seat = rawget(obj, "Seat")
                    local input = rawget(obj, "Input")

                    if md and md.Active and md.Phase == "Playing"
                        and type(seat) == "number" and seat > 0
                        and input and input.State ~= "GameOver" then
                        return obj
                    end
                end
            end
        end)
        return ok and mc or nil
    end

    function Match.matchData(mc)
        local d = mc.Replica and mc.Replica.Data
        return d and d.poolMatch
    end

    function Match.myTurn(mc)
        local md = Match.matchData(mc)
        if not md or md.Phase ~= "Playing" or mc.Seat <= 0 then return false end
        return md.Turn == mc.Seat
    end

    function Match.myGroup(mc)
        if mc.Seat <= 0 then return nil end
        return PoolRules.GetGroup(mc.Rules, mc.Seat)
    end

    function Match.ballGroup(n)
        if n == CUEBALL or n == EIGHTBALL then return nil end
        return n < EIGHTBALL and "Solid" or "Stripe"
    end

    function Match.onEight(mc)
        local g = Match.myGroup(mc)
        return g and PoolRules.CountRemaining(mc.Simulation, g) == 0
    end

    function Match.isNineBall(mc)
        return mc.GameType == "NineBall"
    end

    return Match
end