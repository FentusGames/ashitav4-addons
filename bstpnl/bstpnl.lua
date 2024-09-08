-- Addon Information
addon.name      = 'bstpnl';
addon.author    = 'Fentus';
addon.version   = '1.0';
addon.desc      = 'Beastmaster pet information and commands';

-- Required Libraries
require('common');
local imgui = require('imgui');
local settings = require('settings');

-- Default Settings
local default_settings = T{
    is_open = true,
    target  = nil,
    jug_lock = true, 
};

-- Load settings
local bstpnl = settings.load(default_settings);

-- Helper Functions

-- Function to get an entity by its server ID
---@param sid number The server ID of the entity
---@return table|nil The entity if found, nil otherwise
local function GetEntityByServerId(sid)
    for x = 0, 2303 do
        local ent = GetEntity(x);
        if (ent ~= nil and ent.ServerId == sid) then
            return ent;
        end
    end
    return nil;
end

-- Function to get all pet abilities for the player
---@return table A table of pet abilities
local function PetAbilities()
    local abilities = {};
    local res = AshitaCore:GetResourceManager();
    local ply = AshitaCore:GetMemoryManager():GetPlayer();

    for x = 0, 2816 do
        local a = res:GetAbilityById(x);
        if (a ~= nil and a.Type == 18 and ply:HasAbility(x)) then
            table.insert(abilities, { name = a.Name[1] });
        end
    end
    
    return abilities;
end

-- Function to list all jug pet items in the inventory
---@return table A table of jug pet items
local function ListJugBroths()
    local jugs = {}
    local inventory = AshitaCore:GetMemoryManager():GetInventory()
    local resources = AshitaCore:GetResourceManager()
    
    local containers = {0, 5, 6, 7, 8, 10, 11, 12, 13, 14, 15, 16}
    for _, container in ipairs(containers) do
        for i = 1, 80 do  -- Assuming 80 inventory slots
            local item = inventory:GetContainerItem(container, i)
            if item and item.Id ~= 0 then
                local itemResource = resources:GetItemById(item.Id)
                if itemResource then
                    local itemName = itemResource.LogNameSingular[1]
                    if string.match(itemName, "jug of .*") then
                        local description = itemResource.Description[1]
                        local petName = string.match(description, "Calls (.-)%.")
                        if jugs[itemName] then
                            jugs[itemName].count = jugs[itemName].count + item.Count
                        else
                            jugs[itemName] = {name = itemName, petName = petName or "Unknown", count = item.Count, container = container}
                        end
                    end
                end
            end
        end
    end
    
    -- Convert the jugs table to an array
    local result = {}
    for _, jug in pairs(jugs) do
        table.insert(result, jug)
    end
    
    return result
end

-- Function to get the currently equipped ammo
---@return string|nil The name of the currently equipped ammo, or nil if none
local function GetCurrentAmmo()
    local inv = AshitaCore:GetMemoryManager():GetInventory();

    local eitem = inv:GetEquippedItem(3);
    if (eitem == nil or eitem.Index == 0) then
        return nil;
    end

    local iitem = inv:GetContainerItem(bit.band(eitem.Index, 0xFF00) / 0x0100, eitem.Index % 0x0100);
    if(iitem == nil or T{ nil, 0, -1, 65535 }:hasval(iitem.Id)) then return nil; end
	
	local itemResource = AshitaCore:GetResourceManager():GetItemById(iitem.Id);
    if itemResource ~= nil then
        return itemResource.LogNameSingular[1];
    end

    return nil;
end

-- Function to use a jug pet item
---@param jugName string The name of the jug pet item to use
---@param ability string The name of the ability to use (e.g., "Call Beast" or "Bestial Loyalty")
local function UseJug(jugName, ability)
    local currentAmmo = GetCurrentAmmo();
	
    if currentAmmo then
        AshitaCore:GetChatManager():QueueCommand(1, string.format('/equip ammo "%s"', jugName));
        AshitaCore:GetChatManager():QueueCommand(1, string.format('/ja "%s" <me>', ability));
        ashita.tasks.once(1, function()
            AshitaCore:GetChatManager():QueueCommand(1, string.format('/equip ammo "%s"', currentAmmo));
        end);
    else
        print('No ammo currently equipped.');
    end
end

-- Event Handlers

-- Handle incoming packets
ashita.events.register('packet_in', 'packet_in_cb', function (e)
    -- Packet: Action
    if (e.id == 0x0028) then
        -- Obtain the player entity..
        local player = GetPlayerEntity();
        if (player == nil or player.PetTargetIndex == 0) then
            bstpnl.target = nil;
            return;
        end

        -- Obtain the player pet entity..
        local pet = GetEntity(player.PetTargetIndex);
        if (pet == nil) then
            bstpnl.target = nil;
            return;
        end

        -- Obtain the action main target id if the actor is the player pet..
        local aid = struct.unpack('I', e.data_modified, 0x05 + 0x01);
        if (aid ~= 0 and aid == pet.ServerId) then
            bstpnl.target = ashita.bits.unpack_be(e.data_modified:totable(), 0x96, 0x20);
            return;
        end

        return;
    end

    -- Packet: Pet Sync
    if (e.id == 0x0068) then
        -- Obtain the player entity..
        local player = GetPlayerEntity();
        if (player == nil) then
            bstpnl.target = nil;
            return;
        end

        -- Update the players pet target..
        local owner = struct.unpack('I', e.data_modified, 0x08 + 0x01);
        if (owner == player.ServerId) then
            bstpnl.target = struct.unpack('I', e.data_modified, 0x14 + 0x01);
        end

        return;
    end
end);

local AbilityRecastPointer = ashita.memory.find('FFXiMain.dll', 0, '894124E9????????8B46??6A006A00508BCEE8', 0x19, 0);
AbilityRecastPointer = ashita.memory.read_uint32(AbilityRecastPointer);

local function GetAbilityTimerData(id)
    for i = 1,31 do
        local compId = ashita.memory.read_uint8(AbilityRecastPointer + (i * 8) + 3);
        if (compId == id) then
            return {
                Modifier = ashita.memory.read_int16(AbilityRecastPointer + (i * 8) + 4),
                Recast = ashita.memory.read_uint32(AbilityRecastPointer + (i * 4) + 0xF8)
            };
        end
    end

    return {
        Modifier = 0,
        Recast = 0
    };
end

local function GetReadyCharges()
    --Ready == ability recast ID 102
    local data = GetAbilityTimerData(102);

    local baseRecast = 60 * (90 + data.Modifier);
    local chargeValue = baseRecast / 3;
    local remainingCharges = math.floor((baseRecast - data.Recast) / chargeValue);
    local timeUntilNextCharge = math.fmod(data.Recast, chargeValue);
    return remainingCharges, math.ceil(timeUntilNextCharge/60);
end

-- Main rendering function
ashita.events.register('d3d_present', 'present_cb', function ()
    -- Obtain the player entity..
    local player = GetPlayerEntity();
    if (player == nil) then
        bstpnl.target = nil;
        return;
    end
    
    -- Check if the player's main job is Beastmaster
    local playerJob = AshitaCore:GetMemoryManager():GetPlayer():GetMainJob();
    if playerJob ~= 9 then  -- 9 is the job ID for Beastmaster
        return;  -- Exit the function if not Beastmaster
    end

    local hasPet = true

    -- Obtain the player pet entity..
    local pet = GetEntity(player.PetTargetIndex);
    if (pet == nil or pet.Name == nil) then
        bstpnl.target = nil;
        hasPet = false
    end

    imgui.SetNextWindowBgAlpha(0.8);
    imgui.SetNextWindowSize({ 400, -1, }, ImGuiCond_Always);
    
    if (imgui.Begin('Beast Panel', bstpnl.is_open, bit.bor(ImGuiWindowFlags_NoDecoration, ImGuiWindowFlags_AlwaysAutoResize, ImGuiWindowFlags_NoSavedSettings, ImGuiWindowFlags_NoFocusOnAppearing, ImGuiWindowFlags_NoNav))) then
		
        if hasPet then
			-- Display pet information
			local petmp = AshitaCore:GetMemoryManager():GetPlayer():GetPetMPPercent();
			local pettp = AshitaCore:GetMemoryManager():GetPlayer():GetPetTP();
			local dist  = ('%.1f'):fmt(math.sqrt(pet.Distance));
			local x, _  = imgui.CalcTextSize(dist);

			imgui.Text(pet.Name);
			imgui.SameLine();
			imgui.SetCursorPosX(imgui.GetCursorPosX() + imgui.GetColumnWidth() - x - imgui.GetStyle().FramePadding.x);
			imgui.Text(dist);
			imgui.Separator();
			
			-- Updated ProgressBar section
			imgui.PushStyleColor(ImGuiCol_PlotHistogram, { 0.90, 0.3, 0.3, 1.0 });
			imgui.ProgressBar(pet.HPPercent / 100, { -1, 19 }, string.format("HP: %d%%", pet.HPPercent));
			imgui.PopStyleColor(1);
			
			imgui.PushStyleColor(ImGuiCol_PlotHistogram, { 0.6, 0.1, 0.7, 1.0 });
			imgui.ProgressBar(petmp / 100, { -1, 19 }, string.format("MP: %d%%", petmp));
			imgui.PopStyleColor(1);
			
			imgui.PushStyleColor(ImGuiCol_PlotHistogram, { 0.1, 0.8, 0.95, 1.0 });
			imgui.ProgressBar(pettp / 3000, { -1, 19 }, string.format("TP: %d", pettp));
			imgui.PopStyleColor(1);

			local readyCharges, timeToNextCharge = GetReadyCharges();
			imgui.PushStyleColor(ImGuiCol_PlotHistogram, { 0.7, 0.3, 0.0, 1.0 });  -- Orange color
			imgui.ProgressBar(readyCharges / 3, { -1, 19 }, string.format("Ready: %d/3 (%ds)", readyCharges, timeToNextCharge));
			imgui.PopStyleColor(1);
		
            local abilities = PetAbilities();
            
            if #abilities == 0 then
                imgui.Text("No Abilities Available");
            else
                imgui.Text("Pet Abilities");
                
                -- Display abilities as a simple list
                for i, ability in ipairs(abilities) do
                    imgui.Text(('%d: %s'):format(i, ability.name));
                end
            end
			
            -- Display the pet's target information
            if (bstpnl.target ~= nil) then
                local target = GetEntityByServerId(bstpnl.target);
            
                if (target == nil or target.ActorPointer == 0 or target.HPPercent == 0) then
                    bstpnl.target = nil;
                else
                    dist = ('%.1f'):fmt(math.sqrt(target.Distance));
                    x, _ = imgui.CalcTextSize(dist);

                    local tname = target.Name;
                    if (tname == nil) then
                        tname = '';
                    end
                    
                    if (target ~= pet) then
                        imgui.Separator();
                        imgui.Text(('Target: %s'):format(tname));
                        imgui.SameLine();
                        imgui.SetCursorPosX(imgui.GetCursorPosX() + imgui.GetColumnWidth() - x - imgui.GetStyle().FramePadding.x);
                        imgui.Text(dist);
                        imgui.Separator();
                        imgui.Text('HP:');
                        imgui.SameLine();
                        imgui.ProgressBar(target.HPPercent / 100, { -1, 16 });
                    end
                end
            end
			
			imgui.Separator();
            if imgui.Button("Leave", { imgui.GetContentRegionAvail(), 0 }) then
                AshitaCore:GetChatManager():QueueCommand(1, '/pet "Leave" <me>');
            end
        else
            -- Display jug pet items when no pet is present
            imgui.Text("Jug Broths in Inventory");

            -- Jug Lock toggle
            local jug_lock = { bstpnl.jug_lock };
            if imgui.Checkbox("Jug Lock", jug_lock) then
                bstpnl.jug_lock = jug_lock[1];
                settings.save();
            end

            if imgui.IsItemHovered() then
                imgui.SetTooltip("When enabled, prevents use of Call Beast on the last jug of any type");
            end

            local jugs = ListJugBroths();
            local buttonWidth = 60;
            local spacing = 5;
            for _, jug in ipairs(jugs) do
                local availWidth = imgui.GetContentRegionAvail();
                
                -- Loyalty button is always enabled
                if imgui.Button(('Loyalty##%s'):format(jug.name), { buttonWidth, 0 }) then
                    print("Bestial Loyalty")
                    UseJug(jug.name, "Bestial Loyalty");
                end
                
                imgui.SameLine(0, spacing);
                
                -- Call Beast button, conditionally enabled based on Jug Lock
                if not bstpnl.jug_lock or jug.count > 1 then
                    if imgui.Button(('Call##%s'):format(jug.name), { buttonWidth, 0 }) then
                        UseJug(jug.name, "Call Beast");
                    end
                else
                    imgui.PushStyleVar(ImGuiStyleVar_Alpha, 0.5);
                    imgui.Button(('Call##%s'):format(jug.name), { buttonWidth, 0 });
                    imgui.PopStyleVar(1);
                    if imgui.IsItemHovered() then
                        imgui.SetTooltip("Jug Lock is preventing use of Call Beast on the last jug");
                    end
                end
                
                imgui.SameLine(0, spacing);
                imgui.Text(('%s (x%d)'):format(jug.petName, jug.count));
            end
        end
    end
    imgui.End();
end);

-- Save settings when unloading the addon
ashita.events.register('unload', 'unload_cb', function()
    settings.save();
end);