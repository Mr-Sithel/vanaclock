addon.name    = 'vanaclock'
addon.author  = 'Sithel'
addon.version = '1.0.0'
addon.desc    = 'Displays a Vana clock, moon phases, and day transition images.'

require('common')
local chat      = require('chat')
local fonts     = require('fonts')
local scaling   = require('scaling')
local settings  = require('settings')
local imgui     = require('imgui')
local prims     = require('primitives')

local default_settings = T{
    theme = 'gold',
    font = T{
        visible = true,
        font_family = 'Cinzel Bold',
        font_height = scaling.scale_f(18),
        color = 0xFFFFFFFF,
        position_x = 380,
        position_y = 400,
        background = T{
            visible = false,
            color = 0x80000000, -- 50% Alpha Black Background
        },
    },
    moon_font = T{
        visible = false,
        font_family = 'Cinzel Bold',
        font_height = scaling.scale_f(18),
        color = 0xFF69DCA3,
        position_x = 370,
        position_y = 360,
        background = T{
            visible = false,
            color = 0x80000000,
        },
    },
    images_enabled           = true,
    moon_flash_on_day_change = false,
    fade_delay               = 4,
    mute_sound               = false,
    lightsday_alert          = false, -- Toggle for 21:00 Lightsday advance warning
    position_x               = -5,
    position_y               = 170,
    visible                  = false,
}

local clock = T{
    settings  = settings.load(default_settings),
    font      = nil,
    moon_font = nil,
}

local function loadTheme(name)
    return require('themes/theme_' .. name)
end

local current_loaded_theme_name = nil
local theme = nil

local function updateActiveTheme()
    local target_theme = clock.settings.theme or 'gold'
    if current_loaded_theme_name ~= target_theme then
        theme = loadTheme(target_theme)
        current_loaded_theme_name = target_theme
    end
end

-- Fade / Image Popup tracking
local fadeTimer = 0
local imgObject = nil

-- ImGui Window State
local config_open = { false }

-- Vana Time State Tracking
local lastDay  = -1
local lastHour = -1

-- Vana Days & Moon Phases
local vanaDays = {
    [0] = 'Firesday',
    [1] = 'Earthsday',
    [2] = 'Watersday',
    [3] = 'Windsday',
    [4] = 'Iceday',
    [5] = 'Lightningday',
    [6] = 'Lightsday',
    [7] = 'Darksday'
}

local moonPhases = {
    [0]  = 'New Moon',
    [1]  = 'Waxing Crescent',
    [2]  = 'Waxing Crescent',
    [3]  = 'First Quarter',
    [4]  = 'Waxing Gibbous',
    [5]  = 'Waxing Gibbous',
    [6]  = 'Full Moon',
    [7]  = 'Waning Gibbous',
    [8]  = 'Waning Gibbous',
    [9]  = 'Last Quarter',
    [10] = 'Waning Crescent',
    [11] = 'Waning Crescent',
}

local vanatimePointer = ashita.memory.find('FFXiMain.dll', 0, 'B0015EC390518B4C24088D4424005068', 0x34, 0)

-- Helper Functions
local function GetDayImagePath(dayName)
    return string.format('%s/Weekdays/%s.png', addon.path, dayName)
end

local function GetSoundPath()
    return string.format('%s/Alerts/alert.wav', addon.path)
end

local function PlayAlertSound()
    if not clock.settings.mute_sound then
        ashita.misc.play_sound(GetSoundPath())
    end
end

local function TriggerDayChange(dayStr, showImage)
    if showImage == nil then showImage = true end

    -- Sound alert on day change
    PlayAlertSound()

    -- Set fade timer for popups and/or flashing moon text
    fadeTimer = os.clock() + (clock.settings.fade_delay or 4)

    -- Display day popup image if enabled
    if showImage and clock.settings.images_enabled and imgObject then
        imgObject:SetTextureFromFile(GetDayImagePath(dayStr))
    end
end

local function SyncAndSaveSettings()
    if clock.font ~= nil then
        clock.settings.font.position_x = clock.font.position_x
        clock.settings.font.position_y = clock.font.position_y
    end
    if clock.moon_font ~= nil then
        clock.settings.moon_font.position_x = clock.moon_font.position_x
        clock.settings.moon_font.position_y = clock.moon_font.position_y
    end
    if imgObject ~= nil then
        clock.settings.position_x = imgObject.position_x
        clock.settings.position_y = imgObject.position_y
    end
    settings.save()
end

-- Settings & Login
settings.register('settings', 'settings_update', function(new_settings)
    if (new_settings ~= nil) then
        clock.settings = new_settings
    end

    if (clock.font ~= nil) then
        clock.font:apply(clock.settings.font)
    end
    if (clock.moon_font ~= nil) then
        clock.moon_font:apply(clock.settings.moon_font)
    end
    updateActiveTheme()
end)

ashita.events.register('login', 'login_cb', function()
    clock.settings = settings.load(default_settings)
    if (clock.font ~= nil) then
        clock.font:apply(clock.settings.font)
    end
    if (clock.moon_font ~= nil) then
        clock.moon_font:apply(clock.settings.moon_font)
    end
    updateActiveTheme()
end)

-- Load & Unload
ashita.events.register('load', 'load_cb', function ()
    clock.font      = fonts.new(clock.settings.font)
    clock.moon_font = fonts.new(clock.settings.moon_font)
    imgObject       = prims.new(clock.settings)
    updateActiveTheme()
end)

ashita.events.register('unload', 'unload_cb', function ()
    SyncAndSaveSettings()

    if (clock.font ~= nil) then
        clock.font:destroy()
        clock.font = nil
    end
    if (clock.moon_font ~= nil) then
        clock.moon_font:destroy()
        clock.moon_font = nil
    end
end)

-- Display Render
ashita.events.register('d3d_present', 'present_cb', function ()
    -- Image Overlay Render
    local isFading = os.clock() < fadeTimer
    local delay = clock.settings.fade_delay or 4
    local fadeAlpha = isFading and ((fadeTimer - os.clock()) / delay) or 0

    if imgObject then
        if isFading and clock.settings.images_enabled then
            imgObject.visible = true
            local highBits = math.floor(fadeAlpha * 255)
            imgObject.color = bit.lshift(highBits, 24) + 0x00FFFFFF
        else
            imgObject.visible = false
        end
    end

    -- Vana'diel Time Calculations & Day Change Triggers
    if vanatimePointer and vanatimePointer ~= 0 then
        local basePointer = ashita.memory.read_uint32(vanatimePointer)
        if basePointer ~= 0 then
            local timestamp = ashita.memory.read_uint32(basePointer + 0x0C)
            local ts = (timestamp + 92514960) * 25
            local hour = math.floor((ts / 3600) % 24)
            local minute = math.floor((ts / 60) % 60)
            local dayNum = math.floor(ts / 86400)
            local dayStr = vanaDays[dayNum % 8] or 'Unknown'

            -- Detect Day Change
            if lastDay ~= -1 and lastDay ~= (dayNum % 8) then
                TriggerDayChange(dayStr, true)
            end

            -- Lightsday 21:00 Warning (3 game hours before Darksday)
            local allowLightsdayAlert = clock.settings.lightsday_alert
            if allowLightsdayAlert == nil then allowLightsdayAlert = true end

            if allowLightsdayAlert and (dayNum % 8) == 6 and hour == 21 and lastHour == 20 then
                -- Trigger sound & fade timer
                TriggerDayChange(dayStr, false)
            end

            lastDay  = dayNum % 8
            lastHour = hour

            -- Update Clock Text
            if clock.font ~= nil then
                clock.font.visible = clock.settings.font.visible
                if clock.settings.font.visible then
                    clock.font.text = string.format(' %s - %02d:%02d ', dayStr, hour, minute)
                else
                    clock.font.text = ''
                end
            end

            -- Update Moon Phase Text (Always Visible OR Flashing on Day Change/Alerts)
            if clock.moon_font ~= nil then
                local isMoonVisible = clock.settings.moon_font.visible
                local isFlashing = clock.settings.moon_flash_on_day_change and isFading

                if isMoonVisible or isFlashing then
                    clock.moon_font.visible = true

                    local mphase = (dayNum + 26) % 84
                    local mpercent = (((42 - mphase) * 100) / 42)
                    if mpercent < 0 then mpercent = math.abs(mpercent) end
                    local moonPercent = math.floor(mpercent + 0.5)

                    local moonIdx = 0
                    if mphase >= 38 then
                        moonIdx = math.floor((mphase - 38) / 7)
                    else
                        moonIdx = math.floor((mphase + 46) / 7)
                    end

                    local moonStr = moonPhases[moonIdx] or 'Unknown'
                    clock.moon_font.text = string.format(' %s %d%% ', moonStr, moonPercent)

                    -- Apply Dynamic Alpha when Flashing (if not permanently visible)
                    if isFlashing and not isMoonVisible then
                        local baseColor = clock.settings.moon_font.color
                        local rgb = bit.band(baseColor, 0x00FFFFFF)
                        local calculatedAlpha = math.floor(fadeAlpha * 255)

                        clock.moon_font.color = bit.lshift(calculatedAlpha, 24) + rgb
                    else
                        clock.moon_font.color = clock.settings.moon_font.color
                    end
                else
                    clock.moon_font.visible = false
                    clock.moon_font.text = ''
                end
            end
        end
    end

    -- 3. ImGui Config Window
    if not config_open[1] then return end

    updateActiveTheme()
    if not theme then return end

    theme.push()

    local flags = bit.bor(ImGuiWindowFlags_NoResize, ImGuiWindowFlags_AlwaysAutoResize)
    if imgui.Begin('VanaClock Settings', config_open, flags) then

        -- UI Theme Selection
        imgui.Text("UI Theme")
        imgui.SameLine()
        imgui.TextDisabled("(?)")
        if imgui.IsItemHovered() then
            imgui.SetTooltip("Choose a color theme for the VanaClock settings window.")
        end

        local themes  = { 'gold', 'blue', 'red', 'green', 'purple', 'ice', 'gray' }
        local current = clock.settings.theme or 'gold'

        imgui.PushItemWidth(140)
        if imgui.BeginCombo("##vc_theme_select", current) then
            for _, t in ipairs(themes) do
                local selected = (t == current)
                if imgui.Selectable(t, selected) then
                    clock.settings.theme = t
                    SyncAndSaveSettings()
                    updateActiveTheme()
                end
                if selected then imgui.SetItemDefaultFocus() end
            end
            imgui.EndCombo()
        end
        imgui.PopItemWidth()

        imgui.Spacing()
        imgui.Separator()
        imgui.Spacing()

        -- Clock Visible Checkbox
        local vis_table = { clock.settings.font.visible }
        if imgui.Checkbox('Vana\'diel Clock Display', vis_table) then
            clock.settings.font.visible = vis_table[1]
            if clock.font then clock.font.visible = vis_table[1] end
            SyncAndSaveSettings()
        end
        imgui.SameLine()
        imgui.TextDisabled('(?)')
        if imgui.IsItemHovered() then
            imgui.SetTooltip('Displays the current Vana\'diel time.')
        end

        -- Moon Phase Checkbox
        local moon_vis_table = { clock.settings.moon_font.visible }
        if imgui.Checkbox('Moon Phase Display (Always On)', moon_vis_table) then
            clock.settings.moon_font.visible = moon_vis_table[1]
            if clock.moon_font then clock.moon_font.visible = moon_vis_table[1] end
            SyncAndSaveSettings()
        end
        imgui.SameLine()
        imgui.TextDisabled('(?)')
        if imgui.IsItemHovered() then
            imgui.SetTooltip('Displays the current Vana\'diel moon phase and percentage continuously.')
        end

        -- Flash Moon Phase Checkbox
        local flash_table = { clock.settings.moon_flash_on_day_change == true }
        if imgui.Checkbox('Flash Moon Phase on Day Change / Alerts', flash_table) then
            clock.settings.moon_flash_on_day_change = flash_table[1]
            SyncAndSaveSettings()
        end
        imgui.SameLine()
        imgui.TextDisabled('(?)')
        if imgui.IsItemHovered() then
            imgui.SetTooltip('Fades in the moon phase display briefly whenever a new Vana\'diel day starts or an alert triggers.')
        end

        imgui.Spacing()
        imgui.Separator()
        imgui.Spacing()

        -- Clock Font Size
        local font_size = { math.floor(clock.settings.font.font_height) }
        if imgui.SliderInt('Clock Font Size', font_size, 8, 48) then
            clock.settings.font.font_height = font_size[1]
            if clock.font then clock.font:apply(clock.settings.font) end
            SyncAndSaveSettings()
        end

        -- Moon Font Size
        local moon_font_size = { math.floor(clock.settings.moon_font.font_height) }
        if imgui.SliderInt('Moon Font Size', moon_font_size, 8, 48) then
            clock.settings.moon_font.font_height = moon_font_size[1]
            if clock.moon_font then clock.moon_font:apply(clock.settings.moon_font) end
            SyncAndSaveSettings()
        end

        -- Clock Font Color
        local c = clock.settings.font.color
        local a = bit.band(bit.rshift(c, 24), 0xFF) / 255.0
        local r = bit.band(bit.rshift(c, 16), 0xFF) / 255.0
        local g = bit.band(bit.rshift(c, 8),  0xFF) / 255.0
        local b = bit.band(c, 0xFF) / 255.0

        local col_table = { r, g, b, a }
        if imgui.ColorEdit4('Clock Font Color', col_table) then
            local new_a = math.floor(col_table[4] * 255)
            local new_r = math.floor(col_table[1] * 255)
            local new_g = math.floor(col_table[2] * 255)
            local new_b = math.floor(col_table[3] * 255)

            clock.settings.font.color = bit.lshift(new_a, 24) + bit.lshift(new_r, 16) + bit.lshift(new_g, 8) + new_b
            if clock.font then clock.font:apply(clock.settings.font) end
            SyncAndSaveSettings()
        end

        -- Moon Font Color
        local mc = clock.settings.moon_font.color
        local ma = bit.band(bit.rshift(mc, 24), 0xFF) / 255.0
        local mr = bit.band(bit.rshift(mc, 16), 0xFF) / 255.0
        local mg = bit.band(bit.rshift(mc, 8),  0xFF) / 255.0
        local mb = bit.band(mc, 0xFF) / 255.0

        local mcol_table = { mr, mg, mb, ma }
        if imgui.ColorEdit4('Moon Font Color', mcol_table) then
            local new_a = math.floor(mcol_table[4] * 255)
            local new_r = math.floor(mcol_table[1] * 255)
            local new_g = math.floor(mcol_table[2] * 255)
            local new_b = math.floor(mcol_table[3] * 255)

            clock.settings.moon_font.color = bit.lshift(new_a, 24) + bit.lshift(new_r, 16) + bit.lshift(new_g, 8) + new_b
            if clock.moon_font then clock.moon_font:apply(clock.settings.moon_font) end
            SyncAndSaveSettings()
        end

        -- Font Background Checkbox
        local bg_enabled = (clock.settings.font.background and clock.settings.font.background.visible) == true
        local bg_table = { bg_enabled }
        if imgui.Checkbox('Background Color (Black)', bg_table) then
            local is_bg_visible = bg_table[1]

            if not clock.settings.font.background then clock.settings.font.background = T{} end
            if not clock.settings.moon_font.background then clock.settings.moon_font.background = T{} end

            clock.settings.font.background.visible = is_bg_visible
            clock.settings.moon_font.background.visible = is_bg_visible

            if clock.font then clock.font:apply(clock.settings.font) end
            if clock.moon_font then clock.moon_font:apply(clock.settings.moon_font) end

            SyncAndSaveSettings()
        end
        imgui.SameLine()
        imgui.TextDisabled('(?)')
        if imgui.IsItemHovered() then
            imgui.SetTooltip('Toggles the dark background box behind the clock and moon text on or off.')
        end

        imgui.Spacing()
        imgui.Separator()
        imgui.Spacing()

        -- Sound Alert Settings
        local mute_table = { clock.settings.mute_sound }
        if imgui.Checkbox('Mute All Sound Alerts', mute_table) then
            clock.settings.mute_sound = mute_table[1]
            SyncAndSaveSettings()
        end
        imgui.SameLine()
        imgui.TextDisabled('(?)')
        if imgui.IsItemHovered() then
            imgui.SetTooltip('Mutes all day transition audio alerts.')
        end

        local ld_alert_table = { clock.settings.lightsday_alert == nil and true or clock.settings.lightsday_alert }
        if imgui.Checkbox('Lightsday 21:00 Warning', ld_alert_table) then
            clock.settings.lightsday_alert = ld_alert_table[1]
            SyncAndSaveSettings()
        end
        imgui.SameLine()
        imgui.TextDisabled('(?)')
        if imgui.IsItemHovered() then
            imgui.SetTooltip('In game 3 hour warning before Lightsday ends for Movalpolos Water refresh. Plays audio alert and triggers moon phase flash.')
        end

        imgui.Spacing()

        -- Image Popup Settings
        local img_table = { clock.settings.images_enabled }
        if imgui.Checkbox('Enable Day Popups', img_table) then
            clock.settings.images_enabled = img_table[1]
            SyncAndSaveSettings()
        end
        imgui.SameLine()
        imgui.TextDisabled('(?)')
        if imgui.IsItemHovered() then
            imgui.SetTooltip('Displays game day pop up images.')
        end

        imgui.Spacing()

        -- Fade Delay Slider
        imgui.Text('Fade Delay (sec)')
        local fade_table = { clock.settings.fade_delay or 4 }
        imgui.PushItemWidth(200)
        if imgui.SliderInt('##FadeDelay', fade_table, 1, 15) then
            clock.settings.fade_delay = fade_table[1]
            SyncAndSaveSettings()
        end
        imgui.SameLine()
        imgui.TextDisabled('(?)')
        if imgui.IsItemHovered() then
            imgui.SetTooltip('Game day image & moon flash fade delay in seconds. \n Set to 4 for default')
        end
        imgui.PopItemWidth()

        imgui.Spacing()
        imgui.Separator()
        imgui.Spacing()

        -- Test Alert Button
        if imgui.Button('Test Popup & Sound') then
            local currentDayStr = vanaDays[lastDay] or 'Firesday'
            TriggerDayChange(currentDayStr, true)
        end

        -- Save Positions Button
        imgui.SameLine()
        if imgui.Button('Save Positions') then
            SyncAndSaveSettings()
            print(chat.header(addon.name):append(chat.message('Clock & Moon settings and positions saved.')))
        end

        imgui.End()
    end

    theme.pop()
end)

-- Commands
ashita.events.register('command', 'command_cb', function (e)
    local args = e.command:args()
    if #args == 0 then return end

    if args[1]:lower() == '/vanaclock' or args[1]:lower() == '/vc' then
        e.blocked = true

        if #args >= 2 then
            local subCommand = args[2]:lower()

            -- /vc help
            if subCommand == 'help' then
                print(chat.header(addon.name):append(chat.message('\31\207Commands:')));
                print('\31\207 /vc ui       \31\8 - Shows Config UI.');
                print('\31\207 /vc config   \31\8 - Shows Config UI.');
                print('\31\207 /vc  save    \31\8 - Save Clock & Moon position settings.');
                return
            end

            -- /vc ui or /vc config - Open settings GUI
            if subCommand == 'ui' or subCommand == 'config' then
                config_open[1] = not config_open[1]
                return
            end

            -- /vc save
            if subCommand == 'save' then
                SyncAndSaveSettings()
                print(chat.header(addon.name):append(chat.message('Clock & Moon settings and positions saved.')))
                return
            end
        end

        -- Default behavior: Toggle clock visibility state
        clock.settings.font.visible = not clock.settings.font.visible
        if clock.font ~= nil then
            clock.font.visible = clock.settings.font.visible
        end
        SyncAndSaveSettings()

        local status = clock.settings.font.visible and 'enabled' or 'disabled'
        print(chat.header(addon.name):append(chat.message('Clock display has been ' .. status .. '.')))
    end
end)