local M = {}

M.defaults = {
  vault_dir = vim.fn.getcwd(),
  agenda_days_ahead = 14,
  keymaps = {
    prefix = "<leader>t",
    agenda = "a",
    find = "f",
    new = "n",
  },
  float = {
    width_ratio = 0.65,
    height_ratio = 0.70,
    border = "rounded",
  },
}

M.options = {}

function M.setup(opts)
  M.options = vim.tbl_deep_extend("force", M.defaults, opts or {})
end

return M
