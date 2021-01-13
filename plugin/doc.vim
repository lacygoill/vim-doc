vim9 noclear

if exists('loaded') | finish | endif
var loaded = true

nno <unique> K <cmd>call doc#mapping#main()<cr>
# How is the visual mapping useful?{{{
#
# The normal mode  mapping works only if the documentation  command is contained
# in a codespan or codeblock; the visual mapping lifts that restriction.
#
# It's also useful to get the description of a shell command via the script `ch`.
#}}}
xno <unique> K <c-\><c-n><cmd>call doc#mapping#main('vis')<cr>

com -bar -nargs=1 Ch doc#cmd#ch(<q-args>)
com -bar -nargs=0 CtlSeqs doc#cmd#ctlseqs()
com -bar -nargs=? -complete=shellcmd Info doc#cmd#info(<q-args>)
com -bar -nargs=* Doc doc#cmd#doc(<f-args>)

