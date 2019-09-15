if exists('g:autoloaded_doc#mapping')
    finish
endif
let g:autoloaded_doc#mapping = 1

" Init {{{1

let s:DEVDOCS_ENABLED_FILETYPES = ['bash', 'c', 'html', 'css', 'lua', 'python']

" Interface {{{1
fu! doc#mapping#main(type) abort "{{{2
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
    let cmd = call('s:get_cmd', [a:type])
    if cmd is# ''
        if ! s:on_commented_line() | call s:document_word_under_cursor()
        else | echo 'no known command here (man, :h, CSI, $ ls, ...)' | endif
        return
    endif
    if s:visual_selection_contains_shell_code(a:type)
        exe 'Ch '..cmd | return
    endif
    let cmd = s:vimify_cmd(cmd)
    if cmd =~# '^Man\s' && exists(':Man') != 2 | echo ':Man command is not installed' | return | endif
    if cmd !~# '/' | exe cmd | return | endif
    " The regexes are a little complex because a help topic can start with a slash.{{{
    "
    " Example: `:h /\@>`.
    "
    " In that case, when parsing the command, we must not *stop* at this slash.
    " Same thing when parsing the offset: we must not *start* at this slash.
    "}}}
    let [cmd, topic] = [matchstr(cmd, '.\{-}\ze\%(\%(:h\s\+\)\@<!/\|$\)'),
                      \ matchstr(cmd, '\%(:h\s\+\)\@<!/.*')]
    exe cmd
    " `exe ... cmd` could fail without raising a real Vim error, e.g. `:Man not_a_cmd`.
    " In such a case, we don't want the cursor to move.
    if s:not_in_documentation_buffer() | return | endif
    exe topic
    call s:set_search_register(topic)
endfu
" }}}1
" Core {{{1
fu! s:get_cmd(type) abort "{{{2
    if a:type is# 'vis'
        let cb_save  = &cb
        let sel_save = &sel
        let reg_save = [getreg('"'), getregtype('"')]
        try
            set cb-=unnamed cb-=unnamedplus
            set sel=inclusive
            sil norm! gvy
            let cmd = @"
        catch | return lg#catch_error()
        finally | call setreg('"', reg_save[0], reg_save[1])
        endtry
    else
        let line = getline('.')
        let cmd_pat =
            \   '\m\C\s*\zs\%('
            \ ..    ':h\|info\|man\|CSI\|OSC\|DCS\|'
            "\ random shell command for which we want a description via `ch`
            \ ..    '\$'
            \ ..'\)\s.*'
        let codespan = s:get_codespan(line, cmd_pat)
        let codeblock = s:get_codeblock(line, cmd_pat)
        if codeblock is# '' && codespan is# '' | let cmd = ''
        " if the  function finds a codespan  *and* a codeblock, we  want to give
        " the priority to the latter
        elseif codeblock isnot '' | let cmd = codeblock
        elseif codespan isnot ''  | let cmd = codespan
        endif
    endif
    return cmd
endfu

fu! s:get_codespan(line, cmd_pat) abort "{{{2
    let cml = s:get_cml()
    let col = col('.')
    let pat =
        "\ we are on a commented line
        \    '\%(^\s*\V'..escape(cml, '\')..'\m.*\)\@<='
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
        \ ..     '`[^`]*\%'..col..'c[^`]*`'
        \ ..     '\|'
        "\ a codespan with the cursor on the opening backtick
        \ ..     '\%'..col..'c`[^`]*`'
        \ ..  '\)'

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
    let cml = s:get_cml()
    let n = &ft is# 'markdown' ? 4 : 5
    let pat = '^\s*\V'..escape(cml, '\')..'\m \{'..n..'}'..a:cmd_pat
    let codeblock = matchstr(a:line, pat)
    return codeblock
endfu

fu! s:document_word_under_cursor() abort "{{{2
    if index(s:DEVDOCS_ENABLED_FILETYPES, &ft) == -1
        echo printf('the "%s" filetype is not enabled on https://devdocs.io/', &ft)
        return
    endif
    let word = expand('<cword>')
    exe 'Doc '..word..' '..&ft
endfu

fu! s:vimify_cmd(cmd) abort "{{{2
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
        " command, but you we forget to refactor this function to "vimify" it.
        "}}}
        echo 'not a documentation command (man, :h, CSI, $ ls, ...)' | let cmd = ''
    endif
    return cmd
endfu

fu! s:set_search_register(topic) abort "{{{2
    " Populate the search register with  the topic if it doesn't contain
    " any offset, or with the last offset otherwise.
    if a:topic =~# '/;/' | let @/ = matchstr(a:topic, '.*/;/\zs.*')
    " remove leading `/`
    else | let @/ = a:topic[1:] | endif
endfu
"}}}1
" Utilities {{{1
fu! s:on_commented_line() abort "{{{2
    let cml = s:get_cml()
    if cml is# '' | return 0 | endif
    return getline('.') =~# '^\s*\V'..escape(cml, '\')
endfu

fu! s:get_cml() abort "{{{2
    if &ft is# 'markdown'
        let cml = ''
    else
        let cml = matchstr(get(split(&l:cms, '%s', 1), 0, ''), '\S*')
    endif
    return cml
endfu

fu! s:visual_selection_contains_shell_code(type) abort "{{{2
    return a:type is# 'vis' && &ft is# 'sh' && ! s:on_commented_line()
endfu

fu! s:not_in_documentation_buffer() abort "{{{2
    return index(['help', 'info', 'man'], &ft) == -1
        \ && expand('%:t') isnot# 'ctlseqs.txt.gz'
endfu

