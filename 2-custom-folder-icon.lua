local FileManager = require("apps/filemanager/filemanager")
local UIManager = require("ui/uimanager")
local PathChooser = require("ui/widget/pathchooser")
local InfoMessage = require("ui/widget/infomessage")
local logger = require("logger")
local util = require("util")

local CustomFolderIcon = {}

function CustomFolderIcon:init()
    if self.initialized then return end
    self.initialized = true

    logger.info("CustomFolderIcon: Initializing custom folder icon patch...")

    -- 1. Hook ptutil's getFolderCover/findCover to inject our custom icons
    -- We wait a tick to ensure plugins are loaded.
    UIManager:nextTick(function()
        local success, ptutil = pcall(require, "projecttitle.koplugin/ptutil")
        if not success then
            success, ptutil = pcall(require, "ptutil")
        end

        if success and type(ptutil) == "table" and type(ptutil.findCover) == "function" then
            logger.info("CustomFolderIcon: Successfully hooked ptutil.findCover")
            local orig_findCover = ptutil.findCover
            ptutil.findCover = function(dir_path)
                if dir_path then
                    -- Normalizzazione del path rimuovendo gli slash finali
                    local real_path = dir_path:gsub("[/\\]+$", "")
                    local custom_icons = G_reader_settings:readSetting("custom_folder_icons") or {}
                    local custom_cover = custom_icons[real_path]
                    
                    -- Se esiste l'icona e il file immagine è reperibile, usala!
                    if custom_cover and util.fileExists(custom_cover) then
                        return custom_cover
                    end
                end
                -- Fallback alla funzione originale
                return orig_findCover(dir_path)
            end
        else
            logger.warn("CustomFolderIcon: Could not find ptutil to hook. Custom folder icons will not render.")
        end
    end)

    -- 2. Inject context menu buttons into FileManager (e viste collegate)
    local row_func = function(file, is_file, book_props)
        -- Evitiamo di aggiungere il menu sui file ordinari
        if is_file then return nil end

        local real_path = file:gsub("[/\\]+$", "")
        local custom_icons = G_reader_settings:readSetting("custom_folder_icons") or {}
        local has_custom = (custom_icons[real_path] ~= nil)

        return {
            {
                text = "Folder icon",
                callback = function()
                    -- Chiudi il ButtonDialog corrente prima di aprire il PathChooser
                    local current_dialog = UIManager:getTopmostVisibleWidget()
                    if current_dialog and current_dialog.buttons then -- heuristics per capire che è il ButtonDialog!
                        UIManager:close(current_dialog)
                    end

                    local file_filter = function(filename)
                        local fn = filename:lower()
                        return fn:match("%.jpg$") or fn:match("%.jpeg$") or fn:match("%.png$") or fn:match("%.svg$") or fn:match("%.webp$")
                    end

                    -- Apri il PathChooser per scegliere l'immagine
                    local path_chooser = PathChooser:new{
                        path = require("datastorage"):getDataDir(),
                        select_directory = false,
                        select_file = true,
                        show_unsupported = false,
                        file_filter = file_filter,
                        onConfirm = function(selected_file)
                            local icons = G_reader_settings:readSetting("custom_folder_icons") or {}
                            icons[real_path] = selected_file
                            G_reader_settings:saveSetting("custom_folder_icons", icons)
                            
                            UIManager:show(InfoMessage:new{ text = "Custom folder icon applied!" })
                            
                            -- Assicurati che il file chooser venga ricaricato
                            local fm = FileManager.instance
                            if fm and fm.file_chooser then
                                fm.file_chooser:refreshPath()
                            end
                        end,
                    }
                    UIManager:show(path_chooser)
                end
            },
            {
                text = "Remove icon",
                enabled = has_custom,
                callback = function()
                    local current_dialog = UIManager:getTopmostVisibleWidget()
                    if current_dialog and current_dialog.buttons then
                        UIManager:close(current_dialog)
                    end

                    local icons = G_reader_settings:readSetting("custom_folder_icons") or {}
                    icons[real_path] = nil
                    G_reader_settings:saveSetting("custom_folder_icons", icons)
                    
                    UIManager:show(InfoMessage:new{ text = "Custom folder icon removed." })
                    
                    local fm = FileManager.instance
                    if fm and fm.file_chooser then
                        fm.file_chooser:refreshPath()
                    end
                end
            }
        }
    end

    -- Hook statico se esiste, altrimenti fallback rudimentale
    if FileManager.addFileDialogButtons then
        FileManager.addFileDialogButtons(FileManager, "custom_folder_icon", row_func)
        -- Aggiungiamo anche in History, Collections, Search se necessario.
        -- Essendo la classe FileManager, spesso è sufficiente, ma proviamo:
        local FileManagerHistory = require("apps/filemanager/filemanagerhistory")
        local FileManagerCollection = require("apps/filemanager/filemanagercollection")
        local FileManagerFileSearcher = require("apps/filemanager/filemanagerfilesearcher")
        
        for _, widget_class in pairs({FileManagerHistory, FileManagerCollection, FileManagerFileSearcher}) do
            if widget_class then
                pcall(FileManager.addFileDialogButtons, widget_class, "custom_folder_icon", row_func)
            end
        end
    else
        FileManager.file_dialog_added_buttons = FileManager.file_dialog_added_buttons or {}
        table.insert(FileManager.file_dialog_added_buttons, row_func)
    end
end

-- Inject into FileManager initialization to ensure the patch is activated safely
local orig_init = FileManager.init
FileManager.init = function(self, ...)
    CustomFolderIcon:init()
    return orig_init(self, ...)
end

return CustomFolderIcon
