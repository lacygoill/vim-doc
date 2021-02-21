vim9script noclear

if exists('loaded') | finish | endif
var loaded = true

# Init {{{1

import {
    Catch,
    GetSelectionText,
    } from 'lg.vim'

# The filetype of a header file (`.h`) is `cpp`.
const DEVDOCS_ENABLED_FILETYPES: list<string> =<< trim END
    bash
    c
    cpp
    html
    css
    lua
    python
END

# Interface {{{1
def doc#mapping#main(type = '') #{{{2
    var cnt: number = v:count
    # Make tests on:{{{
    #
    # foo `man bash` bar
    # foo `man bash /keyword/;/running` bar
    # foo `info groff` bar
    # foo `info groff /difficult/;/confines` bar
    # foo `:h :com` bar
    # foo `:h :com /below/;/list` bar
    # foo `:h /\@=` bar
    # foo `:h /\@= /tricky/;/position` bar
    # foo `CSI ? Pm h/;/Ps = 2 0 0 4` bar
    # foo `$ ls -larth` bar
    #
    #     man bash
    #     man bash /keyword/;/running
    #     info groff
    #     info groff /difficult/;/confines
    #     :h :com
    #     :h :com /below/;/list
    #     :h /\@=
    #     :h /\@= /tricky/;/position
    #     CSI ? Pm h/;/Ps = 2 0 0 4
    #     $ ls -larth
    #}}}
    var cmd: string = GetCmd(type)
    if cmd == ''
        # Why do some filetypes need to be handled specially?  Why can't they be handled via `'kp'`?{{{
        #
        # Because  we need  some special  logic which  would need  to be  hidden
        # behind custom  commands, and I  don't want to install  custom commands
        # just for that.
        #
        # It would  also make the  code more complex;  you would have  to update
        # `b:undo_ftplugin`  to  reset `'kp'`  and  remove  the ad-hoc  command.
        # Besides, the latter needs a specific signature (`-buffer`, `-nargs=1`,
        # `<q-args>`, ...).
        # And it would introduce an additional dependency (`vim-lg`) because you
        # would  need  to move  `UseManpage()`  (and  copy `Error()`)  into  the
        # latter.
        #
        # ---
        #
        # There is  an additional benefit  in dealing here with  filetypes which
        # need a special logic.
        # We can tweak `'isk'` more easily to include some characters (e.g. `-`)
        # when looking for the word under the cursor.
        # It's easier here, because we only  have to write the code dealing with
        # adding `-` to `'isk'` once; no code duplication.
        #}}}
        if FiletypeIsSpecial()
            HandleSpecialFiletype(cnt)
        elseif &l:kp != ''
            UseKp(cnt)
        elseif !OnCommentedLine() && FiletypeEnabledOnDevdocs()
            UseDevdoc()
        else
            echo 'no known command here (:h, $ cmd, man, info, CSI/OSC/DCS)'
        endif
        return
    endif
    if VisualSelectionContainsShellCode(type)
        exe 'Ch ' .. cmd
        return
    endif
    cmd = VimifyCmd(cmd)
    if cmd =~ '^Man\s' && exists(':Man') != 2
        Error(':Man command is not installed')
        return
    endif
    # If the command does not contain a `/topic` token, just execute it.{{{
    #
    # Note that a  shell command may include  a slash, but it will  never be the
    # start of a `/topic`.  We never use `/topic` after a shell command:
    #
    #     ✔
    #     $ ls -larth
    #
    #     ✘
    #     $ ls -larth /some topic
    #}}}
    if cmd !~ '/' || cmd =~ '^Ch '
        # Don't let a quote or a bar terminate the shell command prematurely.{{{
        #
        #     com -bar -nargs=1 Ch Func(<q-args>)
        #     def Func(cmd: string)
        #         echo cmd
        #     enddef
        #
        #     Ch a"b
        #     a~
        #     Ch a|b
        #     a~
        #}}}
        cmd = escape(cmd, '"|')
        try
            exe cmd
        catch
            Catch()
            return
        endtry
        return
    endif
    # The regex is a little complex because a help topic can start with a slash.{{{
    #
    # Example: `:h /\@>`.
    #
    # In that case, when parsing the command, we must not *stop* at this slash.
    # Same thing when parsing the offset: we must not *start* at this slash.
    #}}}
    var topic: string
    [cmd, topic] = matchlist(cmd, '\(.\{-}\)\%(\%(:h\s\+\)\@<!\(/.*\)\|$\)')[1 : 2]
    exe cmd
    # `exe ... cmd` could fail without raising a real Vim error, e.g. `:Man not_a_cmd`.
    # In such a case, we don't want the cursor to move.
    if NotInDocumentationBuffer()
        return
    endif
    try
        exe ':' .. topic
    # E486, E874, ...
    catch
        Catch()
        return
    endtry
    SetSearchRegister(topic)
enddef
# }}}1
# Core {{{1
def GetCmd(type: string): string #{{{2
    var cmd: string
    if type == 'vis'
        cmd = GetSelectionText()->join("\n")
    else
        var line: string = getline('.')
        var cmd_pat: string =
              '\m\C\s*\zs\%('
            ..    ':h\|info\|man\|CSI\|OSC\|DCS\|'
            # random shell command for which we want a description via `ch`
            ..    '\$'
            .. '\)\s.*'
        var codespan: string = GetCodespan(line, cmd_pat)
        var codeblock: string = GetCodeblock(line, cmd_pat)
        if codeblock == '' && codespan == '' | cmd = ''
        # if the  function finds a codespan  *and* a codeblock, we  want to give
        # the priority to the latter
        elseif codeblock != '' | cmd = codeblock
        elseif codespan != ''  | cmd = codespan
        endif
    endif
    # Ignore everything after a bar.{{{
    #
    # Useful to  avoid an  error when  pressing `K`  while visually  selecting a
    # shell command containing a pipe.
    # Also,  we don't  want Vim  to  interpret what  follows  the bar  as an  Ex
    # command; it could be anything, too dangerous.
    #}}}
    cmd = substitute(cmd, '.\{-}\zs|.*', '', '')
    return cmd
enddef

def GetCodespan(line: string, cmd_pat: string): string #{{{2
    var cml: string = GetCml()
    var col: number = col('.')
    var pat: string =
        # we are on a commented line
           '\%(^\s*\V' .. cml .. '\m.*\)\@<='
        .. '\%(^\%('
        # there can be a codespan before
        ..         '`[^`]*`'
        ..         '\|'
        # there can be a character outside a codespan before
        ..         '[^`]'
        ..      '\)'
        # there can be several of them
        ..     '*'
        ..  '\)\@<='
        .. '\%('
        # a codespan with the cursor in the middle
        ..     '`[^`]*\%' .. col .. 'c[^`]*`'
        ..     '\|'
        # a codespan with the cursor on the opening backtick
        ..     '\%' .. col .. 'c`[^`]*`'
        ..  '\)'

    # extract codespan from the line
    var codespan: string = matchstr(line, pat)
    # remove surrounding backticks
    codespan = trim(codespan, '`')
    # extract command from the text
    # This serves 2 purposes.{{{
    #
    # Remove a possible leading `$` (shell prompt).
    #
    # Make  sure the text does  contain a command  for which our plugin  can find
    # some documentation.
    #}}}
    codespan = matchstr(codespan, '^' .. cmd_pat)
    return codespan
enddef

def GetCodeblock(line: string, cmd_pat: string): string #{{{2
    var cml: string = GetCml()
    var n: number = &ft == 'markdown' ? 4 : 5
    var pat: string = '^\s*\V' .. cml .. '\m \{' .. n .. '}' .. cmd_pat
    var codeblock: string = matchstr(line, pat)
    return codeblock
enddef

def GetCword(): string #{{{2
    var isk_save: string = &l:isk
    var bufnr: number = bufnr('%')
    var cword: string
    try
        setl isk+=-
        cword = expand('<cword>')
    finally
        setbufvar(bufnr, '&isk', isk_save)
    endtry
    return cword
enddef

def HandleSpecialFiletype(cnt: number) #{{{2
    if &ft == 'vim'
        || &ft == 'markdown' && In('markdownHighlightvim')
        || &ft == 'markdown' && getcwd() == $HOME .. '/wiki/vim'
        # there may be no help tag for the current word
        try
            exe 'help ' .. Helptopic()
        catch
            Catch()
            return
        endtry
    elseif &ft == 'tmux'
        try
            tmux#man()
        catch
            Catch()
            return
        endtry
    elseif &ft == 'awk'
        UseManpage('awk', cnt)
    elseif &ft == 'markdown'
        UseManpage('markdown', cnt)
    elseif &ft == 'python'
        UsePydoc()
    elseif &ft == 'sh'
        UseManpage('bash', cnt)
    endif
enddef

def UseManpage(name: string, cnt: number) #{{{2
    if exists(':Man') != 2
        Error(':Man command is not installed')
        return
    endif
    var cword: string = GetCword()
    var cmd: string = printf('Man %s %s', cnt ? cnt : '', cword)
    if cnt
        exe cmd
        return
    endif
    try
        # first try to look for the current word in the bash/awk manpage
        exe 'Man ' .. name
        var pat: string = '\m\C^\s*\zs\<' .. cword .. '\>\ze\%(\s\|$\)'
        exe ':/' .. pat
        setreg('/', [pat], 'c')
    catch /^Vim\%((\a\+)\)\=:E486:/
        # if you can't find it there, use it as the name of a manpage
        q
        # Why not trying to catch a possible error if we press `K` on some random word?{{{
        #
        # When `:Man`  is passed the  name of  a non-existing manpage,  an error
        # message is echo'ed;  but it's just a message highlighted  in red; it's
        # not a real error, so you can't catch it.
        #}}}
        exe cmd
    catch /^Vim\%((\a\+)\)\=:E492:/
        # When can that happen?{{{
        #
        # Write this in a markdown file:
        #
        #     blah ``:h vim9 /`=``.
        #                   ^----^
        #                   press `K` on any of these characters
        #}}}
        # What's the solution?{{{
        #
        # Avoid backticks *inside* your codespans.
        #}}}
        # FIXME: Could we better handle this?{{{
        #
        # I think the root cause of the issue comes from `GetCodespan()`.
        # It's tricky to  extract the body of a codespan  when it's delimited by
        # *multiple* backticks.  Our current code is not designed to support this.
        #}}}
        echohl ErrorMsg
        echo 'Something went wrong.  Is there some backtick near your cursor?'
        echohl NONE
    endtry
enddef

def UseKp(cnt: number) #{{{2
    var cword: string = GetCword()
    if &l:kp[0] == ':'
        try
            exe printf('%s %s %s', &l:kp, cnt ? cnt : '', cword)
        catch /^Vim\%((\a\+)\)\=:\%(E149\|E434\):/
            Catch()
            return
        endtry
    else
        exe printf('!%s %s %s', &l:kp, cnt ? cnt : '', shellescape(cword, true))
    endif
enddef

def UsePydoc() #{{{2
    var cword: string = GetCword()
    sil var doc: list<string> = systemlist('pydoc ' .. shellescape(cword))
    if get(doc, 0, '') =~ '^no Python documentation found for'
        echo doc[0]
        return
    endif
    exe 'new ' .. tempname()
    setline(1, doc)
    setl bh=delete bt=nofile nobl noswf noma ro
    nmap <buffer><nowait> q <plug>(my_quit)
enddef

def UseDevdoc() #{{{2
    var cword: string = GetCword()
    exe 'Doc ' .. cword .. ' ' .. &ft
enddef

def VimifyCmd(arg_cmd: string): string #{{{2
    var cmd: string = arg_cmd
    if cmd =~ '^\%(info\|man\)\s'
        var Rep: func = (m: list<string>): string => m[0] == 'info' ? 'Info' : 'Man'
        cmd = substitute(cmd, '^\%(info\|man\)', Rep, '')
    elseif cmd =~ '^\%(CSI\|OSC\|DCS\)\s'
        cmd = substitute(cmd, '^', 'CtlSeqs /', '')
    elseif cmd =~ '^\$\s'
        cmd = substitute(cmd, '^\$', 'Ch', '')
    elseif cmd =~ '^:h\s'
        # nothing to do; `:h` is already a Vim command
    else
        # When can this happen?{{{
        #
        # When  you visually  select some  text  which doesn't  match any  known
        # documentation command.
        #
        # Or when you refactor `GetCmd()` to support a new kind of documentation
        # command, but you forget to refactor this function to "vimify" it.
        #}}}
        echo 'not a documentation command (:h, $ cmd, man, info, CSI/OSC/DCS)'
        cmd = ''
    endif
    return cmd
enddef

def SetSearchRegister(topic: string) #{{{2
    # Populate the search register with  the topic if it doesn't contain
    # any offset, or with the last offset otherwise.
    if topic =~ '/;/'
        setreg('/', [matchstr(topic, '.*/;/\zs.*')], 'c')
    # remove leading `/`
    else
        setreg('/', [topic[1 :]], 'c')
    endif
enddef

def Helptopic(): string #{{{2
    var line: string = getline('.')
    var col: number = col('.')
    var pat_pre: string
    if line[col - 1] =~ '\k'
        pat_pre = '.*\ze\<\k*\%' .. col .. 'c'
    else
        pat_pre = '.*\%' .. col .. 'c.'
    endif
    var pat_post: string = '\%' .. col .. 'c\k*\>\zs.*'
    var pre: string = matchstr(line, pat_pre)
    var post: string = matchstr(line, pat_post)

    var syntax_item: string = synstack('.', col('.'))
        ->mapnew((_, v: number): string => synIDattr(v, 'name'))
        ->reverse()
        ->get(0, '')
    var cword: string = expand('<cword>')

    if syntax_item == 'markdownCodeBlock'
        return cword
    elseif syntax_item == 'vimFuncName'
        return cword .. '()'
    elseif syntax_item == 'vimOption'
        return "'" .. cword .. "'"
    # `-bar`, `-nargs`, `-range`...
    elseif syntax_item == 'vimUserAttrbKey'
        return ':command-' .. cword
    # `<silent>`, `<unique>`, ...
    elseif syntax_item == 'vimMapModKey'
        return ':map-<' .. cword

    # if the word under the cursor is  preceded by nothing, except maybe a colon
    # right before, treat it as an Ex command
    elseif pre =~ '^\s*:\=$'
        return ':' .. cword

    # `v:key`, `v:val`, `v:count`, ... (cursor after `:`)
    elseif pre =~ '\<v:$'
        return 'v:' .. cword
    # `v:key`, `v:val`, `v:count`, ... (cursor on `v`)
    elseif cword == 'v' && post =~ ':\w\+'
        return 'v' .. matchstr(post, ':\w\+')

    else
        return cword
    endif
enddef
#}}}1
# Utilities {{{1
def In(syngroup: string): bool #{{{2
    return synstack('.', col('.'))
        ->mapnew((_, v: number): string => synIDattr(v, 'name'))
        ->match('\c' .. syngroup) >= 0
enddef

def FiletypeIsSpecial(): bool #{{{2
    return index(['awk', 'markdown', 'python', 'sh', 'tmux', 'vim'], &ft) >= 0
enddef

def Error(msg: string) #{{{2
    echohl ErrorMsg
    echom msg
    echohl NONE
enddef

def OnCommentedLine(): bool #{{{2
    var cml: string = GetCml()
    if cml == ''
        return false
    endif
    return getline('.') =~ '^\s*\V' .. cml
enddef

def FiletypeEnabledOnDevdocs(): bool #{{{2
    return index(DEVDOCS_ENABLED_FILETYPES, &ft) >= 0
enddef

def GetCml(): string #{{{2
    var cml: string
    if &ft == 'markdown'
        cml = ''
    elseif &ft == 'vim'
        cml = '\m["#]\V'
    else
        cml = matchstr(&l:cms, '\S*\ze\s*%s')->escape('\')
    endif
    return cml
enddef

def VisualSelectionContainsShellCode(type: string): bool #{{{2
    return type == 'vis' && &ft == 'sh' && !OnCommentedLine()
enddef

def NotInDocumentationBuffer(): bool #{{{2
    return index(['help', 'info', 'man'], &ft) == -1
        && expand('%:t') != 'ctlseqs.txt.gz'
enddef

