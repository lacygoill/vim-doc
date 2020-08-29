if exists('g:autoloaded_doc#mapping')
    finish
endif
let g:autoloaded_doc#mapping = 1

" Init {{{1

import {Catch, GetSelection} from 'lg.vim'

const s:DEVDOCS_ENABLED_FILETYPES =<< trim END
    bash
    c
    html
    css
    lua
    python
END

" Interface {{{1
fu doc#mapping#main(type) abort "{{{2
    let cnt = v:count
    " Make tests on:{{{
    "
    " foo `man bash` bar
    " foo `man bash /keyword/;/running` bar
    " foo `info groff` bar
    " foo `info groff /difficult/;/confines` bar
    " foo `:h :com` bar
    " foo `:h :com /below/;/list` bar
    " foo `:h /\@=` bar
    " foo `:h /\@= /tricky/;/position` bar
    " foo `CSI ? Pm h/;/Ps = 2 0 0 4` bar
    " foo `$ ls -larth` bar
    "
    "     man bash
    "     man bash /keyword/;/running
    "     info groff
    "     info groff /difficult/;/confines
    "     :h :com
    "     :h :com /below/;/list
    "     :h /\@=
    "     :h /\@= /tricky/;/position
    "     CSI ? Pm h/;/Ps = 2 0 0 4
    "     $ ls -larth
    "}}}
    let cmd = s:get_cmd(a:type)
    if cmd == ''
        " Why do some filetypes need to be handled specially?  Why can't they be handled via `'kp'`?{{{
        "
        " Because  we need  some special  logic which  would need  to be  hidden
        " behind custom  commands, and I  don't want to install  custom commands
        " just for that.
        "
        " It would  also make the  code more complex;  you would have  to update
        " `b:undo_ftplugin`  to  reset `'kp'`  and  remove  the ad-hoc  command.
        " Besides, the latter needs a specific signature (`-buffer`, `-nargs=1`,
        " `<q-args>`, ...).
        " And it would introduce an additional dependency (`vim-lg`) because you
        " would need to  move `s:use_manpage()` (and copy  `s:error()`) into the
        " latter.
        "
        " ---
        "
        " There is  an additional benefit  in dealing here with  filetypes which
        " need a special logic.
        " We can tweak `'isk'` more easily to include some characters (e.g. `-`)
        " when looking for the word under the cursor.
        " It's easier here, because we only  have to write the code dealing with
        " adding `-` to `'isk'` once; no code duplication.
        "}}}
        if s:filetype_is_special()
            call s:handle_special_filetype(cnt)
        elseif &l:kp != ''
            call s:use_kp(cnt)
        elseif !s:on_commented_line() && s:filetype_enabled_on_devdocs()
            call s:use_devdoc()
        else
            echo 'no known command here (:h, $ cmd, man, info, CSI/OSC/DCS)'
        endif
        return
    endif
    if s:visual_selection_contains_shell_code(a:type)
        exe 'Ch ' .. cmd | return
    endif
    let cmd = s:vimify_cmd(cmd)
    if cmd =~# '^Man\s' && exists(':Man') != 2 | return s:error(':Man command is not installed') | endif
    " If the command does not contain a `/topic` token, just execute it.{{{
    "
    " Note that a  shell command may include  a slash, but it will  never be the
    " start of a `/topic`.  We never use `/topic` after a shell command:
    "
    "     ✔
    "     $ ls -larth
    "
    "     ✘
    "     $ ls -larth /some topic
    "}}}
    if cmd !~# '/' || cmd =~# '^Ch '
        " Don't let a quote or a bar terminate the shell command prematurely.{{{
        "
        "     com -bar -nargs=1 Ch call Func(<q-args>)
        "     fu Func(cmd) abort
        "         echo a:cmd
        "     endfu
        "
        "     Ch a"b
        "     a~
        "     Ch a|b
        "     a~
        "}}}
        let cmd = escape(cmd, '"|')
        try | exe cmd | catch | return s:Catch() | endtry
        return
    endif
    " The regex is a little complex because a help topic can start with a slash.{{{
    "
    " Example: `:h /\@>`.
    "
    " In that case, when parsing the command, we must not *stop* at this slash.
    " Same thing when parsing the offset: we must not *start* at this slash.
    "}}}
    let [cmd, topic] = matchlist(cmd, '\(.\{-}\)\%(\%(:h\s\+\)\@<!\(/.*\)\|$\)')[1:2]
    exe cmd
    " `exe ... cmd` could fail without raising a real Vim error, e.g. `:Man not_a_cmd`.
    " In such a case, we don't want the cursor to move.
    if s:not_in_documentation_buffer() | return | endif
    try
        exe topic
    " E486, E874, ...
    catch
        echohl ErrorMsg | echom v:exception | echohl NONE
    endtry
    call s:set_search_register(topic)
endfu
" }}}1
" Core {{{1
fu s:get_cmd(type) abort "{{{2
    if a:type is# 'vis'
        let cmd = s:GetSelection()->join("\n")
    else
        let line = getline('.')
        let cmd_pat =
            \   '\m\C\s*\zs\%('
            \ ..    ':h\|info\|man\|CSI\|OSC\|DCS\|'
            "\ random shell command for which we want a description via `ch`
            \ ..    '\$'
            \ .. '\)\s.*'
        let codespan = s:get_codespan(line, cmd_pat)
        let codeblock = s:get_codeblock(line, cmd_pat)
        if codeblock == '' && codespan == '' | let cmd = ''
        " if the  function finds a codespan  *and* a codeblock, we  want to give
        " the priority to the latter
        elseif codeblock != '' | let cmd = codeblock
        elseif codespan != ''  | let cmd = codespan
        endif
    endif
    " Ignore everything after a bar.{{{
    "
    " Useful to  avoid an  error when  pressing `K`  while visually  selecting a
    " shell command containing a pipe.
    " Also,  we don't  want Vim  to  interpret what  follows  the bar  as an  Ex
    " command; it could be anything, too dangerous.
    "}}}
    let cmd = substitute(cmd, '.\{-}\zs|.*', '', '')
    return cmd
endfu

fu s:get_codespan(line, cmd_pat) abort "{{{2
    let cml = s:get_cml()
    let col = col('.')
    let pat =
        "\ we are on a commented line
        \    '\%(^\s*\V' .. cml .. '\m.*\)\@<='
        \ .. '\%(^\%('
        "\ there can be a codespan before
        \ ..         '`[^`]*`'
        \ ..         '\|'
        "\ there can be a character outside a codespan before
        \ ..         '[^`]'
        \ ..      '\)'
        "\ there can be several of them
        \ ..     '*'
        \ ..  '\)\@<='
        \ .. '\%('
        "\ a codespan with the cursor in the middle
        \ ..     '`[^`]*\%' .. col .. 'c[^`]*`'
        \ ..     '\|'
        "\ a codespan with the cursor on the opening backtick
        \ ..     '\%' .. col .. 'c`[^`]*`'
        \ ..  '\)'

    " extract codespan from the line
    let codespan = matchstr(a:line, pat)
    " remove surrounding backticks
    let codespan = trim(codespan, '`')
    " extract command from the text
    " This serves 2 purposes.{{{
    "
    " Remove a possible leading `$` (shell prompt).
    "
    " Make  sure the text does  contain a command  for which our plugin  can find
    " some documentation.
    "}}}
    let codespan = matchstr(codespan, '^' .. a:cmd_pat)
    return codespan
endfu

fu s:get_codeblock(line, cmd_pat) abort "{{{2
    let cml = s:get_cml()
    let n = &ft is# 'markdown' ? 4 : 5
    let pat = '^\s*\V' .. cml .. '\m \{' .. n .. '}' .. a:cmd_pat
    let codeblock = matchstr(a:line, pat)
    return codeblock
endfu

fu s:get_cword() abort "{{{2
    let [isk_save, bufnr] = [&l:isk, bufnr('%')]
    try
        setl isk+=-
        let cword = expand('<cword>')
    finally
        call setbufvar(bufnr, '&isk', isk_save)
    endtry
    return cword
endfu

fu s:handle_special_filetype(cnt) abort "{{{2
    if &ft is# 'vim' || &ft is# 'markdown' && s:In('markdownHighlightvim')
        " there may be no help tag for the current word
        try | exe 'help ' .. s:helptopic() | catch | return s:Catch() | endtry
    elseif &ft is# 'tmux'
        try | call tmux#man() | catch | return s:Catch() | endtry
    elseif &ft is# 'awk'
        call s:use_manpage('awk', a:cnt)
    elseif &ft is# 'markdown'
        call s:use_manpage('markdown', a:cnt)
    elseif &ft is# 'python'
        call s:use_pydoc()
    elseif &ft is# 'sh'
        call s:use_manpage('bash', a:cnt)
    endif
endfu

fu s:use_manpage(name, cnt) abort "{{{2
    if exists(':Man') != 2 | return s:error(':Man command is not installed') | endif
    let cword = s:get_cword()
    let cmd = printf('Man %s %s', a:cnt ? a:cnt : '', cword)
    if a:cnt | exe cmd | return | endif
    try
        " first try to look for the current word in the bash/awk manpage
        exe 'Man ' .. a:name
        let pat = '\m\C^\s*\zs\<' .. cword .. '\>\ze\%(\s\|$\)'
        exe '/' .. pat
        call setreg('/', [pat], 'c')
    catch /^Vim\%((\a\+)\)\=:E486:/
        " if you can't find it there, use it as the name of a manpage
        q
        " Why not trying to catch a possible error if we press `K` on some random word?{{{
        "
        " When `:Man`  is passed the  name of  a non-existing manpage,  an error
        " message is echo'ed;  but it's just a message highlighted  in red; it's
        " not a real error, so you can't catch it.
        "}}}
        exe cmd
    endtry
endfu

fu s:use_kp(cnt) abort "{{{2
    let cword = s:get_cword()
    if &l:kp[0] is# ':'
        try
            exe printf('%s %s %s', &l:kp, a:cnt ? a:cnt : '', cword)
        catch /^Vim\%((\a\+)\)\=:\%(E149\|E434\):/
            echohl ErrorMsg
            echom v:exception
            echohl NONE
        endtry
    else
        exe printf('!%s %s %s', &l:kp, a:cnt ? a:cnt : '', shellescape(cword, 1))
    endif
endfu

fu s:use_pydoc() abort "{{{2
    let cword = s:get_cword()
    sil let doc = systemlist('pydoc ' .. shellescape(cword))
    if get(doc, 0, '') =~# '^no Python documentation found for'
        echo doc[0]
        return
    endif
    exe 'new ' .. tempname()
    call setline(1, doc)
    setl bh=delete bt=nofile nobl noswf noma ro
    nmap <buffer><nowait><silent> q <plug>(my_quit)
endfu

fu s:use_devdoc() abort "{{{2
    let cword = s:get_cword()
    exe 'Doc ' .. cword .. ' ' .. &ft
endfu

fu s:vimify_cmd(cmd) abort "{{{2
    let cmd = a:cmd
    if cmd =~# '^\%(info\|man\)\s'
        let l:Rep = {m -> m[0] is# 'info' ? 'Info' : 'Man'}
        let cmd = substitute(cmd, '^\%(info\|man\)', l:Rep, '')
    elseif cmd =~# '^\%(CSI\|OSC\|DCS\)\s'
        let cmd = substitute(cmd, '^', 'CtlSeqs /', '')
    elseif cmd =~# '^\$\s'
        let cmd = substitute(cmd, '^\$', 'Ch', '')
    elseif cmd =~# '^:h\s'
        " nothing to do; `:h` is already a Vim command
    else
        " When can this happen?{{{
        "
        " When  you visually  select some  text  which doesn't  match any  known
        " documentation command.
        "
        " Or when you refactor `s:get_cmd()` to support a new kind of documentation
        " command, but you forget to refactor this function to "vimify" it.
        "}}}
        echo 'not a documentation command (:h, $ cmd, man, info, CSI/OSC/DCS)'
        let cmd = ''
    endif
    return cmd
endfu

fu s:set_search_register(topic) abort "{{{2
    " Populate the search register with  the topic if it doesn't contain
    " any offset, or with the last offset otherwise.
    if a:topic =~# '/;/'
        call setreg('/', [matchstr(a:topic, '.*/;/\zs.*')], 'c')
    " remove leading `/`
    else
        call setreg('/', [a:topic[1:]], 'c')
    endif
endfu

fu s:helptopic() abort "{{{2
    let [line, col] = [getline('.'), col('.')]
    if line[col-1] =~# '\k'
        let pat_pre = '.*\ze\<\k*\%' .. col .. 'c'
    else
        let pat_pre = '.*\%' .. col .. 'c.'
    endif
    let pat_post = '\%' .. col .. 'c\k*\>\zs.*'
    let pre = matchstr(line, pat_pre)
    let post = matchstr(line, pat_post)

    let syntax_item = synstack('.', col('.'))
        \ ->map({_, v -> synIDattr(v,'name')})
        \ ->reverse()
        \ ->get(0, '')
    let cword = expand('<cword>')

    if syntax_item is# 'vimFuncName'
        return cword .. '()'
    elseif syntax_item is# 'vimOption'
        return "'" .. cword .. "'"
    " `-bar`, `-nargs`, `-range`...
    elseif syntax_item is# 'vimUserAttrbKey'
        return ':command-' .. cword
    " `<silent>`, `<unique>`, ...
    elseif syntax_item is# 'vimMapModKey'
        return ':map-<' .. cword

    " if the word under the cursor is  preceded by nothing, except maybe a colon
    " right before, treat it as an Ex command
    elseif pre =~# '^\s*:\=$'
        return ':' .. cword

    " `v:key`, `v:val`, `v:count`, ... (cursor after `:`)
    elseif pre =~# '\<v:$'
        return 'v:' .. cword
    " `v:key`, `v:val`, `v:count`, ... (cursor on `v`)
    elseif cword is# 'v' && post =~# ':\w\+'
        return 'v' .. matchstr(post, ':\w\+')

    else
        return cword
    endif
endfu
"}}}1
" Utilities {{{1
fu s:In(syngroup) abort "{{{2
    return synstack('.', col('.'))
        \ ->map({_, v -> synIDattr(v, 'name')})
        \ ->match('\c' .. a:syngroup) != -1
endfu

fu s:filetype_is_special() abort "{{{2
    return index(['awk', 'markdown', 'python', 'sh', 'tmux', 'vim'], &ft) != -1
endfu

fu s:error(msg) abort "{{{2
    echohl ErrorMsg
    echo a:msg
    echohl NONE
endfu

fu s:on_commented_line() abort "{{{2
    let cml = s:get_cml()
    if cml == '' | return 0 | endif
    return getline('.') =~# '^\s*\V' .. cml
endfu

fu s:filetype_enabled_on_devdocs() abort "{{{2
    return index(s:DEVDOCS_ENABLED_FILETYPES, &ft) != -1
endfu

fu s:get_cml() abort "{{{2
    if &ft is# 'markdown'
        let cml = ''
    elseif &ft is# 'vim'
        let cml = '\m["#]\V'
    else
        let cml = matchstr(&l:cms, '\S*\ze\s*%s')->escape('\')
    endif
    return cml
endfu

fu s:visual_selection_contains_shell_code(type) abort "{{{2
    return a:type is# 'vis' && &ft is# 'sh' && !s:on_commented_line()
endfu

fu s:not_in_documentation_buffer() abort "{{{2
    return index(['help', 'info', 'man'], &ft) == -1
        \ && expand('%:t') isnot# 'ctlseqs.txt.gz'
endfu

