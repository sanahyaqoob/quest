-- Initializing global variables to store the latest game state and game host process.
LatestGameState = LatestGameState or nil
InAction = InAction or false -- Prevents the agent from taking multiple actions at once.
Logs = Logs or {}

colors = {
    red = "\27[31m",
    green = "\27[32m",
    blue = "\27[34m",
    reset = "\27[0m",
    gray = "\27[90m"
}

function addLog(msg, text) -- Function definition commented for performance, can be used for debugging
    Logs[msg] = Logs[msg] or {}
    table.insert(Logs[msg], text)
end

-- Checks if two points are within a given range.
-- @param x1, y1: Coordinates of the first point.
-- @param x2, y2: Coordinates of the second point.
-- @param range: The maximum allowed distance between the points.
-- @return: Boolean indicating if the points are within the specified range.
function inRange(x1, y1, x2, y2, range)
    return math.abs(x1 - x2) <= range and math.abs(y1 - y2) <= range
end

function findNearestPlayer()
    local me = LatestGameState.Players[ao.id]

    local nearestPlayer = nil
    local nearestDistance = nil

    for target, state in pairs(LatestGameState.Players) do
        if target == ao.id then
            goto continue
        end

        local other = state;
        local xdiff = me.x - other.x
        local ydiff = me.y - other.y
        local distance = math.sqrt(xdiff * xdiff + ydiff * ydiff)

        if nearestPlayer == nil or nearestDistance > distance then
            nearestPlayer = other
            nearestDistance = distance
        end

        ::continue::
    end

    return nearestPlayer
end

directionMap = {}
directionMap[{ x = 0, y = 1 }] = "Up"
directionMap[{ x = 0, y = -1 }] = "Down"
directionMap[{ x = -1, y = 0 }] = "Left"
directionMap[{ x = 1, y = 0 }] = "Right"
directionMap[{ x = 1, y = 1 }] = "UpRight"
directionMap[{ x = -1, y = 1 }] = "UpLeft"
directionMap[{ x = 1, y = -1 }] = "DownRight"
directionMap[{ x = -1, y = -1 }] = "DownLeft"

function findAvoidDirection()
    local me = LatestGameState.Players[ao.id]

    local avoidDirection = { x = 0, y = 0 }
    for target, state in pairs(LatestGameState.Players) do
        if target == ao.id then
            goto continue
        end

        local otherPlayer = state
        local avoidVector = { x = me.x - otherPlayer.x, y = me.y - otherPlayer.y }
        avoidDirection.x = avoidDirection.x + avoidVector.x
        avoidDirection.y = avoidDirection.y + avoidVector.y

        ::continue::
    end
    avoidDirection = normalizeDirection(avoidDirection)

    local closestDirection = nil
    local closestDotResult = nil

    for direction, name in pairs(directionMap) do
        local normalized = normalizeDirection(direction)
        local dotResult = avoidDirection.x * normalized.x + avoidDirection.y + normalized.y

        if closestDirection == nil or closestDotResult < dotResult then
            closestDirection = name
            closestDotResult = dotResult
        end
    end

    return closestDirection
end

function findApproachDirection()
    local me = LatestGameState.Players[ao.id]

    local approachDirection = { x = 0, y = 0 }
    local otherPlayer = findNearestPlayer()
    local approachVector = { x = otherPlayer.x - me.x, y = otherPlayer.y - me.y }
    approachDirection.x = approachDirection.x + approachVector.x
    approachDirection.y = approachDirection.y + approachVector.y
    approachDirection = normalizeDirection(approachDirection)

    local closestDirection = nil
    local closestDotResult = nil

    for direction, name in pairs(directionMap) do
        local normalized = normalizeDirection(direction)
        local dotResult = approachDirection.x * normalized.x + approachDirection.y + normalized.y

        if closestDirection == nil or closestDotResult < dotResult then
            closestDirection = name
            closestDotResult = dotResult
        end
    end

    return closestDirection
end

function isPlayerInAttackRange(player)
    local me = LatestGameState.Players[ao.id]

    if inRange(me.x, me.y, player.x, player.y, 1) then
        return true;
    end

    return false;
end

function normalizeDirection(direction)
    local length = math.sqrt(direction.x * direction.x + direction.y * direction.y)
    return { x = direction.x / length, y = direction.y / length }
end

-- Advanced Movement Strategies: Dodging incoming attacks, circling opponents, and strategic positioning.
function advancedMovement()
    local me = LatestGameState.Players[ao.id]
    local nearestPlayer = findNearestPlayer()
    
    -- Check if any opponent is targeting our bot
    local isTargeted = false
    for _, player in pairs(LatestGameState.Players) do
        if player.target == ao.id then
            isTargeted = true
            break
        end
    end
    
    -- Dodge incoming attacks if targeted
    if isTargeted then
        local dodgeDirection = findAvoidDirection()
        print(colors.blue .. "Dodging incoming attacks." .. colors.reset)
        ao.send({ Target = Game, Action = "PlayerMove", Player = ao.id, Direction = dodgeDirection })
        InAction = false -- Reset InAction after moving
        return
    end
    
    -- Circle around opponents to avoid direct confrontation
    local circleDirection = findApproachDirection() -- Use approach direction for circling
    print(colors.blue .. "Circling around opponents." .. colors.reset)
    ao.send({ Target = Game, Action = "PlayerMove", Player = ao.id, Direction = circleDirection })
    InAction = false -- Reset InAction after moving
end

-- Modified decideNextAction function to include advanced movement strategies
function decideNextAction()
    local me = LatestGameState.Players[ao.id]
    local nearestPlayer = findNearestPlayer()
    local isNearestPlayerInAttackRange = isPlayerInAttackRange(nearestPlayer)

    nearestPlayer.isInAttackRange = isNearestPlayerInAttackRange;
    nearestPlayer.meEnergy = me.energy

    -- Determine if there's an opponent in attack range and their relative energy level
    local shouldAttack = false
    local attackPower = 1.0
    if nearestPlayer.isInAttackRange then
        local opponentEnergy = nearestPlayer.energy
        if opponentEnergy < 20 or (opponentEnergy < me.energy and opponentEnergy < 50) then
            shouldAttack = true
            if opponentEnergy < 20 then
                attackPower = 1.0 -- Full power if opponent energy < 20
            elseif opponentEnergy >= 20 and opponentEnergy < 50 then
                attackPower = 0.5 -- 50% power if opponent energy < 50 and weaker than our bot
            end
        elseif opponentEnergy >= me.energy then
            -- Move away from stronger opponent
            local avoidDirection = findAvoidDirection()
            print(colors.blue .. "Moving away from stronger opponent." .. colors.reset)
            ao.send({ Target = Game, Action = "PlayerMove", Player = ao.id, Direction = avoidDirection })
            InAction = false -- Reset InAction after moving
            return -- Exit function early
        end
    end

    if not shouldAttack then
        -- Advanced Movement Strategies: Incorporate dodging, circling, and strategic positioning
        advancedMovement()
    else
        -- Attack with calculated power
        print(colors.red .. "Attacking with " .. (attackPower * 100) .. "% power." .. colors.reset)
        ao.send({ Target = Game, Action = "PlayerAttack", Player = ao.id, AttackEnergy = tostring(me.energy * attackPower) })
        InAction = false -- Reset InAction after attacking
    end
end

-- Handler to print game announcements and trigger game state updates.
Handlers.add(
    "PrintAnnouncements",
    Handlers.utils.hasMatchingTag("Action", "Announcement"),
    function(msg)
        if msg.Event == "Started-Waiting-Period" then
            ao.send({ Target = ao.id, Action = "AutoPay" })
        elseif (msg.Event == "Tick" or msg.Event == "Started-Game") and not InAction then
            InAction = true  -- InAction logic added
            ao.send({ Target = Game, Action = "GetGameState" })
        elseif InAction then -- InAction logic added
            print("Previous action still in progress. Skipping.")
        end

        print(colors.green .. msg.Event .. ": " .. msg.Data .. colors.reset)
    end
)

-- Handler to trigger game state updates.
Handlers.add(
    "GetGameStateOnTick",
    Handlers.utils.hasMatchingTag("Action", "Tick"),
    function()
        if not InAction then -- InAction logic added
            InAction = true  -- InAction logic added
            print(colors.gray .. "Getting game state..." .. colors.reset)
            ao.send({ Target = Game, Action = "GetGameState" })
        else
            print("Previous action still in progress. Skipping.")
        end
    end
)

-- Handler to automate payment confirmation when waiting period starts.
Handlers.add(
    "AutoPay",
    Handlers.utils.hasMatchingTag("Action", "AutoPay"),
    function(msg)
        print("Auto-paying confirmation fees.")
        ao.send({ Target = Game, Action = "Transfer", Recipient = Game, Quantity = "1000" })
    end
)

-- Handler to update the game state upon receiving game state information.
Handlers.add(
    "UpdateGameState",
    Handlers.utils.hasMatchingTag("Action", "GameState"),
    function(msg)
        local json = require("json")
        LatestGameState = json.decode(msg.Data)
        ao.send({ Target = ao.id, Action = "UpdatedGameState" })
        print("Game state updated. Print \'LatestGameState\' for detailed view.")
        print("energy:" .. LatestGameState.Players[ao.id].energy)
    end
)

-- Handler to decide the next best action.
Handlers.add(
    "decideNextAction",
    Handlers.utils.hasMatchingTag("Action", "UpdatedGameState"),
    function()
        if LatestGameState.GameMode ~= "Playing" then
            print("game not start")
            InAction = false -- InAction logic added
            return
        end
        print("Deciding next action.")
        decideNextAction()
        ao.send({ Target = ao.id, Action = "Tick" })
    end
)

-- Handler to automatically attack when hit by another player.
Handlers.add(
    "ReturnAttack",
    Handlers.utils.hasMatchingTag("Action", "Hit"),
    function(msg)
        if not InAction then -- InAction logic added
            InAction = true  -- InAction logic added
            local playerEnergy = LatestGameState.Players[ao.id].energy
            if playerEnergy == undefined then
                print(colors.red .. "Unable to read energy." .. colors.reset)
                ao.send({ Target = Game, Action = "Attack-Failed", Reason = "Unable to read energy." })
            elseif playerEnergy == 0 then
                print(colors.red .. "Player has insufficient energy." .. colors.reset)
                ao.send({ Target = Game, Action = "Attack-Failed", Reason = "Player has no energy." })
            else
                print(colors.red .. "Returning attack." .. colors.reset)
                ao.send({ Target = Game, Action = "PlayerAttack", Player = ao.id, AttackEnergy = tostring(playerEnergy) })
            end
            InAction = false -- InAction logic added
            ao.send({ Target = ao.id, Action = "Tick" })
        else
            print("Previous action still in progress. Skipping.")
        end
    end
)
