vim9script noclear

if exists('loaded') | finish | endif
var loaded = true

nnoremap <unique> K <Cmd>call doc#mapping#main()<CR>
# How is the visual mapping useful?{{{
#
# The normal mode  mapping works only if the documentation  command is contained
# in a codespan or codeblock; the visual mapping lifts that restriction.
#
# It's also useful to get the description of a shell command via the script `ch`.
#}}}
xnoremap <unique> K <C-\><C-N><Cmd>call doc#mapping#main('vis')<CR>

command -bar -nargs=1 Ch doc#cmd#ch(<q-args>)
command -bar -nargs=0 CtlSeqs doc#cmd#ctlseqs()
command -bar -nargs=? -complete=shellcmd Info doc#cmd#info(<q-args>)
command -bar -nargs=* Doc doc#cmd#doc(<f-args>)

