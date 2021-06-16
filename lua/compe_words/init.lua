local compe = require"compe"
local compe_config = require"compe.config"

local source_name = "words"

local script_dir = debug.getinfo(1).source:match("^@?(.*)/")
local default_cache_dir = script_dir .. "/cache"

--- Additional options
local default_config = {
  min_word_size = 4, -- Drop candidates smaller than the value in advance.
  -- TODO: reduce candidates out of this source as `max_num_results`.
  max_num_results = 6,
  cache_dir = default_cache_dir,
  paths = {
    "https://github.com/first20hours/google-10000-english/raw/master/google-10000-english-usa-no-swears-short.txt",
    "https://github.com/first20hours/google-10000-english/raw/master/google-10000-english-usa-no-swears-medium.txt",
    "https://github.com/first20hours/google-10000-english/raw/master/google-10000-english-usa-no-swears-long.txt",
  },
}

local should_disable_source = false
local disable_source = function()
  should_disable_source = true
end

--- Once abort, disable this resource. To reload, restart current vim instance.
---@param callback function
---@return function
local safe = function(callback)
  return function(...)
    local success, result = pcall(callback, ...)
    if not success then
      disable_source()
      error("Please restart vim/nvim to reload `" .. source_name .. "` source" .. result)
    end
    return result
  end
end

---@return table<string, any> # The default items would be used at keys where user doesn't set value.
local get_config = function()
  local user_config = compe_config.get().source[source_name] or true
  user_config = user_config == true and {} or user_config
  local config = {}
  for k, v in pairs(default_config) do
    config[k] = user_config[k] or v
  end
  return config
end

local get_cache_dir = safe(function()
  ---@note vim.fn.expand("<sfile>") instead doesn't work here.
  local path = get_config().cache_dir
  if vim.fn.filereadable(path) == 1 then
    error("Abort. You're trying to set `cache_dir` onto the existing file: " .. path)
  elseif vim.fn.isdirectory(path) == 0 then
    local answer = vim.fn.input("[nvim-compe] The cache dir for `words` source doesn't exist. Create? [Y/n] (at " .. path ..")")
    if vim.regex([[y\%[es]\c]]):match_str(answer) then
      local success = vim.fn.mkdir(path, "p") == 1
      if success then
        print("[nvim-compe] Created " .. path)
      else
        error("Abort. Fail to create the directory: " .. path)
      end
    else
      error("Abort. Your imput: " .. answer)
    end
  end
  return path
end)

local download_file = safe(function(remote, dest)
  if vim.fn.filereadable(dest) == 1 or vim.fn.isdirectory(dest) == 1 then
    error("Abort. `" .. dest .. "` has already existed!")
  end
  if vim.fn.executable("curl") == 1 then
    vim.fn.system("curl " .. remote .. " --silent --location > " .. dest)
    if vim.v.shell_error ~= 0 then
      error("You set a wrong URL: " .. remote)
    end
  else
    error("You require `curl` to install " .. remote)
  end
end)

--- Convert `foo/bar/baz/qux.ext` into `foo%bar%baz%qux.ext`.
local convert_into_undofile_format = function(path)
  return path:gsub("/", "%%")
end

local get_dicts = function()
  local paths = get_config().paths or {}
  local cache_dir = get_cache_dir()
  local dicts = {}
  for _, path in pairs(paths) do
    local is_remote = path:match("^https://")
    if is_remote then
      local path_without_protocol = path:match("^https://(.*)")
      local fname = convert_into_undofile_format(path_without_protocol)
      local local_path = cache_dir .. "/" .. fname
      if vim.fn.filereadable(local_path) == 0 then
        print("[nvim-compe] `" .. path .. "` is not installed! Installing it to `" .. local_path .. "`...")
        download_file(path, local_path)
      end
      path = local_path
    end
    table.insert(dicts, path)
  end
  return dicts
end

--- Return completion items with capitalized one.
local get_items = function()
  local items = {}
  local files = get_dicts()
  local min_word_size = get_config().min_word_size
  for _, file in pairs(files) do
    for word in io.lines(file) do
      if #word >= min_word_size then
        local item = {
          word = word,
        }
        table.insert(items, item)
        local capitalized = word:sub(1, 1):upper() .. word:sub(2)
        table.insert(items, capitalized)
      end
    end
  end
  return items
end

local Source = {}

function Source:get_metadata()
  return {
    priority = 5,
    dup = 0,
    menu = "[Words]",
  }
end

function Source:determine(context)
  local trigger = compe.helper.determine(context, {
    -- The offset is supposed to be set at such X as foo_Xbar or fooXBar.
    keyword_pattern = [[\%(\%(\u\l\+\)\|\%(\l\+\)\)$]],
  })
  return trigger
end

function Source:complete(context)
  if should_disable_source then return end
  self._items = self._items or get_items()
  context.callback({
    items = self._items,
    incomplete = true,
  })
end

return Source
