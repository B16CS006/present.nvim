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
---@field blocks present.Block[]: A codeblock inside of a slide

---@class present.Block
---@field language string: The language of the codeblock
---@field body string: The body of the codeblock

--- Takes some lines and parses them
---@param lines string[]: The lines in the buffer
---@return present.Slides
local parse_slides = function(lines)
  local slides = { slides = {} }
  local current_slide = {
    title = "",
    body = {},
    blocks = {}
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
        body = {},
        blocks = {}
      }
    else
      table.insert(current_slide.body, line)
    end
  end
  table.insert(slides.slides, current_slide)

  for _, slide in ipairs(slides.slides) do
    local block = {
      language = nil,
      body = "",
    }
    local inside_block = false
    for _, line in ipairs(slide.body) do
      if vim.startswith(line, "```") then
        if not inside_block then
          inside_block = true
          block.language = string.sub(line, 4)
        else
          inside_block = false
          block.body = vim.trim(block.body)
          table.insert(slide.blocks, block)
          block = {}
        end
      else
        if inside_block then
          -- OK, we are inside a current markdown block
          -- but it is not one of the guards
          -- so insert this text
          block.body = block.body .. line .. "\n"
        end
      end
    end
  end

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

  present_keymap("n", "X", function()
    local slide = state.parsed.slides[state.current_slide]
    -- TODO: Make a way for people to execute this for other languages
    local block = slide.blocks[1]
    if not block then
      print("No blocks on this page")
      return
    end

    local chunk = loadstring(block.body)
    if chunk == nil then
      print("<<<chunk is nil on loadstring>>>")
      return
    end

    -- Override the default print function, the capture all the output
    -- Store the original print function
    local original_print = print

    -- Table to capture print messages
    local output = { "", "# Code", "", "```" .. block.language }
    vim.list_extend(output, vim.split(block.body, "\n"))
    table.insert(output, "```")

    -- Redefine the print function
    print = function(...)
      local args = { ... }
      local message = table.concat(vim.tbl_map(tostring, args), "\t")
      table.insert(output, message)
    end

    -- Call the provided function
    pcall(function()
      table.insert(output, "")
      table.insert(output, "# Output")
      table.insert(output, "")
      chunk()
    end)

    -- Restore the original print function
    print = original_print

    local output_buf = vim.api.nvim_create_buf(false, true) -- No file, scratch buffer

    local temp_width = math.floor(vim.o.columns * 0.8)
    local temp_height = math.floor(vim.o.lines * 0.8)
    vim.api.nvim_open_win(output_buf, true, {
      relative = "editor",
      style = "minimal",
      noautocmd = true, -- we are temp opening this window, so don't fire the autocommand
      width = temp_width,
      height = temp_height,
      row = (vim.o.lines - temp_height) / 2,
      col = (vim.o.columns - temp_width) / 2,
    })

    vim.bo[output_buf].filetype = "markdown"
    vim.api.nvim_buf_set_lines(output_buf, 0, -1, false, output)
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

M.start_presentation({ bufnr = 4 })

M._parse_slides = parse_slides

return M
