if exists('g:loaded_doc')
    finish
endif
let g:loaded_doc = 1

com -bar -nargs=? Ch call doc#cmd#ch(<q-args>)
com -bar -nargs=0 CtlSeqs call doc#cmd#ctlseqs()
com -bar -nargs=? Info call doc#cmd#info(<q-args>)
com -bar -nargs=* Doc call doc#cmd#doc(<f-args>)

" we use an opfunc just to make the mapping dot repeatable
nno <silent><unique> -d :<c-u>set opfunc=doc#mapping#main<cr>g@l
" How is the visual mapping useful?{{{
"
" The normal mode  mapping works only if the documentation  command is contained
" in a codespan or codeblock; the visual mapping lifts that restriction.
"
" It's also useful to get the description of a shell command via the script `ch`.
"}}}
xno <silent><unique> -d :<c-u>call doc#mapping#main('vis')<cr>

