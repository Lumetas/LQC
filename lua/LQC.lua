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
    
    -- Получаем всю историю команд
    local history_count = vim.fn.histnr(":")
    
    for i = history_count, math.max(1, history_count - config.max_history_commands), -1 do
        local cmd = vim.fn.histget(":", i)
        if cmd and cmd ~= "" and cmd ~= " " then
            -- Исключаем команды плагина и проверяем уникальность
            if not cmd:match("^LumQuickCommands") and not seen[cmd] then
                table.insert(commands, cmd)
                seen[cmd] = true
            end
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
    
    pickers.new({}, {
        prompt_title = "Выберите команду для добавления",
        finder = finders.new_table({
            results = available_commands,
        }),
        sorter = conf.generic_sorter({}),
        attach_mappings = function(prompt_bufnr, map)
            -- Стандартное действие - добавление команды
            actions.select_default:replace(function()
                local selection = action_state.get_selected_entry()
                actions.close(prompt_bufnr)
                if selection then
                    local command = selection[1]
                    table.insert(saved_commands, command)
                    save_commands(saved_commands)
                    vim.notify("Команда добавлена: " .. command, vim.log.levels.INFO)
                end
            end)
            
            -- Хоткей для переименования/указания названия
            map("i", config.rename_hotkey, function()
                local selection = action_state.get_selected_entry()
                if selection then
                    local command = selection[1]
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
            table.insert(display_commands, cmd.name .. config.name_separator .. cmd.command)
        else
            table.insert(display_commands, cmd)
        end
    end
    
    pickers.new({}, {
        prompt_title = "Сохраненные команды",
        finder = finders.new_table({
            results = display_commands,
        }),
        sorter = conf.generic_sorter({}),
        attach_mappings = function(prompt_bufnr, map)
            -- Стандартное действие - выполнение команды
            actions.select_default:replace(function()
                local selection = action_state.get_selected_entry()
                actions.close(prompt_bufnr)
                if selection then
                    local display_text = selection[1]
                    local command = display_text
                    
                    -- Извлекаем команду если есть название
                    if display_text:match(config.name_separator) then
						command = display_text:match(config.name_separator .. "(.+)$")
                    end
                    
                    vim.cmd(command)
                end
            end)
            
            -- Хоткей для удаления команды
            map("i", config.delete_hotkey, function()
                local selection = action_state.get_selected_entry()
                if selection then
                    local display_text = selection[1]
                    local index_to_remove = nil
                    
                    -- Находим индекс команды для удаления
                    for i, cmd in ipairs(saved_commands) do
                        local display_cmd = type(cmd) == "table" and (cmd.name .. config.name_separator .. cmd.command) or cmd
                        if display_cmd == display_text then
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
