-- ============================================================
-- Foule Throttle : spawn and control a crowd of NPCs
-- Open the menu with F2.
-- Requires MenuV : `ensure menuv` before `ensure foule_throttle`.
-- ============================================================

-- ------------------------------------------------------------
-- CONFIG
-- ------------------------------------------------------------
local OPEN_KEY = 'F2'              -- pick a key not used by another resource
local COUNT_MAX = 1000              -- maximum number of peds in the crowd
local DENSITY_MAX = 2.0            -- maximum peds per square metre in a spawn's spread area
local RADIUS_MAX = 10000             -- maximum spread radius (metres)
local DEFAULT_COUNT = 10           -- default quantity per spawn
local DEFAULT_RADIUS = 10          -- default spread radius (metres)
local NETWORKED = true            -- false = peds exist only for you, true = visible to everyone
local RANDOM_VARIATION = true      -- random clothes / face variation on each ped
local SPAWN_BATCH = 5              -- peds created per frame (avoids a freeze with big crowds)
local MODEL_TIMEOUT = 3000         -- ms to wait for a model before giving up
local LOAD_TRIES = 3               -- models tried for one ped when loading fails (streaming problem)

-- Appearance modes (the first button cycles through them with Enter)
local APPEARANCES = {
    { key = 'all',     label = 'Random (all models)' },
    { key = 'civil_m', label = 'Random : civilian men' },
    { key = 'civil_f', label = 'Random : civilian women' },
    { key = 'service', label = 'Random : service' },
    { key = 'gang',    label = 'Random : gangs' },
    { key = 'unique',  label = 'Random : unique' },
    { key = 'story',   label = 'Random : story characters' },
    { key = 'animals', label = 'Random : animals' },
    { key = 'chosen',  label = 'Chosen model' }
}

-- "all" picks among these categories (animals are only used on purpose)
local ALL_CATEGORIES = { 'civil_m', 'civil_f', 'service', 'gang', 'unique', 'story' }

local POSITIONS = {
    { key = 'player',   label = 'My position' },
    { key = 'waypoint', label = 'Waypoint' },
    { key = 'custom',   label = 'Custom coords' }
}

-- Animations applied to the whole crowd.
-- scenario = name of a game scenario, anim = animation dictionary + clip (looped).
-- Dances have one clip for men and one for women.
local ANIMATIONS = {
    { icon = '🙌', label = 'Cheering',       scenario = 'WORLD_HUMAN_CHEERING' },
    { icon = '🎉', label = 'Partying',       scenario = 'WORLD_HUMAN_PARTYING' },
    { icon = '💃', label = 'Dance (high)',   dict = 'anim@amb@nightclub@dancers@crowddance_groups@hi_intensity',
      male = 'hi_dance_crowd_15_v1_male^2', female = 'hi_dance_crowd_17_v2_female^5' },
    { icon = '🕺', label = 'Dance (low)',    dict = 'anim@amb@nightclub@dancers@crowddance_groups@low_intensity',
      male = 'li_dance_crowd_11_v2_male^5', female = 'li_dance_crowd_17_v1_female^1' },
    { icon = '📱', label = 'On the phone',   scenario = 'WORLD_HUMAN_STAND_MOBILE' },
    { icon = '🎥', label = 'Filming',        scenario = 'WORLD_HUMAN_MOBILE_FILM_SHOCKING' },
    { icon = '🚬', label = 'Smoking',        scenario = 'WORLD_HUMAN_SMOKING' },
    { icon = '☕', label = 'Coffee',          scenario = 'WORLD_HUMAN_AA_COFFEE' },
    { icon = '🥤', label = 'Drinking',       scenario = 'WORLD_HUMAN_DRINKING' },
    { icon = '🧍', label = 'Hanging out',    scenario = 'WORLD_HUMAN_HANG_OUT_STREET' },
    { icon = '⏱️', label = 'Impatient',      scenario = 'WORLD_HUMAN_STAND_IMPATIENT' },
    { icon = '📋', label = 'Clipboard',      scenario = 'WORLD_HUMAN_CLIPBOARD' },
    { icon = '🔭', label = 'Binoculars',     scenario = 'WORLD_HUMAN_BINOCULARS' },
    { icon = '🗺️', label = 'Tourist map',    scenario = 'WORLD_HUMAN_TOURIST_MAP' },
    { icon = '💂', label = 'Guard',          scenario = 'WORLD_HUMAN_GUARD_STAND' },
    { icon = '🏃', label = 'Jogging',        scenario = 'WORLD_HUMAN_JOG_STANDING' },
    { icon = '💪', label = 'Push ups',       scenario = 'WORLD_HUMAN_PUSH_UPS' },
    { icon = '🧘', label = 'Yoga',           scenario = 'WORLD_HUMAN_YOGA' },
    { icon = '🎸', label = 'Musician',       scenario = 'WORLD_HUMAN_MUSICIAN' },
    { icon = '🥴', label = 'Drunk',          scenario = 'WORLD_HUMAN_STUPOR' }
}

-- ------------------------------------------------------------
-- STATE
-- ------------------------------------------------------------
-- THE LIST of every ped created by this resource, oldest first:
-- { ped = entity handle, model = 'model_name' }
local crowd = {}

local settings = {
    appearance = 1,                  -- index in APPEARANCES
    chosenModel = nil,               -- model name used by the 'chosen' mode
    count = DEFAULT_COUNT,           -- peds per spawn
    position = 1,                    -- index in POSITIONS
    customCoords = nil,              -- vector3 used by the 'custom' mode
    radius = DEFAULT_RADIUS
}

local busy = false                   -- true while the keyboard is open or a spawn is running

-- Bumped every time a control order (animation, stand still, wander, come to me) is given.
-- A running order compares its own token against this value: if it no longer matches,
-- a newer order has superseded it, so it stops instead of fighting over the same peds.
local controlGeneration = 0

-- ------------------------------------------------------------
-- HELPERS
-- ------------------------------------------------------------
local function notify(message)
    BeginTextCommandThefeedPost('STRING')
    AddTextComponentSubstringPlayerName(message)
    EndTextCommandThefeedPostTicker(false, true)
end

-- Opens GTA's on-screen keyboard. Returns the typed text, or nil if cancelled.
local function askText(title, defaultText, maxLength)
    AddTextEntry('CROWD_INPUT', title)
    DisplayOnscreenKeyboard(1, 'CROWD_INPUT', '', defaultText or '', '', '', '', maxLength or 64)

    local status = UpdateOnscreenKeyboard()
    while status == 0 do
        DisableAllControlActions(0)
        Wait(0)
        status = UpdateOnscreenKeyboard()
    end

    -- 1 = validated, 2 = cancelled, 3 = keyboard not shown
    if status ~= 1 then
        return nil
    end

    return ((GetOnscreenKeyboardResult() or ''):gsub('^%s+', ''):gsub('%s+$', ''))
end

-- Asks for a whole number between min and max. Returns the number, or nil.
local function askInteger(title, defaultValue, min, max)
    local text = askText(title, tostring(defaultValue), 5)

    if text == nil then
        return nil
    end

    local value = text:match('^%d+$') and tonumber(text) or nil

    if value == nil or value < min or value > max then
        notify(('Enter a whole number from %d to %d.'):format(min, max))
        return nil
    end

    return value
end

-- Removes from the list the peds that no longer exist (deleted by the game, etc.)
local function pruneCrowd()
    for i = #crowd, 1, -1 do
        if not DoesEntityExist(crowd[i].ped) then
            table.remove(crowd, i)
        end
    end
end

local function crowdSize()
    pruneCrowd()
    return #crowd
end

-- Number of living peds of the crowd currently within `radius` metres of `center`
-- (used to enforce the density cap even across several successive spawns in the same area)
local function crowdWithin(center, radius)
    local count = 0

    for _, entry in ipairs(crowd) do
        if DoesEntityExist(entry.ped) then
            local coords = GetEntityCoords(entry.ped)
            local dx, dy = coords.x - center.x, coords.y - center.y

            if (dx * dx + dy * dy) <= radius * radius then
                count = count + 1
            end
        end
    end

    return count
end

-- ------------------------------------------------------------
-- MODELS
-- ------------------------------------------------------------
-- true if the model exists in this game build and is a ped
local function isUsablePed(name)
    local hash = GetHashKey(name)

    return IsModelInCdimage(hash) and IsModelValid(hash) and IsModelAPed(hash)
end

-- Loads a model. Returns its hash, or nil if it does not exist / is not a ped / times out.
local function loadPedModel(name)
    if not isUsablePed(name) then
        return nil
    end

    local hash = GetHashKey(name)

    RequestModel(hash)

    local deadline = GetGameTimer() + MODEL_TIMEOUT
    while not HasModelLoaded(hash) do
        if GetGameTimer() > deadline then
            return nil
        end

        Wait(0)
    end

    return hash
end

-- Pools are built once
local allPool = {}

for _, category in ipairs(ALL_CATEGORIES) do
    for _, name in ipairs(CrowdModels[category] or {}) do
        allPool[#allPool + 1] = name
    end
end

-- Builds the list of models the current appearance mode can use, keeping only
-- the ones that exist in this game build. Returns the list, or nil + reason.
local function buildPool()
    local mode = APPEARANCES[settings.appearance].key

    if mode == 'chosen' then
        if not settings.chosenModel then
            return nil, 'No model chosen. Use the Model button first.'
        end

        if not isUsablePed(settings.chosenModel) then
            return nil, ('Model "%s" is not available.'):format(settings.chosenModel)
        end

        return { settings.chosenModel }
    end

    local source = mode == 'all' and allPool or CrowdModels[mode] or {}
    local pool = {}

    for _, name in ipairs(source) do
        if isUsablePed(name) then
            pool[#pool + 1] = name
        end
    end

    if #pool == 0 then
        return nil, 'No available model for this appearance in your game build.'
    end

    return pool
end

-- ------------------------------------------------------------
-- POSITIONS
-- ------------------------------------------------------------
-- Returns the spawn center (vector3), or nil + reason.
local function resolveCenter()
    local mode = POSITIONS[settings.position].key

    if mode == 'player' then
        local coords = GetEntityCoords(PlayerPedId())
        return vector3(coords.x, coords.y, coords.z - 1.0)
    end

    if mode == 'waypoint' then
        local blip = GetFirstBlipInfoId(8)

        if not DoesBlipExist(blip) then
            return nil, 'No waypoint set on the map.'
        end

        local coords = GetBlipInfoIdCoord(blip)
        return vector3(coords.x, coords.y, 0.0), nil
    end

    if not settings.customCoords then
        return nil, 'No custom coords set. Use the Custom coords button first.'
    end

    return settings.customCoords
end

-- Random point in a disc around the center
local function randomPointAround(center, radius)
    local angle = math.random() * 2.0 * math.pi
    local distance = radius * math.sqrt(math.random())

    return center.x + math.cos(angle) * distance, center.y + math.sin(angle) * distance
end

-- Ground height at x, y. Falls back to hintZ when the collision is not loaded.
local function findGroundZ(x, y, hintZ, tries)
    local startZ = hintZ == 0.0 and 1000.0 or hintZ + 25.0

    RequestCollisionAtCoord(x, y, startZ)

    for _ = 1, tries do
        local found, groundZ = GetGroundZFor_3dCoord(x, y, startZ, false)

        if found then
            return groundZ, true
        end

        Wait(0)
    end

    return hintZ, false
end

-- ------------------------------------------------------------
-- SPAWN / DELETE
-- ------------------------------------------------------------
local function deleteEntry(entry)
    if DoesEntityExist(entry.ped) then
        SetEntityAsMissionEntity(entry.ped, true, true)
        DeleteEntity(entry.ped)
    end
end

-- Spawns `amount` peds around the chosen position and adds them to the list.
-- Returns how many were really created.
local function spawnPeds(amount)
    local center, reason = resolveCenter()

    if not center then
        notify(reason)
        return 0
    end

    local pool, poolReason = buildPool()

    if not pool then
        notify(poolReason)
        return 0
    end

    local room = COUNT_MAX - crowdSize()

    -- Density cap: at most DENSITY_MAX peds per m² in this spawn's spread area,
    -- counting the peds already there from earlier spawns in the same spot.
    local areaCap = math.floor(DENSITY_MAX * math.pi * settings.radius * settings.radius)
    local densityRoom = areaCap - crowdWithin(center, settings.radius)

    amount = math.min(amount, room, math.max(densityRoom, 0))

    if amount <= 0 then
        if densityRoom <= 0 then
            notify(('Max density reached for this area (%.0f peds/m²). Increase the radius or spawn elsewhere.'):format(DENSITY_MAX))
        else
            notify(('The crowd is full (%d peds maximum).'):format(COUNT_MAX))
        end
        return 0
    end

    -- A waypoint has no height: find the ground once for the center
    local centerZ = center.z
    local centerKnown = true

    if centerZ == 0.0 then
        local z = nil
        z, centerKnown = findGroundZ(center.x, center.y, 0.0, 60)
        centerZ = z
    end

    local created = 0
    local failures = 0
    local lastHash = nil

    for i = 1, amount do
        -- 1. Choose a model that can really be loaded
        local hash, name = nil, nil

        for _ = 1, LOAD_TRIES do
            local candidate = pool[math.random(#pool)]

            hash = loadPedModel(candidate)

            if hash then
                name = candidate
                break
            end

            -- A chosen model that fails will fail every time: stop now
            if APPEARANCES[settings.appearance].key == 'chosen' then
                notify(('Model "%s" could not be loaded.'):format(candidate))
                return created
            end
        end

        if not hash then
            -- Nothing loads: no point trying again for every remaining ped
            notify('Models are not loading, spawn stopped.')
            return created
        else
            -- 2. Position
            local x, y = randomPointAround(center, settings.radius)
            local z = findGroundZ(x, y, centerZ, 3)

            -- 3. Create the ped
            local ped = CreatePed(4, hash, x, y, z, math.random() * 360.0, NETWORKED, false)

            if ped ~= 0 and DoesEntityExist(ped) then
                SetEntityAsMissionEntity(ped, true, true)
                SetBlockingOfNonTemporaryEvents(ped, true)
                SetPedFleeAttributes(ped, 0, false)

                if RANDOM_VARIATION then
                    SetPedRandomComponentVariation(ped, 0)
                end

                crowd[#crowd + 1] = { ped = ped, model = name }
                created = created + 1
            else
                failures = failures + 1
            end

            SetModelAsNoLongerNeeded(hash)
        end

        if i % SPAWN_BATCH == 0 then
            Wait(0)
        end
    end

    if failures > 0 then
        notify(('%d ped(s) could not be created.'):format(failures))
    end

    if not centerKnown then
        notify('Ground not loaded at the spawn point: get closer if peds look misplaced.')
    end

    return created
end

-- Deletes the `amount` most recent peds of the list
local function deleteLast(amount)
    pruneCrowd()

    local removed = 0

    for i = #crowd, math.max(1, #crowd - amount + 1), -1 do
        deleteEntry(crowd[i])
        table.remove(crowd, i)
        removed = removed + 1
    end

    return removed
end

local function deleteAll()
    return deleteLast(#crowd)
end

-- ------------------------------------------------------------
-- ORDERS GIVEN TO THE WHOLE CROWD
-- ------------------------------------------------------------
-- Runs fn(ped, index) on every living ped of the list
local function forEachPed(fn)
    pruneCrowd()

    local count = 0

    for i, entry in ipairs(crowd) do
        if not IsPedDeadOrDying(entry.ped, true) then
            fn(entry.ped, i)
            count = count + 1
        end
    end

    return count
end

-- `token` is the controlGeneration value captured when this order was issued.
-- Loading an anim dict takes time: if a newer order arrives while we wait, this
-- one gives up instead of applying a stale animation after the fact.
local function playAnimation(animation, token)
    if animation.dict then
        RequestAnimDict(animation.dict)

        local deadline = GetGameTimer() + MODEL_TIMEOUT
        while not HasAnimDictLoaded(animation.dict) do
            if token ~= controlGeneration then
                return 0
            end

            if GetGameTimer() > deadline then
                notify('Animation could not be loaded.')
                return 0
            end

            Wait(0)
        end
    end

    if token ~= controlGeneration then
        return 0
    end

    local count = forEachPed(function(ped)
        ClearPedTasks(ped)

        if animation.scenario then
            TaskStartScenarioInPlace(ped, animation.scenario, 0, true)
        else
            local clip = IsPedMale(ped) and animation.male or animation.female
            TaskPlayAnim(ped, animation.dict, clip, 8.0, -8.0, -1, 1, 0.0, false, false, false)
        end
    end)

    return count
end

local function standStill()
    controlGeneration = controlGeneration + 1

    return forEachPed(function(ped)
        ClearPedTasks(ped)
    end)
end

local function wander()
    controlGeneration = controlGeneration + 1

    return forEachPed(function(ped)
        ClearPedTasks(ped)
        TaskWanderStandard(ped, 10.0, 10)
        SetPedKeepTask(ped, true)
    end)
end

local function comeToMe()
    controlGeneration = controlGeneration + 1

    local target = GetEntityCoords(PlayerPedId())

    return forEachPed(function(ped)
        ClearPedTasks(ped)

        -- Each ped aims at a slightly different point so they do not pile up
        local x, y = randomPointAround(target, 3.0)
        TaskGoToCoordAnyMeans(ped, x, y, target.z, 1.0, 0, false, 786603, 0.0)
        SetPedKeepTask(ped, true)
    end)
end

-- ------------------------------------------------------------
-- MENUS
-- ------------------------------------------------------------
local menu = MenuV:CreateMenu(
    'Crowd Manager',
    'Spawn and control NPCs',
    'topleft',
    0, 120, 255,
    'size-125',
    'default',
    'menuv',
    'foule_throttle',
    'native'
)

local controlMenu = MenuV:CreateMenu(
    'Crowd Control',
    'Animations and behaviour',
    'topleft',
    0, 120, 255,
    'size-125',
    'default',
    'menuv',
    'foule_throttle_control',
    'native'
)

-- ---- Main menu items ----
local appearanceButton = menu:AddButton({
    icon = '🎭',
    label = 'Appearance : ' .. APPEARANCES[settings.appearance].label,
    description = 'Press Enter to change: random, by category, or a chosen model'
})

local modelButton = menu:AddButton({
    icon = '🧍',
    label = 'Model : none',
    description = 'Type a model name, for example a_m_m_beach_01 (selects the Chosen model mode)'
})

local quantityButton = menu:AddButton({
    icon = '🔢',
    label = ('Quantity : %d'):format(settings.count),
    description = ('Peds created by each spawn (1 to %d)'):format(COUNT_MAX)
})

local positionButton = menu:AddButton({
    icon = '📍',
    label = 'Position : ' .. POSITIONS[settings.position].label,
    description = 'Press Enter to change: your position, the map waypoint, or custom coords'
})

local coordsButton = menu:AddButton({
    icon = '🧭',
    label = 'Custom coords : not set',
    description = 'Type x, y, z (selects the Custom coords position)'
})

local radiusButton = menu:AddButton({
    icon = '↔️',
    label = ('Spread radius : %d m'):format(settings.radius),
    description = ('Peds are spread randomly in this radius (1 to %d m), max density %.0f peds/m²'):format(RADIUS_MAX, DENSITY_MAX)
})

local spawnButton = menu:AddButton({
    icon = '➕',
    label = 'Spawn crowd',
    description = 'Create the peds with the settings above'
})

local controlButton = menu:AddButton({
    icon = '🎮',
    label = 'Control crowd (0)',
    value = controlMenu,
    description = 'Animations and behaviour for every ped of the crowd'
})

local totalButton = menu:AddButton({
    icon = '✏️',
    label = 'Set total count',
    description = 'Adds peds or removes the most recent ones to reach this total'
})

local deleteButton = menu:AddButton({
    icon = '🗑️',
    label = 'Delete all',
    description = 'Removes every ped created by this menu'
})

local closeButton = menu:AddButton({
    icon = '❌',
    label = 'Close',
    description = 'Close the menu'
})

-- ---- Control menu items ----
local animationButtons = {}

for _, animation in ipairs(ANIMATIONS) do
    local button = controlMenu:AddButton({
        icon = animation.icon,
        label = animation.label,
        description = 'Plays on every ped of the crowd'
    })

    animationButtons[#animationButtons + 1] = { button = button, animation = animation }
end

local stillButton = controlMenu:AddButton({
    icon = '⏹️',
    label = 'Stop (stand still)',
    description = 'Cancels the current animation or movement'
})

local wanderButton = controlMenu:AddButton({
    icon = '🚶',
    label = 'Wander',
    description = 'Every ped walks around freely'
})

local comeButton = controlMenu:AddButton({
    icon = '👋',
    label = 'Come to me',
    description = 'Every ped walks to your position'
})

local backButton = controlMenu:AddButton({
    icon = '⬅️',
    label = 'Back',
    description = 'Return to the main menu'
})

-- ------------------------------------------------------------
-- LABEL REFRESH
-- ------------------------------------------------------------
local function refreshLabels()
    controlButton.Label = ('Control crowd (%d)'):format(crowdSize())
    appearanceButton.Label = 'Appearance : ' .. APPEARANCES[settings.appearance].label
    modelButton.Label = 'Model : ' .. (settings.chosenModel or 'none')
    quantityButton.Label = ('Quantity : %d'):format(settings.count)
    positionButton.Label = 'Position : ' .. POSITIONS[settings.position].label

    if settings.customCoords then
        coordsButton.Label = ('Custom coords : %.1f, %.1f, %.1f'):format(
            settings.customCoords.x, settings.customCoords.y, settings.customCoords.z)
    else
        coordsButton.Label = 'Custom coords : not set'
    end

    radiusButton.Label = ('Spread radius : %d m'):format(settings.radius)
end

local function refreshCount()
    controlButton.Label = ('Control crowd (%d)'):format(crowdSize())
end

-- Runs fn in its own thread with the `busy` guard. An error never leaves the menu locked.
local function runExclusive(fn)
    if busy then
        return
    end

    busy = true

    CreateThread(function()
        local ok, err = pcall(fn)

        if not ok then
            print(('[foule_throttle] error: %s'):format(tostring(err)))
            notify('Crowd Manager error, see the F8 console.')
        end

        busy = false
    end)
end

-- Same, but the menu is closed while the on-screen keyboard is open
-- (otherwise Enter / Backspace would also act on the menu), then reopened.
local function runWithKeyboard(fn)
    runExclusive(function()
        menu:Close()
        Wait(300)

        local ok, err = pcall(fn)

        if not ok then
            print(('[foule_throttle] error: %s'):format(tostring(err)))
            notify('Crowd Manager error, see the F8 console.')
        end

        refreshLabels()
        Wait(200)
        menu:Open()
    end)
end

-- ------------------------------------------------------------
-- MAIN MENU EVENTS
-- ------------------------------------------------------------
appearanceButton:On('select', function()
    if busy then return end

    settings.appearance = settings.appearance % #APPEARANCES + 1
    refreshLabels()
end)

positionButton:On('select', function()
    if busy then return end

    settings.position = settings.position % #POSITIONS + 1
    refreshLabels()
end)

modelButton:On('select', function()
    runWithKeyboard(function()
        local name = askText('Ped model name', settings.chosenModel or 'a_m_m_beach_01', 64)

        if name == nil then
            notify('Model unchanged.')
            return
        end

        name = name:lower()

        if name == '' or not isUsablePed(name) then
            notify(('"%s" is not a valid ped model.'):format(name))
            return
        end

        settings.chosenModel = name

        for index, appearance in ipairs(APPEARANCES) do
            if appearance.key == 'chosen' then
                settings.appearance = index
            end
        end

        notify(('Model set to %s.'):format(name))
    end)
end)

quantityButton:On('select', function()
    runWithKeyboard(function()
        local value = askInteger('Quantity per spawn', settings.count, 1, COUNT_MAX)

        if value then
            settings.count = value
            notify(('Quantity set to %d.'):format(value))
        end
    end)
end)

radiusButton:On('select', function()
    runWithKeyboard(function()
        local value = askInteger('Spread radius in metres', settings.radius, 1, RADIUS_MAX)

        if value then
            settings.radius = value
            notify(('Radius set to %d m.'):format(value))
        end
    end)
end)

coordsButton:On('select', function()
    runWithKeyboard(function()
        local here = GetEntityCoords(PlayerPedId())
        local default = settings.customCoords
            and ('%.1f, %.1f, %.1f'):format(settings.customCoords.x, settings.customCoords.y, settings.customCoords.z)
            or ('%.1f, %.1f, %.1f'):format(here.x, here.y, here.z - 1.0)

        local text = askText('Coords: x, y, z', default, 48)

        if text == nil then
            notify('Coords unchanged.')
            return
        end

        local numbers = {}
        for token in text:gmatch('[^,%s]+') do
            numbers[#numbers + 1] = tonumber(token)
        end

        if #numbers ~= 3 or not numbers[1] or not numbers[2] or not numbers[3] then
            notify('Enter three numbers: x, y, z.')
            return
        end

        settings.customCoords = vector3(numbers[1] + 0.0, numbers[2] + 0.0, numbers[3] + 0.0)

        for index, position in ipairs(POSITIONS) do
            if position.key == 'custom' then
                settings.position = index
            end
        end

        notify('Custom coords saved.')
    end)
end)

spawnButton:On('select', function()
    runExclusive(function()
        local created = spawnPeds(settings.count)

        refreshLabels()

        if created > 0 then
            notify(('%d ped(s) created. Crowd: %d.'):format(created, crowdSize()))
        end
    end)
end)

totalButton:On('select', function()
    runWithKeyboard(function()
        local target = askInteger('Total number of peds', crowdSize(), 0, COUNT_MAX)

        if target == nil then
            return
        end

        local current = crowdSize()

        if target < current then
            deleteLast(current - target)
        elseif target > current then
            spawnPeds(target - current)
        end

        notify(('Crowd: %d.'):format(crowdSize()))
    end)
end)

deleteButton:On('select', function()
    if busy then return end

    local removed = deleteAll()
    refreshLabels()
    notify(('%d ped(s) deleted.'):format(removed))
end)

closeButton:On('select', function()
    menu:Close()
end)

-- ------------------------------------------------------------
-- CONTROL MENU EVENTS
-- ------------------------------------------------------------
for _, entry in ipairs(animationButtons) do
    entry.button:On('select', function()
        -- Supersedes any order (animation or behaviour) still being applied
        controlGeneration = controlGeneration + 1
        local token = controlGeneration

        -- Loading an animation dictionary waits, so it runs in its own thread
        CreateThread(function()
            local count = playAnimation(entry.animation, token)

            if count > 0 then
                notify(('%s : %d ped(s).'):format(entry.animation.label, count))
            end
        end)
    end)
end

stillButton:On('select', function()
    notify(('Stopped : %d ped(s).'):format(standStill()))
end)

wanderButton:On('select', function()
    notify(('Wandering : %d ped(s).'):format(wander()))
end)

comeButton:On('select', function()
    notify(('Coming to you : %d ped(s).'):format(comeToMe()))
end)

backButton:On('select', function()
    controlMenu:Close()
end)

-- Keep the crowd counter up to date whenever a menu opens
menu:On('open', refreshCount)

-- Open with F2
menu:OpenWith('KEYBOARD', OPEN_KEY)

-- ------------------------------------------------------------
-- CLEANUP AND EXPORTS
-- ------------------------------------------------------------
-- Delete every ped of the crowd when the resource stops
AddEventHandler('onResourceStop', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then
        return
    end

    deleteAll()
end)

-- Other resources can read the list: exports['foule_throttle']:GetCrowd()
-- returns a copy: { { ped = handle, model = 'name' }, ... }
exports('GetCrowd', function()
    pruneCrowd()

    local copy = {}

    for i, entry in ipairs(crowd) do
        copy[i] = { ped = entry.ped, model = entry.model }
    end

    return copy
end)

math.randomseed(GetGameTimer())
