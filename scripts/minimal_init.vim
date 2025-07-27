set rtp+=.
set rtp+=../plenary.nvim "for running things on github
set rtp+=~/.local/share/nvim/lazy/plenary.nvim/ "for running things smoothly on local system

runtime! plugin/plenary.vim
runtime! plugin/load_present.lua
