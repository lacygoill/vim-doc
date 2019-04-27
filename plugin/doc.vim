if exists('g:loaded_doc')
    finish
endif
let g:loaded_doc = 1

com! -bar -nargs=* Doc call doc#cmd#main(<f-args>)

" TODO: Develop this mapping.{{{
"
" It could be used  to get more interactivity in our markdown  notes, and in our
" comments.
"
" Think about it: we use some markup everywhere.
" That gives Vim the ability to get some understanding of what we write.
" Leverage this understanding; make Vim interact with what it recognizes.
"
" For example, all those:
"
"     see `blah blah`
"
" should require a minimum amout of effort.
" `blah blah` should be processed by a single smart mapping, capable of reacting
" differently depending on the text.
"}}}
nno <silent><unique> -d :<c-u>call doc#mapping#main()<cr>

