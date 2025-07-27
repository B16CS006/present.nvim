local M = {}

local function create_floating_window(config, enter)
  if enter == nil then
    enter = false
  end

  -- Create a buffer
  local buf = vim.api.nvim_create_buf(false, true) -- No file, scratch buffer

  -- Create the floating window
  local win = vim.api.nvim_open_win(buf, enter, config)

  return { buf = buf, win = win }
end

M.setup = function()
  -- nothing
end

---@class present.Slides
---@field slides present.Slide[]: The slides of file

---@class present.Slide
---@field title string: The title of the slide
---@field body string[]: The body of the slide

--- Takes some lines and parses them
---@param lines string[]: The lines in the buffer
---@return present.Slides
local parse_slides = function(lines)
  local slides = { slides = {} }
  local current_slide = {
    title = "",
    body = {}
  }

  local separator = "^# "

  for _, line in ipairs(lines) do
    -- print(line, "find:", line:find(separator), "|")
    if line:find(separator) then
      if #current_slide.title > 0 then
        table.insert(slides.slides, current_slide)
      end
      current_slide = {
        title = line,
        body = {}
      }
    else
      table.insert(current_slide.body, line)
    end
  end
  table.insert(slides.slides, current_slide)

  return slides
end

local create_window_configuration = function()
  local width = vim.o.columns
  local height = vim.o.lines
  local border_width = 1
  local border_height = 1

  local title_height = 1
  local title_height_total = title_height + 2 * border_height

  local footer_height = 1
  local footer_height_total = footer_height + 0 * border_height

  local body_height_total = height - title_height_total - footer_height_total
  local body_height = body_height_total - 2 * border_height
  local body_width_margin = 8
  local body_width_total = width - 2 * body_width_margin - 2 * border_width


  return {
    background = {
      relative = "editor",
      width = width,
      height = height,
      style = "minimal",
      col = 0,
      row = 0,
      zindex = 1
    },
    header = {
      relative = "editor",
      width = width,
      height = title_height,
      style = "minimal",
      border = "rounded",
      col = 0,
      row = 0,
      zindex = 2
    },
    body = {
      relative = "editor",
      width = body_width_total,
      height = body_height,
      style = "minimal",
      border = { " ", " ", " ", " ", " ", " ", " ", " ", },
      col = body_width_margin,
      row = title_height_total, -- including border
      zindex = 2
    },
    footer = {
      relative = "editor",
      width = width,
      height = footer_height,
      style = "minimal",
      -- TODO: Just a border on top?
      -- border = "rounded",
      col = 0,
      row = title_height_total + body_height_total, -- including border
      zindex = 2
    },
  }
end

local state = {
  title = "", -- filename
  parsed = {},
  current_slide = 1,
  floating_windows = {}
}

local foreach_floating_window = function(cb)
  for name, floating_window in pairs(state.floating_windows) do
    cb(name, floating_window)
  end
end

local present_keymap = function(mode, key, callback)
  vim.keymap.set(mode, key, callback, {
    buffer = state.floating_windows.body.buf
  })
end

M.start_presentation = function(opts)
  opts = opts or {}
  opts.bufnr = opts.bufnr or 0

  local lines = vim.api.nvim_buf_get_lines(opts.bufnr, 0, -1, false)
  state.parsed = parse_slides(lines)
  state.current_slide = 1
  state.title = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(opts.bufnr), ":t")

  local win_config = create_window_configuration()
  state.floating_windows.background = create_floating_window(win_config.background)
  state.floating_windows.header = create_floating_window(win_config.header)
  state.floating_windows.body = create_floating_window(win_config.body, true)
  state.floating_windows.footer = create_floating_window(win_config.footer)

  foreach_floating_window(function(_, floating_window)
    vim.bo[floating_window.buf].filetype = "markdown"
  end)

  local set_slide_content = function(idx)
    local width = vim.o.columns

    local slide = state.parsed.slides[idx]

    local padding = string.rep(" ", (width - #slide.title) / 2)
    local title = padding .. slide.title
    vim.api.nvim_buf_set_lines(state.floating_windows.header.buf, 0, -1, false, { title })
    vim.api.nvim_buf_set_lines(state.floating_windows.body.buf, 0, -1, false, slide.body)

    local footer = string.format(
      " %d / %d | %s",
      state.current_slide,
      #state.parsed.slides,
      state.title
    )
    vim.api.nvim_buf_set_lines(state.floating_windows.footer.buf, 0, -1, false, { footer })
  end

  present_keymap("n", "n", function()
    if (state.current_slide < #state.parsed.slides) then
      state.current_slide = math.min(state.current_slide + 1, #state.parsed.slides)
      set_slide_content(state.current_slide)
    end
  end)

  present_keymap("n", "p", function()
    if (state.current_slide > 1) then
      state.current_slide = math.max(state.current_slide - 1, 1)
      set_slide_content(state.current_slide)
    end
  end)

  present_keymap("n", "q", function()
    vim.api.nvim_win_close(state.floating_windows.body.win, true)
  end)

  local restore = {
    cmdheight = {
      original = vim.o.cmdheight,
      present = 0
    }
  }

  -- set the options we want during presentation
  for option, config in pairs(restore) do
    vim.opt[option] = config.present
  end

  vim.api.nvim_create_autocmd("BufLeave", {
    buffer = state.floating_windows.body.buf,
    callback = function()
      -- reset back the options
      for option, config in pairs(restore) do
        vim.opt[option] = config.original
      end
      foreach_floating_window(function(_, floating_window)
        pcall(vim.api.nvim_win_close, floating_window.win, true)
      end)
    end
  })

  vim.api.nvim_create_autocmd("VimResized", {
    group = vim.api.nvim_create_augroup("present-resized", {}),
    callback = function()
      if not vim.api.nvim_win_is_valid(state.floating_windows.body.win) or state.floating_windows.body.win == nil then
        return
      end

      local updated_win_config = create_window_configuration()
      foreach_floating_window(function(name, floating_window)
        vim.api.nvim_win_set_config(floating_window.win, updated_win_config[name])
      end)
      set_slide_content(state.current_slide)
    end
  })

  set_slide_content(state.current_slide)
end

-- M.start_presentation({ bufnr = 309 })

M._parse_slides = parse_slides

return M
