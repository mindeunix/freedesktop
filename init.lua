local Gio  = require("lgi").Gio
local GLib = require("lgi").GLib

local module = {
    -- This table holds a list of directories to search for *.desktop files.
    -- Only files ending in .desktop are used; other files are ignored.
    appdirs = {
        "/usr/share/applications/",
        "/usr/share/applications/kde4/",
        "/usr/local/share/applications/",
        os.getenv("HOME").."/.local/share/applications/",
    },
    -- The table below lists all menu categories.
    categories = {
        Development = {},
        Education = {},
        Games = {},
        Graphics = {},
        Internet = {},
        Multimedia = {},
        Office = {},
        Science = {},
        Settings = {},
        System = {},
        Utilities = {}
    }
}

local icons_cached  = setmetatable({}, { __mode = 'k' })
local Gtk = nil

-- Helpers
local function emit_signal(self, name,...)
    for _,v in ipairs(self._connections[name] or {}) do
        v(...)
    end
end
local function connect_signal(self, name, callback)
    self._connections[name] = self._connections[name] or {}
    self._connections[name][#self._connections[name]+1] = callback
end
local function create_request()
    local req = {_connections={}}
    req.emit_signal = emit_signal
    req.connect_signal = connect_signal
    return req
end

--- Looks up a named icon and returns a filename of the icon.
-- @param icon
-- @returns filename of the icon.
-- TODO: Select icon theme.
function module.lookup_icon(icon)
    if icons_cached[icon] then return icons_cached[icon] end
    if not Gtk then Gtk = require("lgi").Gtk end
    local icon = icon.Icon or icon.Exec or icon or 'error'
    local gtk_icon_info = Gtk.IconTheme.lookup_icon(Gtk.IconTheme.get_default(), icon, 24, 0)
    if gtk_icon_info then
        icons_cached[icon] = Gtk.IconInfo.get_filename(gtk_icon_info)
        return icons_cached[icon]
    end
end

-- Get all the content from the *.desktop file.
local function parser(request, content, path, file_enum, task, c)
    local value, ret = {},{}
    local desktop_files = file_enum:next_files_finish(task)
    for _, desktop_file in ipairs(desktop_files) do
        -- if we can read the file
        if desktop_file:get_attribute_as_string('access::can-read') then
            if desktop_file:get_attribute_as_string('standard::is-symlink') then
                -- if the file is symlink
                value = desktop_file:get_attribute_as_string('standard::symlink-target')
            else
                value = path .. desktop_file:get_attribute_as_string('standard::name')
            end
            -- Only files ending in .directory are used; other files are ignored. 
            if  value:find('%.desktop$') then
                local key, data = GLib.KeyFile.new(),{}
                -- Skip translations and comments.
                -- TODO: Enable translations
                key:load_from_file(value, GLib.KeyFileFlags.NONE)
                for k,v in ipairs(key:get_keys('Desktop Entry')) do
                    data[v] = key:get_value('Desktop Entry', v)
                end
                -- Ignored if no Categories defined or NoDisplay is set.
                if data.NoDisplay ~= 'true' and data.Categories then
                    ret[#ret+1] = data
                end
            end
        end
    end
    content:close_async(0, nil)
    request:emit_signal('request::completed', ret or {})
end

-- Use Gio to scan a directory.
local function scan_dir_async(path)
    -- Create new request
    local request = create_request()
    -- Constructs a Gio.File for a given path
    Gio.File.new_for_path(path):enumerate_children_async(
        -- The data types for file attributes.
        'access::can-read,standard::is-symlink,standard::symlink-target,standard::name', 
        Gio.FileQueryInfoFlags.NONE, 0, nil, function(file, task, c)
            local content = file:enumerate_children_finish(task)
            if content then
                content:next_files_async(500, 0, nil, function(file_enum, task, c)
                    parser(request, content, path, file_enum, task, c)
                end)
            end
        end
    )
    return request
end

-- Search *.desktop files at startup.
local i = 1
for _,dir in pairs(module.appdirs) do
    local job = scan_dir_async(dir)
    if job then
        job:connect_signal('request::completed', function(items)
            if items then
                for _,item in ipairs(items) do
                    -- Most items has its own place (defined in module.categories).
                    -- If multiple Main Categories are included in a single desktop entry file,
                    -- the entry may appear more than once in the menu.
                    for category in string.gmatch(item.Categories, '([^;]+)') do
                        if category == "AudioVideo" or category == "Audio" or category == "Video" then
                            table.insert(module.categories.Multimedia, item)
                        elseif category == "Utility" then
                            table.insert(module.categories.Utilities, item)
                        elseif category == "Game" then
                            table.insert(module.categories.Games, item)
                        elseif category == "Network" then
                            table.insert(module.categories.Internet, item)
                        elseif module.categories[category] then
                            table.insert(module.categories[category], item)
                        end
                    end
                end
                -- Cleanup items
                for category in pairs(module.categories) do
                    local d = {}
                    for k,v in ipairs(module.categories[category]) do
                        -- Remove dublicates.
                        if d[v.Name] then table.remove(module.categories[category], k) else d[v.Name] = k end
                        -- Remove deprecated field codes %d, %D, %n, %N, %v, %m.
                        -- Remove %f, %F, %u, %U, %k (a list of files/URL's) field codes too.
                        v.Exec = v.Exec:gsub('%%[dDnNvmfFuUk]', '')
                        -- %i - The Icon key of the desktop entry expanded as two arguments,
                        -- first --icon and then the value of the Icon key.
                        -- Should not expand to any arguments if the Icon key is empty or missing.
                        v.Exec = v.Exec:gsub('%%i', '--icon '..v.Icon)
                        -- TODO: %c - The translated name of the application as listed
                        -- in the appropriate Name key in the desktop entry. (GLib.KeyFileFlags)
                        v.Exec = v.Exec:gsub('%%c', ''..v.Name)
                    end
                end
            end
        end)
    end
end

--- Create a menu popup.
local freedesktop_menu
function module.menu()
    if freedesktop_menu then freedesktop_menu:toggle() return end

    local awful = require("awful")
    local has_radical, radical = pcall(require, "radical")
    
    -- XXX: remove?
    local function caticon(s)
        if s == "Settings" then
            return module.lookup_icon("preferences-system")
        else
            return module.lookup_icon("applications-"..string.lower(s))
        end
    end

    if has_radical then -- Radical menu system
        freedesktop_menu = radical.context({
            style = radical.style.classic, item_style = radical.item.style.classic, arrow_type = radical.base.arrow_type.NONE,
            enable_keyboard = false, disable_markup = true
        })
        
        -- Add items
        for k,v in pairs(module.categories) do
            if #v > 0 then
                freedesktop_menu:add_item({
                    text = k, icon = caticon(k),
                    sub_menu = function()
                        local submenu = radical.context({ style = radical.style.classic, item_style = radical.item.style.classic })
                        for _,item in ipairs(v) do
                            submenu:add_item({
                                text = item.Name, icon = module.lookup_icon(item.Icon),
                                button1 = function()
                                    awful.util.spawn(item.Exec)
                                    freedesktop_menu:toggle()
                                end
                            })
                        end
                        return submenu
                end})
            end
        end

        function freedesktop_menu:toggle()
            freedesktop_menu.visible = not freedesktop_menu.visible
        end
    else -- Default awful menu
        local menu_items = {} -- Table containing the displayed menu items
        for k,v in pairs(module.categories) do
            if #v > 0 then
                local submenu = {}
                for _,item in ipairs(v) do
                    table.insert(submenu, { item.Name, item.Exec, module.lookup_icon(item.Icon) })
                end
                table.insert(menu_items, { k, submenu, caticon(k) })
            end
        end
        freedesktop_menu = awful.menu({ items = menu_items })
    end

    freedesktop_menu:toggle()
end

return setmetatable(module, { __call = function(_, ...) return new(...) end })