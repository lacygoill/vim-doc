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
let s:PATH_TO_CTLSEQS = '/usr/share/doc/xterm/ctlseqs.txt.gz'

" Interface {{{1
fu! doc#mapping#main(type) abort "{{{2
    " TODO: the function is too long, and too complex for a main function
    let reg_save = [getreg('"'), getregtype('"')]
    try
        " TODO: Why do we call `s:describe_shell_command()` here, and later a second time?{{{
        "
        " Is the second call redundant?
        "
        " ---
        "
        " Why do we care about the comment leader only when we extract a command
        " from a codeblock? Why don't we also care for a codespan?
        "}}}
        if s:is_uncommented_shell_command() | call s:describe_shell_command() | return | endif
        let cmd = call('s:get_cmd', [a:type])
        if cmd is# '' | return | endif
        if cmd =~# '^\%(info\|man\)\s'
            let l:Rep = {m -> m[0] is# 'info' ? 'Info' : 'Man'}
            let cmd = substitute(cmd, '^\(info\|man\)', l:Rep, '')
        elseif cmd =~# '^\%(CSI\|OSC\|DCS\)\s'
            if s:ctlseqs_file_is_already_displayed()
                call s:focus_ctlseqs_window()
            else
                exe 'noswapfile sp +1 '..s:PATH_TO_CTLSEQS
            endif
            if expand('%:t') is# 'ctlseqs.txt.gz'
                nno <buffer><expr><nowait><silent> q reg_recording() isnot# '' ? 'q' : ':<c-u>q!<cr>'
            endif
            let cmd = substitute(cmd, '^', '/', '')
        elseif cmd !~# '^:h\s'
            " Test the code against these commands:{{{
            "
            "     $ ls -larth
            " foo `$ ls -larth` bar
            "}}}
            call s:describe_shell_command(cmd) | return
        endif
        if cmd =~# '/'
            " A help topic can start with a slash.{{{
            "
            " Example:
            " blah blah `:h /\@>` blah blah
            "
            " Here, `/\@>` would  be wrongly interpreted as a  pattern to search
            " by the rest of our code (instead of a simple help tag).
            "}}}
            if cmd =~# '^:h\s\+/'
                let [cmd, topic] = [matchstr(cmd, '.\{-}\ze\s*/.\{-}%\(/\|$\)'), matchstr(cmd, '/.*')]
            else
                let [cmd, topic] = [matchstr(cmd, '.\{-}\ze\s*/'), matchstr(cmd, '/.*')]
            endif
            exe cmd
            " `exe ... cmd` could fail without raising a real Vim error, e.g. `:Man not_a_cmd`.
            " In such a case, we make sure the cursor is not moved.
            if index(['help', 'info', 'man'], &ft) == -1 && expand('%:t') isnot# 'ctlseqs.txt.gz' | return | endif
            exe topic
            " Populate the search register with  the topic if it doesn't contain
            " any offset, or with the last offset otherwise.
            if topic =~# '/;/'
                let @/ = matchstr(topic, '.*/;/\zs.*')
            else
                " remove leading `/`
                let @/ = topic[1:]
            endif
        else
            exe cmd
        endif
    catch | return lg#catch_error()
    finally | call setreg('"', reg_save[0], reg_save[1])
    endtry
endfu
" }}}1
" Core {{{1
fu! s:get_cmd(type) abort "{{{2
    if a:type is# 'vis'
        norm! gvy
        return @"
    else
        let line = getline('.')
        let cmd_pat =
            \   '\m\C\s*\%('
            \ ..    '\zs\%(info\|man\)'
            \ ..    '\|'
            "\ random shell command for which we want a description via `ch`
            \ ..    '$\s*\zs.*'
            \ ..    '\|'
            \ ..    '\zs\%(:h\|CSI\|OSC\|DCS\)'
            \ ..'\)\s.*'
        let codespan = s:get_codespan(line, cmd_pat)
        let codeblock = s:get_codeblock(line, cmd_pat)
        if codeblock is# '' && codespan is# ''
            echo 'no documentation command to run' | return ''
        " if the  function finds a codespan  *and* a codeblock, we  want to give
        " the priority to the latter
        elseif codeblock isnot ''
            return codeblock
        elseif codespan isnot ''
            return codespan
        endif
    return ''
endfu

fu! s:get_codespan(line, cmd_pat) abort "{{{2
   let col = col('.')
   let pat =
       \   '\%(^\%('
       "\ there can be a codespan before
       \ ..        '`[^`]*`'
       \ ..        '\|'
       "\ there can be a character outside a codespan before
       \ ..        '[^`]'
       \ ..     '\)'
       "\ there can be several of them
       \ ..     '*'
       \ .. '\)\@<='
       \ .. '\%('
       "\ a codespan with the cursor in the middle
       \ ..     '`[^`]*\%'..col..'c[^`]*`'
       \ ..     '\|'
       "\ a codespan with the cursor on the opening backtick
       \ ..     '\%'..col..'c`[^`]*`'
       \ .. '\)'

   " extract codespan from the line
   let codespan = matchstr(a:line, pat)
   " remove surrounding backticks
   let codespan = substitute(codespan, '^`\|`$', '', 'g')
   " extract command from the text
   " This serves 2 purposes.{{{
   "
   " Remove a possible leading `$` (shell prompt).
   "
   " Make  sure the text does  contain a command  for which our plugin  can find
   " some documentation.
   "}}}
   let codespan = matchstr(codespan, '^'..a:cmd_pat)
   return codespan
endfu

fu! s:get_codeblock(line, cmd_pat) abort "{{{2
   if &ft is# 'markdown'
       let cml = ''
   else
       let cml = matchstr(get(split(&l:cms, '%s', 1), 0, ''), '\S*')
   endif
   let n = &ft is# 'markdown' ? 4 : 5
   let pat = '^\s*\V'..escape(cml, '\')..'\m \{'..n..'}'..a:cmd_pat
   let codeblock = matchstr(a:line, pat)
   return codeblock
endfu
"}}}1
" Utilities {{{1
fu! s:is_uncommented_shell_command() abort "{{{2
    return &ft is# 'sh' && getline('.') !~# '^\s*#'
endfu

fu! s:describe_shell_command(...) abort "{{{2
    let cmd = a:0 ? a:1 : getline('.')
    sil let @o = system('ch '..cmd..' 2>/dev/null')
    echo @o
endfu

fu! s:ctlseqs_file_is_already_displayed() abort "{{{2
    return match(map(tabpagebuflist(), {_,v -> bufname(v)}), 'ctlseqs\.txt\.gz$') != -1
endfu

fu! s:focus_ctlseqs_window() abort "{{{2
    let bufnr = bufnr('ctlseqs\.txt.\gz$')
    let winids = win_findbuf(bufnr)
    let tabpagenr = tabpagenr()
    call filter(winids, {_,v -> getwininfo(v)[0].tabnr == tabpagenr})
    call win_gotoid(winids[0])
endfu

