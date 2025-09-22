local M = {}

local config = {
    max_history_commands = 10,
    delete_hotkey = "<C-d>",
    rename_hotkey = "<C-r>",
    commands_file = vim.fn.stdpath("config") .. "/lum_commands.json",
    name_separator = " : "
}

-- Загрузка сохраненных команд из файла
local function load_commands()
    local file = io.open(config.commands_file, "r")
    if not file then return {} end
    
    local content = file:read("*a")
    file:close()
    
    if content == "" then return {} end
    
    local ok, commands = pcall(vim.json.decode, content)
    if not ok then return {} end
    
    return commands
end

-- Сохранение команд в файл
local function save_commands(commands)
    local file = io.open(config.commands_file, "w")
    if not file then return false end
    
    local content = vim.json.encode(commands)
    file:write(content)
    file:close()
    return true
end

-- Получение истории команд (исключая команды плагина)
local function get_command_history()
    local commands = {}
    local seen = {}
    
    local mc = config.max_history_commands
    for i = 1, mc do
        local cmd = vim.fn.histget("cmd", i * -1)
        if cmd and cmd ~= "" and cmd ~= "LumQuickCommandsAdd" and cmd ~= "LumQuickCommandsShow" and not seen[cmd] then
            table.insert(commands, cmd)
            seen[cmd] = true
        end
    end
    
    return commands
end

-- Функция добавления команд
function M.add_command()
    local commands_history = get_command_history()
    local saved_commands = load_commands()
    local saved_commands_set = {}
    
    -- Создаем множество сохраненных команд для быстрой проверки
    for _, cmd in ipairs(saved_commands) do
        if type(cmd) == "table" then
            saved_commands_set[cmd.command] = true
        else
            saved_commands_set[cmd] = true
        end
    end
    
    -- Фильтруем команды, которые уже сохранены
    local available_commands = {}
    for _, cmd in ipairs(commands_history) do
        if not saved_commands_set[cmd] then
            table.insert(available_commands, cmd)
        end
    end
    
    if #available_commands == 0 then
        vim.notify("Нет новых команд для добавления", vim.log.levels.INFO)
        return
    end
    
    -- Настройка picker для Telescope
    local actions = require("telescope.actions")
    local action_state = require("telescope.actions.state")
    local finders = require("telescope.finders")
    local pickers = require("telescope.pickers")
    local conf = require("telescope.config").values
    
    pickers.new({
        -- Максимально отключаем все фильтры
        disable_devicons = true,
		file_ignore_patterns = false,
        sorting_strategy = "ascending",
        ignore_filename = false,
        no_ignore = true,
        no_ignore_parent = true,
        hidden = true,
    }, {
        prompt_title = "Выберите команду для добавления",
        finder = finders.new_table({
            results = available_commands,
            entry_maker = function(entry)
                return {
                    value = entry,
                    display = entry,
                    ordinal = entry,
                    valid = true
                }
            end
        }),
        -- Используем кастомный sorter без фильтрации
        sorter = conf.generic_sorter(opts),
        attach_mappings = function(prompt_bufnr, map)
            -- Стандартное действие - добавление команды
            actions.select_default:replace(function()
                local selection = action_state.get_selected_entry()
                actions.close(prompt_bufnr)
                if selection then
                    local command = selection.value
                    table.insert(saved_commands, command)
                    save_commands(saved_commands)
                    vim.notify("Команда добавлена: " .. command, vim.log.levels.INFO)
                end
            end)
            
            -- Хоткей для переименования/указания названия
            map("i", config.rename_hotkey, function()
                local selection = action_state.get_selected_entry()
                if selection then
                    local command = selection.value
                    vim.ui.input({
                        prompt = "Название для команды: ",
                        default = command
                    }, function(new_name)
                        if new_name and new_name ~= "" then
                            actions.close(prompt_bufnr)
                            table.insert(saved_commands, {
                                name = new_name,
                                command = command
                            })
                            save_commands(saved_commands)
                            vim.notify("Команда добавлена: " .. new_name, vim.log.levels.INFO)
                        end
                    end)
                end
            end)
            
            return true
        end,
    }):find()
end

-- Функция показа и выполнения команд
function M.show_commands()
    local saved_commands = load_commands()
    
    if #saved_commands == 0 then
        vim.notify("Нет сохраненных команд", vim.log.levels.INFO)
        return
    end
    
    local actions = require("telescope.actions")
    local action_state = require("telescope.actions.state")
    local finders = require("telescope.finders")
    local pickers = require("telescope.pickers")
	local conf = require("telescope.config").values
    
    -- Преобразуем команды в отображаемый формат
    local display_commands = {}
    for _, cmd in ipairs(saved_commands) do
        if type(cmd) == "table" then
            table.insert(display_commands, {
                display = cmd.name .. config.name_separator .. cmd.command,
                value = cmd.command,
                name = cmd.name
            })
        else
            table.insert(display_commands, {
                display = cmd,
                value = cmd,
                name = nil
            })
        end
    end
    
    pickers.new({
        -- Максимально отключаем все фильтры
        disable_devicons = true,
        sorting_strategy = "ascending",
        ignore_filename = false,
		file_ignore_patterns = false,
        no_ignore = true,
        no_ignore_parent = true,
        hidden = true,
    }, {
        prompt_title = "Сохраненные команды",
        finder = finders.new_table({
            results = display_commands,
            entry_maker = function(entry)
                return {
                    value = entry.value,
                    display = entry.display,
                    ordinal = entry.display,
                    name = entry.name,
                    valid = true
                }
            end
        }),
        -- Используем кастомный sorter без фильтрации
        sorter = conf.generic_sorter({}),
        attach_mappings = function(prompt_bufnr, map)
            -- Стандартное действие - выполнение команды
            actions.select_default:replace(function()
                local selection = action_state.get_selected_entry()
                actions.close(prompt_bufnr)
                if selection then
                    local command = selection.value
                    vim.cmd(command)
                end
            end)
            
            -- Хоткей для удаления команды
            map("i", config.delete_hotkey, function()
                local selection = action_state.get_selected_entry()
                if selection then
                    local command_to_remove = selection.value
                    local index_to_remove = nil
                    
                    -- Находим индекс команды для удаления
                    for i, cmd in ipairs(saved_commands) do
                        local current_cmd = type(cmd) == "table" and cmd.command or cmd
                        if current_cmd == command_to_remove then
                            index_to_remove = i
                            break
                        end
                    end
                    
                    if index_to_remove then
                        table.remove(saved_commands, index_to_remove)
                        save_commands(saved_commands)
                        vim.notify("Команда удалена", vim.log.levels.INFO)
                        
                        -- Обновляем список
                        require("telescope.actions").close(prompt_bufnr)
                        vim.defer_fn(function()
                            M.show_commands()
                        end, 50)
                    end
                end
            end)
            
            return true
        end,
    }):find()
end

-- Функция настройки
function M.setup(user_config)
    config = vim.tbl_deep_extend("force", config, user_config or {})
end

-- Создание команд Vim
vim.api.nvim_create_user_command("LumQuickCommandsAdd", M.add_command, {})
vim.api.nvim_create_user_command("LumQuickCommandsShow", M.show_commands, {})

return M
