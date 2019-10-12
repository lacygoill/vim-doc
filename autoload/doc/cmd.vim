" Init {{{1

" Could we get it programmatically?{{{
"
" You could use `findfile()`:
"
"     :echo findfile('ctlseqs.txt.gz', '/usr/share/**')
"
" Or `find(1)`:
"
"     :echo system('find /usr -path "*/xterm/*ctlseqs.txt.gz"')[:-2]
"
" But those commands take some time.
" Not sure it's worth it for the moment.
"}}}
const s:PATH_TO_CTLSEQS = '/usr/share/doc/xterm/ctlseqs.txt.gz'

" Interface {{{1
fu doc#cmd#ch(shell_cmd) abort "{{{2
    if a:shell_cmd is# ''
        let cmd = getline('.')
    else
        let cmd = a:shell_cmd
    endif
    sil let @o = system('ch '..cmd..' 2>/dev/null')
    echo @o
endfu

fu doc#cmd#ctlseqs() abort "{{{2
    if s:ctlseqs_file_is_already_displayed()
        call s:focus_ctlseqs_window()
    else
        exe 'noswapfile sp +1 '..s:PATH_TO_CTLSEQS
    endif
    if expand('%:t') is# 'ctlseqs.txt.gz'
        nno <buffer><expr><nowait><silent> q reg_recording() isnot# '' ? 'q' : ':<c-u>q!<cr>'
    endif
endfu

fu doc#cmd#info(topic) abort "{{{2
    new
    exe '.!info '..a:topic
    if bufname('%') isnot# '' | return | endif
    setl bh=delete bt=nofile nobl noswf nowrap
    nno <buffer><expr><nowait><silent> q reg_recording() isnot# '' ? 'q' : ':<c-u>q<cr>'
endfu

fu doc#cmd#doc(...) abort "{{{2
    if ! a:0 || (a:1 is# '--help' || a:1 is# '-h')
        let usage =<< trim END
        usage:
            :Doc div        keyword 'div', scoped with current filetype
            :Doc div html   keyword 'div', scoped with html

        If you don't get the expected information,
        make sure that the documentation for the relevant language is enabled on:
            https://devdocs.io/
        END
        echo join(usage, "\n")
        return
    endif

    let cmd = 'xdg-open'
    " For the syntax of the query, see this link:
    " https://devdocs.io/help#search
    let url = 'http://devdocs.io/?q='

    let args = a:0 == 1
           \ ?     url..&ft..' '..a:1
           \ :     url..a:2..' '..a:1

    sil call system(cmd..' '..shellescape(args))
endfu
"}}}1
" Core {{{1
fu s:focus_ctlseqs_window() abort "{{{2
    let bufnr = bufnr('ctlseqs\.txt.\gz$')
    let winids = win_findbuf(bufnr)
    let tabpagenr = tabpagenr()
    call filter(winids, {_,v -> getwininfo(v)[0].tabnr == tabpagenr})
    call win_gotoid(winids[0])
endfu
"}}}1
" Utilities {{{1
fu s:ctlseqs_file_is_already_displayed() abort "{{{2
    return match(map(tabpagebuflist(), {_,v -> bufname(v)}), 'ctlseqs\.txt\.gz$') != -1
endfu

