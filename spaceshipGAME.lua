-- Space Ship Game

-- GLOBAL VARIABLES

-- Game progression modes in a loop:
-- [Not-Started] -> Waiting -> Playing -> [Someone wins or timeout] -> Waiting...
GameMode = GameMode or "Not-Started"
StateChangeTime = StateChangeTime or undefined

-- State durations (in milliseconds)
WaitTime = WaitTime or 2 * 60 * 1000 -- 2 minutes
GameTime = GameTime or 20 * 60 * 1000 -- 20 minutes
Now = Now or undefined -- Current time, updated on every message.

-- Token information for player stakes.
UNIT = 0.1 -- 0.1 CRED tokens
PaymentToken = PaymentToken or "CRED"  -- Token address
PaymentQty = PaymentQty or tostring(UNIT)    -- Quantity of tokens for registration

-- Players waiting to join the next game and their payment status.
Waiting = Waiting or {}
-- Active players and their game states.
Players = Players or {}
-- Active bots and their positions.
Bots = Bots or {}
-- Health of the player and bots.
PlayerHealth = PlayerHealth or {}
BotHealth = BotHealth or {}

-- Default player state initialization.
function PlayerInitState()
    return {
        Health = 100 -- 100% health initially
    }
end

-- Sends a state change announcement to all registered listeners.
-- @param event: The event type or name.
-- @param description: Description of the event.
function announce(event, description)
    for ix, address in pairs(Listeners) do
        ao.send({
            Target = address,
            Action = "Announcement",
            Event = event,
            Data = description
        })
    end
    return print("Announcement: " .. event .. " " .. description)
end

-- Sends a reward to a player.
-- @param recipient: The player receiving the reward.
-- @param qty: The quantity of the reward.
-- @param reason: The reason for the reward.
function sendReward(recipient, qty, reason)
    if type(qty) ~= number then
      qty = tonumber(qty)
    end
    ao.send({
        Target = PaymentToken,
        Action = "Transfer",
        Quantity = tostring(qty),
        Recipient = recipient,
        Reason = reason
    })
    return print("Sent Reward: " .. tostring(qty) .. " tokens to " .. recipient .. " " .. reason)
end

-- Starts the waiting period for players to become ready to play.
function startWaitingPeriod()
    GameMode = "Waiting"
    StateChangeTime = Now + WaitTime
    announce("Started-Waiting-Period", "The game is about to begin! Send your token to take part.")
    print('Starting Waiting Period')
end

-- Starts the game if there are enough players.
function startGamePeriod()
    local paidPlayers = 0
    for player, hasPaid in pairs(Waiting) do
        if hasPaid then
            paidPlayers = paidPlayers + 1
        end
    end

    if paidPlayers < 2 then
        announce("Not-Enough-Players", "Not enough players registered! Restarting...")
        for player, hasPaid in pairs(Waiting) do
            if hasPaid then
                Waiting[player] = false
                sendReward(player, PaymentQty, "Refund")
            end
        end
        startWaitingPeriod()
        return
    end

    LastTick = undefined
    GameMode = "Playing"
    StateChangeTime = Now + GameTime
    for player, hasPaid in pairs(Waiting) do
        if hasPaid then
            Players[player] = PlayerInitState()
        else
            ao.send({
                Target = player,
                Action = "Ejected",
                Reason = "Did-Not-Pay"
            })
            removeListener(player) -- Removing player from listener if they didn't pay
        end
    end
    announce("Started-Game", "The game has started. Good luck!")
    print("Game Started....")
end

-- Handles the elimination of a player from the game.
-- @param eliminated: The player to be eliminated.
-- @param eliminator: The player causing the elimination.
function eliminatePlayer(eliminated, eliminator)
    sendReward(eliminator, PaymentQty, "Eliminated-Player")
    Waiting[eliminated] = false
    Players[eliminated] = nil

    ao.send({
        Target = eliminated,
        Action = "Eliminated",
        Eliminator = eliminator
    })

    announce("Player-Eliminated", eliminated .. " was eliminated by " .. eliminator .. "!")
    
    local playerCount = 0
    for player, _ in pairs(Players) do
        playerCount = playerCount + 1
    end
    print("Eliminating player: " .. eliminated .. " by: " .. eliminator) -- Useful for tracking eliminations

    if playerCount < 2 then
        endGame()
    end

end

-- Ends the current game and starts a new one.
function endGame()
    print("Game Over")

    local winner = ""
    for player, _ in pairs(Players) do
        winner = player
    end

    sendReward(winner, tostring(2 * UNIT), "Win")

    Players = {}
    announce("Game-Ended", "Congratulations! The game has ended. Winner: " .. winner .. ".")
    startWaitingPeriod()
end

-- HANDLERS: Game state management

-- Handler for cron messages, manages game state transitions.
Handlers.add(
    "Game-State-Timers",
    function(Msg)
        Now = Msg.Timestamp
        if GameMode == "Not-Started" then
            startWaitingPeriod()
        elseif GameMode == "Waiting" then
            if Now > StateChangeTime then
                startGamePeriod()
            end
        elseif GameMode == "Playing" then
            if Now > StateChangeTime then
                endGame()
            end
        end
    end
)

-- Handler for player deposits to participate in the next game.
Handlers.add(
    "Transfer",
    function(Msg)
        return
            Msg.Action == "Credit-Notice" and
            Msg.From == PaymentToken and
            tonumber(Msg.Quantity) >= tonumber(PaymentQty) and "continue"
    end,
    function(Msg)
        Waiting[Msg.Sender] = true
        ao.send({
            Target = Msg.Sender,
            Action = "Payment-Received"
        })
        announce("Player-Ready", Msg.Sender .. " is ready to play!")
    end
)

-- Handler for player eliminations.
Handlers.add(
    "Eliminate-Player",
    function(Msg)
        return Msg.Action == "Eliminate-Player"
    end,
    function(Msg)
        eliminatePlayer(Msg.Tags.Eliminated, Msg.Tags.Eliminator)
    end
)

-- Registers new players for the next game and subscribes them for event info.
Handlers.add(
    "Register",
    Handlers.utils.hasMatchingTag("Action", "Register"),
    function(Msg)
        if Msg.Mode ~= "Listen" and Waiting[Msg.From] == undefined then
            Waiting[Msg.From] = false
        end
        removeListener(Msg.From)
        table.insert(Listeners, Msg.From)
        ao.send({
            Target = Msg.From,
            Action = "Registered"
        })
        announce("New Player Registered", Msg.From .. " has joined in waiting.")
    end
)

-- Unregisters players and stops sending them event info.
Handlers.add(
    "Unregister",
    Handlers.utils.hasMatchingTag("Action", "Unregister"),
    function(Msg)
        removeListener(Msg.From)
        ao.send({
            Target = Msg.From,
            Action = "Unregistered"
        })
    end
)
