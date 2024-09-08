-- Addon Information
addon.name      = 'bstpnljugs';
addon.author    = 'Fentus';
addon.version   = '1.0';
addon.desc      = 'Beastmaster jug pet usage';

-- Required Libraries
require('common');
local imgui = require('imgui');
local settings = require('settings');

-- Default Settings
local default_settings = T{
    is_open = true,
    jug_lock = true,
    window_position = { 100, 100 },
    window_size = { 400, 300 }
};

-- Load settings
local bstpnljugs = settings.load(default_settings);

-- Helper Functions

-- Function to list all jug pet items in the inventory
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

-- Main rendering function
ashita.events.register('d3d_present', 'present_cb', function ()
    -- Check if the player's main job is Beastmaster
    local playerJob = AshitaCore:GetMemoryManager():GetPlayer():GetMainJob();
    if playerJob ~= 9 then  -- 9 is the job ID for Beastmaster
        return;  -- Exit the function if not Beastmaster
    end
	
	local player = GetPlayerEntity();
	
	if player and player.PetTargetIndex ~= 0 then
		return;  -- Exit the function if the player has an active pet
	end

    imgui.SetNextWindowBgAlpha(0.8);
    imgui.SetNextWindowSize(bstpnljugs.window_size, ImGuiCond_FirstUseEver);
    imgui.SetNextWindowPos(bstpnljugs.window_position, ImGuiCond_FirstUseEver);
    
    if (imgui.Begin('Jug Usage Panel', bstpnljugs.is_open, bit.bor(ImGuiWindowFlags_NoDecoration, ImGuiWindowFlags_AlwaysAutoResize, ImGuiWindowFlags_NoSavedSettings, ImGuiWindowFlags_NoFocusOnAppearing, ImGuiWindowFlags_NoNav))) then
        imgui.Text("Jug Broths in Inventory");

        -- Jug Lock toggle
        local jug_lock = { bstpnljugs.jug_lock };
        if imgui.Checkbox("Jug Lock", jug_lock) then
            bstpnljugs.jug_lock = jug_lock[1];
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
                UseJug(jug.name, "Bestial Loyalty");
            end
            
            imgui.SameLine(0, spacing);
            
            -- Call Beast button, conditionally enabled based on Jug Lock
            if not bstpnljugs.jug_lock or jug.count > 1 then
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

        -- Save window position and size
        bstpnljugs.window_position = { imgui.GetWindowPos() };
        bstpnljugs.window_size = { imgui.GetWindowSize() };
    end
    imgui.End();
end);

-- Save settings when unloading the addon
ashita.events.register('unload', 'unload_cb', function()
    settings.save();
end);

-- Save settings periodically
local last_save_time = 0;
ashita.events.register('d3d_present', 'save_settings_cb', function()
    local current_time = os.time();
    if current_time - last_save_time >= 60 then  -- Save every 60 seconds
        settings.save();
        last_save_time = current_time;
    end
end);