addon.name      = 'find';
addon.author    = 'Fentus';
addon.version   = '1.5';
addon.desc      = 'Find items across inventories and locate duplicates';

require('common');
local chat = require('chat');

-- Define the containers to search
local containers = {0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16};

-- Function to get the container name
local function getContainerName(id)
    local containerNames = {
        [0] = "Inventory",
        [1] = "Safe",
        [2] = "Storage",
        [3] = "Temporary",
        [4] = "Locker",
        [5] = "Satchel",
        [6] = "Sack",
        [7] = "Case",
        [8] = "Wardrobe",
        [9] = "Safe 2",
        [10] = "Wardrobe 2",
        [11] = "Wardrobe 3",
        [12] = "Wardrobe 4",
        [13] = "Wardrobe 5",
        [14] = "Wardrobe 6",
        [15] = "Wardrobe 7",
        [16] = "Wardrobe 8"
    };
    
    return containerNames[id] or "Unknown";
end

-- Function to find items
local function findItems(searchText, includeDescription)
    local results = {};
    local inventory = AshitaCore:GetMemoryManager():GetInventory();
    local resources = AshitaCore:GetResourceManager();

    for _, container in ipairs(containers) do
        local containerItems = {};
        for i = 1, 80 do  -- Assuming 80 inventory slots
            local item = inventory:GetContainerItem(container, i);
            if (item ~= nil and item.Id ~= 0) then
                local itemResource = resources:GetItemById(item.Id);
                if (itemResource ~= nil) then
                    local fullName = itemResource.Name[1];
                    local logNameSingular = itemResource.LogNameSingular[1];
                    local description = itemResource.Description[1];
                    if string.find(string.lower(fullName), string.lower(searchText)) or
                       string.find(string.lower(logNameSingular), string.lower(searchText)) or
                       (description ~= nil and includeDescription and string.find(string.lower(description), string.lower(searchText))) then
                        containerItems[fullName] = {
                            count = (containerItems[fullName] and containerItems[fullName].count or 0) + item.Count,
                            description = description
                        };
                    end
                end
            end
        end
        if next(containerItems) ~= nil then
            results[container] = containerItems;
        end
    end

    return results;
end

local function findDuplicates()
    local inventory = AshitaCore:GetMemoryManager():GetInventory();
    local resources = AshitaCore:GetResourceManager();
    local itemCounts = {};
    local duplicates = {};

    for _, container in ipairs(containers) do
        for i = 1, 80 do
            local item = inventory:GetContainerItem(container, i);
            if (item ~= nil and item.Id ~= 0) then
                local itemResource = resources:GetItemById(item.Id);
                if (itemResource ~= nil) then
                    local fullName = itemResource.Name[1];
                    local maxStack = itemResource.StackSize;
                    
                    -- Only consider items that haven't reached their max stack size
                    if item.Count < maxStack then
                        if (itemCounts[fullName] == nil) then
                            itemCounts[fullName] = {};
                        end
                        if (itemCounts[fullName][container] == nil) then
                            itemCounts[fullName][container] = {};
                        end
                        table.insert(itemCounts[fullName][container], {count = item.Count, slot = i});
                    end
                end
            end
        end
    end

    for itemName, containerCounts in pairs(itemCounts) do
        local containerList = {};
        for container, items in pairs(containerCounts) do
            table.insert(containerList, {container = container, items = items});
        end
        if (#containerList > 1) then
            table.sort(containerList, function(a, b) return a.container < b.container end);
            duplicates[itemName] = containerList;
        end
    end

    return duplicates;
end

local function printDuplicates(duplicates)
    print(chat.header(addon.name) .. chat.message('Duplicate items across inventories:'));
    for itemName, containerList in pairs(duplicates) do
        print(chat.color1(1, itemName));  -- Item name in white
        for _, containerInfo in ipairs(containerList) do
            print(chat.color1(6, getContainerName(containerInfo.container)));  -- Inventory name in blue
            for _, itemInfo in ipairs(containerInfo.items) do
                print(string.format('  > x%d (%d)', 
                    itemInfo.count,
                    itemInfo.slot
                ));
            end
        end
        print(''); -- Add an empty line between items for better readability
    end
end

-- Prints the addon help information.
local function print_help(isError)
    if (isError) then
        print(chat.header(addon.name):append(chat.error('Invalid command syntax for command: ')):append(chat.success('/' .. addon.name)));
    else
        print(chat.header(addon.name):append(chat.message('Available commands:')));
    end

    local cmds = T{
        { '/find <search text>', 'Searches for items containing the specified text in full name or log name singular.' },
        { '/f <search text>', 'Short version of the search command.' },
        { '/di <search text>', 'Searches for items containing the specified text in full name, log name singular, or description. Also displays item descriptions.' },
        { '/fc', 'Finds duplicate items across different inventories.' },
    };

    cmds:ieach(function (v)
        print(chat.header(addon.name):append(chat.error('Usage: ')):append(chat.message(v[1]):append(' - ')):append(chat.color1(6, v[2])));
    end);
end

-- Initialize the addon event handlers.
ashita.events.register('load', 'load_cb', function()
    print(chat.header(addon.name) .. chat.message('Find addon loaded. Use /find, /f, /di <search text> to search for items, or /fc to find duplicates.'));
end);

ashita.events.register('command', 'command_cb', function(e)
    -- Parse the command arguments..
    local args = e.command:args();
    if (#args == 0 or (args[1] ~= '/find' and args[1] ~= '/f' and args[1] ~= '/di' and args[1] ~= '/fc')) then
        return false;
    end

    -- Handle: /find <search text>, /f <search text>, or /di <search text>
    if ((args[1] == '/find' or args[1] == '/f' or args[1] == '/di') and #args >= 2) then
        local searchText = table.concat(args, ' ', 2);
        local includeDescription = (args[1] == '/di');
        local results = findItems(searchText, includeDescription);

        if (next(results) == nil) then
            print(chat.header(addon.name) .. chat.message('No items found matching: ' .. searchText));
            return true;
        end

        print(chat.header(addon.name) .. chat.message('Items matching: ' .. searchText));
        local grandTotal = 0;
        for container, items in pairs(results) do
            print(chat.color1(6, getContainerName(container) .. ':'));
            for itemName, itemInfo in pairs(items) do
                local output = string.format('  %s x%d', itemName, itemInfo.count);
                if (includeDescription and itemInfo.description) then
                    output = output .. string.format(' - %s', itemInfo.description);
                end
                print(output);
                grandTotal = grandTotal + itemInfo.count;
            end
        end
        print(chat.header(addon.name) .. chat.color1(5, 'Total count across all inventories: ' .. grandTotal));
        return true;
    end

    -- Handle: /fc
    if (args[1] == '/fc') then
        local duplicates = findDuplicates();
        if (next(duplicates) == nil) then
            print(chat.header(addon.name) .. chat.message('No duplicate items found across different inventories.'));
        else
            printDuplicates(duplicates);
        end
        return true;
    end

    -- Unhandled: Print help information..
    print_help(true);
    return true;
end);

return addon;