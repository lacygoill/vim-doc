" Interface {{{1
fu! doc#mapping#main() abort "{{{2
    let line = getline('.')
    let cmd_pat = '\C\s*\%($\s*\zs\%(info\|man\)\|\zs\%(:h\|CSI\|OSC\|DCS\)\)\s.*'
    let codespan = s:get_codespan(line, cmd_pat)
    let codeblock = s:get_codeblock(line, cmd_pat)
    if codespan is# '' && codeblock isnot# ''
        let cmd = codeblock
    elseif codespan isnot# '' && codeblock is# ''
        let cmd = codespan
    else
        echo 'no documentation command to run'
        return
    endif
    if cmd =~# '^\%(info\|man\)'
        let l:Rep = {m -> m[0] is# 'info' ? 'Info' : 'Man'}
        let cmd = substitute(cmd, '^\(info\|man\)', l:Rep, '')
    elseif cmd =~# '^\%(CSI\|OSC\|DCS\)'
        let l:Rep = {m -> m[0] is# 'info' ? 'Info' : 'Man'}
        sp +1 /usr/share/doc/xterm/ctlseqs.txt.gz
        if expand('%:t') is# 'ctlseqs.txt.gz'
            nno <buffer><nowait><silent> q :<c-u>q<cr>
        endif
        let cmd = substitute(cmd, '^', '/', '')
    endif
    if cmd =~# '/'
        let [cmd, topics] = [matchstr(cmd, '.\{-}\ze\s*/'), matchstr(cmd, '/.*')]
        let cmd = substitute(cmd, '|.*', '', '')
        if topics =~# '[^ \\]/'
            echohl ErrorMsg
            " Example:{{{
            "
            "     $ man cmd /search/this
            "                      ^
            "                      ✘
            "
            "     $ man cmd /search\/this
            "                      ^
            "                      ✔
            "}}}
            echom 'One of your search contains an unescaped slash; escape it'
            echohl NONE
            return
        endif
        exe cmd
        " Don't make the cursor move if the previous command failed.
        " Don't try to catch an error; `:Man not_a_cmd` doesn't raise a real error.
        if index(['help', 'info', 'man'], &ft) == -1 && expand('%:t') isnot# 'ctlseqs.txt.gz'
            return
        endif
        try
            let topics = map(split(topics, '\\\@<!/'), {i,v -> matchstr(v, '.*\s\@<!')})
            " TODO: Should we remove this line?{{{
            " What if  we need to  search for  an uppercase word,  which appears
            " somewhere in the middle of a line (!= section header)?
            "
            " If you  remove it, use  the anchor `^`  to prefix all  the section
            " headers used in a search of a `$ man` command.
            "}}}
            call map(topics, {i,v -> toupper(v) is# v ? '^' . v : v})
            for topic in topics
                exe '/' . topic
            endfor
            if tolower(topic) is# topic
                let @/ = topic
            endif
        catch /^Vim\%((\a\+)\)\=:E\%(486\)/
            echohl ErrorMsg
            echom v:exception
            echohl NONE
        endtry
    else
        let cmd = substitute(cmd, '|.*', '', '')
        try
            exe cmd
        catch
            echohl ErrorMsg
            echom v:exception
            echohl NONE
        endtry
    endif
endfu
" }}}1
" Utilities {{{1
fu! s:get_codeblock(line, cmd_pat) abort "{{{2
   if &ft is# 'markdown'
       let cml = ''
   else
       let cml = matchstr(get(split(&l:cms, '%s', 1), 0, ''), '\S*')
   endif
   let n = &ft is# 'markdown' ? 4 : 5
   let pat = '^\s*\V' . escape(cml, '\') . '\m \{' . n . '}'
   let codeblock = matchstr(a:line, pat . a:cmd_pat)
   return codeblock
endfu

fu! s:get_codespan(line, cmd_pat) abort "{{{2
   let col = col('.')
   " Why 2 branches?{{{
   "
   " The  codespan could start *after*  the cursor (1st branch),  or *from* the
   " cursor (2nd branch).
   " The second branch allows you to press  the mapping the cursor being on the
   " first backtick of a codespan (but not on the second one).
   "}}}
   let pat = '`[^`]*\%' . col . 'c[^`]\+`\|\%' . col . 'c`.\{-}`'
   let codespan = matchstr(a:line, pat)
   let codespan = substitute(codespan, '^`\|`$', '', 'g')
   let codespan = matchstr(codespan, '^' . a:cmd_pat)
   return codespan
endfu

