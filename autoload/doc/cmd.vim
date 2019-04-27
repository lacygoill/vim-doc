fu! doc#cmd#main(...) abort "{{{1
    if a:0 && (a:1 is# '--help' || a:1 is# '-h')
        echo printf("usage:\n    %s\n    %s\n    %s",
        \ ':Doc             word under cursor, scoped with current filetype',
        \ ':Doc div         keyword ''div'', scoped with current filetype',
        \ ':Doc html div    keyword ''div'', scoped with html'
        \ )
        return
    endif

    let cmd = 'xdg-open'
    " For the syntax of the query, see this link:
    "     https://devdocs.io/help#search
    let url = 'http://devdocs.io/?q='

    let args = a:0 ==# 0
           \ ?     url . &filetype . ' ' . expand('<cword>')
           \ : a:0 ==# 1
           \ ?     url . &filetype . ' ' . a:1
           \ :     url . join(a:000)

    sil! call system(cmd.' '.string(args))
endfu

