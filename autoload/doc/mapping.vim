vim9script noclear

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
    # foo `:help :command` bar
    # foo `:help :command /below/;/list` bar
    # foo `:help /\@=` bar
    # foo `:help /\@= /tricky/;/position` bar
    # foo `CSI ? Pm h/;/Ps = 2 0 0 4` bar
    # foo `$ ls -larth` bar
    #
    #     man bash
    #     man bash /keyword/;/running
    #     info groff
    #     info groff /difficult/;/confines
    #     :help :command
    #     :help :command /below/;/list
    #     :help /\@=
    #     :help /\@= /tricky/;/position
    #     CSI ? Pm h/;/Ps = 2 0 0 4
    #     $ ls -larth
    #}}}
    var cmd: string = GetCmd(type)
    if cmd == ''
        # Why do some filetypes need to be handled specially?  Why can't they be handled via `'keywordprg'`?{{{
        #
        # Because  we need  some special  logic which  would need  to be  hidden
        # behind custom  commands, and I  don't want to install  custom commands
        # just for that.
        #
        # It would  also make the  code more complex;  you would have  to update
        # `b:undo_ftplugin`  to  reset  `'keywordprg'`  and  remove  the  ad-hoc
        # command.  Besides,  the latter needs a  specific signature (`-buffer`,
        # `-nargs=1`,  `<q-args>`, ...).  And it  would introduce  an additional
        # dependency (`vim-lg`)  because you  would need to  move `UseManpage()`
        # (and copy `Error()`) into the latter.
        #
        # ---
        #
        # There is  an additional benefit  in dealing here with  filetypes which
        # need a special logic.
        # We  can tweak  `'iskeyword'` more  easily to  include some  characters
        # (e.g. `-`) when looking for the word under the cursor.
        # It's easier here, because we only  have to write the code dealing with
        # adding `-` to `'iskeyword'` once; no code duplication.
        #}}}
        if FiletypeIsSpecial()
            HandleSpecialFiletype(cnt)
        elseif &l:keywordprg != ''
            UseKp(cnt)
        elseif !OnCommentedLine() && FiletypeEnabledOnDevdocs()
            UseDevdoc()
        else
            echo 'no known command here (:h, $ cmd, man, info, CSI/OSC/DCS)'
        endif
        return
    endif
    if VisualSelectionContainsShellCode(type)
        execute 'Ch ' .. cmd
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
        #     command -bar -nargs=1 Ch Func(<q-args>)
        #     def Func(cmd: string)
        #         echo cmd
        #     enddef
        #
        #     Ch a"b
        #     a˜
        #     Ch a|b
        #     a˜
        #}}}
        cmd = escape(cmd, '"|')
        try
            execute cmd
        catch
            Catch()
            return
        endtry
        return
    endif
    # The regex is a little complex because a help topic can start with a slash.{{{
    #
    # Example: `:help /\@>`.
    #
    # In that case, when parsing the command, we must not *stop* at this slash.
    # Same thing when parsing the offset: we must not *start* at this slash.
    #}}}
    var topic: string
    [cmd, topic] = matchlist(cmd, '\(.\{-}\)\%(\%(:h\s\+\)\@<!\(/.*\)\|$\)')[1 : 2]
    execute cmd
    # `execute ... cmd` could fail without raising a real Vim error, e.g. `:Man not_a_cmd`.
    # In such a case, we don't want the cursor to move.
    if NotInDocumentationBuffer()
        return
    endif
    try
        # Why the loop?{{{
        #
        # You cannot simply write:
        #
        #     topic->trim('/', 0)->search('c')
        #
        # It would not  be able to handle multiple line  specifiers separated by
        # semicolons:
        #
        #     /foo/;/bar
        #
        # This syntax is only available in the range of an Ex command; see `:help :;`.
        #
        # ---
        #
        # Alternatively, we could just write:
        #
        #     execute ':' .. topic
        #
        # But, in  Vim9, I  try to  avoid `:execute`  as much  as possible,  in part
        # because it suppress the compilation of the executed command.
        #}}}
        for line_spec in topic->trim('/', 0)->split('/;/')
            search(line_spec, 'c')
        endfor
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
              '\C\s*\zs\%('
            ..    ':h\%[elp]\|info\|man\|CSI\|OSC\|DCS\|'
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
    return cmd
        # Ignore everything after a bar.{{{
        #
        # Useful to avoid an error when  pressing `K` while visually selecting a
        # shell command containing a pipe.
        # Also, we  don't want Vim  to interpret what follows  the bar as  an Ex
        # command; it could be anything, too dangerous.
        #}}}
        ->substitute('.\{-}\zs|.*', '', '')
enddef

def GetCodespan(line: string, cmd_pat: string): string #{{{2
    var cml: string = GetCml()
    var pat: string =
        # we are on a commented line
           '\%(^\s*' .. cml .. '.*\)\@<='
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
        ..     '`[^`]*\%.c[^`]*`'
        ..     '\|'
        # a codespan with the cursor on the opening backtick
        ..     '\%.c`[^`]*`'
        ..  '\)'

    # extract codespan from the line
    var codespan: string = line->matchstr(pat)
    # remove surrounding backticks
    codespan = codespan->trim('`')
    # extract command from the text
    # This serves 2 purposes.{{{
    #
    # Remove a possible leading `$` (shell prompt).
    #
    # Make  sure the text does  contain a command  for which our plugin  can find
    # some documentation.
    #}}}
    codespan = codespan->matchstr('^' .. cmd_pat)
    return codespan
enddef

def GetCodeblock(line: string, cmd_pat: string): string #{{{2
    var cml: string = GetCml()
    var n: number = &filetype == 'markdown' ? 4 : 5
    var pat: string = '^\s*' .. cml .. ' \{' .. n .. '}' .. cmd_pat
    var codeblock: string = line->matchstr(pat)
    return codeblock
enddef

def GetCword(): string #{{{2
    var iskeyword_save: string = &l:iskeyword
    var bufnr: number = bufnr('%')
    var cword: string
    try
        # Including the parens can be useful for a possible manpage section number:{{{
        #
        #     run-mailcap(1)
        #                ^ ^
        #}}}
        setlocal iskeyword+=-,(,)
        cword = expand('<cword>')
        if cword !~ '^\w\+(\d\+)$'
            setlocal iskeyword-=(,)
            cword = expand('<cword>')
        endif
    finally
        setbufvar(bufnr, '&iskeyword', iskeyword_save)
    endtry
    return cword
enddef

def HandleSpecialFiletype(cnt: number) #{{{2
    if &filetype == 'vim'
        || &filetype == 'markdown' && In('markdownHighlightvim')
        || &filetype == 'markdown' && getcwd() == $HOME .. '/wiki/vim'
        # there may be no help tag for the current word
        try
            execute 'help ' .. HelpTopic()
        catch
            Catch()
            return
        endtry
    elseif &filetype == 'tmux'
        try
            tmux#man()
        catch
            Catch()
            return
        endtry
    elseif &filetype == 'awk'
        UseManpage('awk', cnt)
    elseif &filetype == 'c'
        # For `C`, the man pages in the third section of the manual are better than devdocs.io:{{{
        #
        #    - no need of an internet connection
        #    - can search and copy text within Vim
        #}}}
        UseManpage('c', cnt)
    elseif &filetype == 'markdown'
        UseManpage('markdown', cnt)
    elseif &filetype == 'python'
        UsePydoc()
    elseif &filetype == 'sh'
        UseManpage('bash', cnt)
    endif
enddef

def UseManpage(name: string, cnt: number) #{{{2
    if exists(':Man') != 2
        Error(':Man command is not installed')
        return
    endif

    var cword: string = GetCword()
    if cword =~ '([0-9a-z])$'
        execute 'Man ' .. cword
        return
    endif

    var scnt: string
    if cnt != 0
        scnt = cnt->string()
    elseif &filetype == 'c'
        scnt = '3'
    endif
    var cmd: string = printf('Man %s %s', scnt, cword)
    if scnt != ''
        execute cmd
        return
    endif

    # there is no manpage for "markdown" or "C"
    if &filetype == 'markdown' || &filetype == 'c'
        return
    endif

    try
        # first try to look for the current word in the bash/awk manpage
        execute 'Man ' .. name
        var pat: string = '^\C\s*\zs\<' .. cword .. '\>\ze\%(\s\|$\)'
        execute ':/' .. pat
        setreg('/', [pat], 'c')
    catch /^Vim\%((\a\+)\)\=:E486:/
        # if you can't find it there, use it as the name of a manpage
        quit
        # Why not trying to catch a possible error if we press `K` on some random word?{{{
        #
        # When `:Man`  is passed the  name of  a non-existing manpage,  an error
        # message is echo'ed;  but it's just a message highlighted  in red; it's
        # not a real error, so you can't catch it.
        #}}}
        execute cmd
    catch /^Vim\%((\a\+)\)\=:E492:/
        # When can that happen?{{{
        #
        # Write this in a markdown file:
        #
        #     blah ``:help vim9 /`=``.
        #                      ^----^
        #                      press `K` on any of these characters
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
    if &l:keywordprg[0] == ':'
        try
            execute printf('%s %s %s', &l:keywordprg, cnt != 0 ? cnt : '', cword)
        catch /^Vim\%((\a\+)\)\=:\%(E149\|E434\):/
            Catch()
            return
        endtry
    else
        execute printf('!%s %s %s', &l:keywordprg, cnt ? cnt : '', shellescape(cword, true))
    endif
enddef

def UsePydoc() #{{{2
    var cword: string = GetCword()
    silent var doc: list<string> = systemlist('pydoc ' .. shellescape(cword))
    if get(doc, 0, '') =~ '^no Python documentation found for'
        echo doc[0]
        return
    endif
    execute 'new ' .. tempname()
    doc->setline(1)
    &l:bufhidden = 'delete'
    &l:buftype = 'nofile'
    &l:buflisted = false
    &l:swapfile = false
    &l:modifiable = false
    &l:readonly = true
    nmap <buffer><nowait> q <Plug>(my-quit)
enddef

def UseDevdoc() #{{{2
    var cword: string = GetCword()
    execute 'Doc ' .. cword .. ' ' .. &filetype
enddef

def VimifyCmd(arg_cmd: string): string #{{{2
    var cmd: string = arg_cmd
    if cmd =~ '^\%(info\|man\)\s'
        var Rep: func = (m: list<string>): string => m[0] == 'info' ? 'Info' : 'Man'
        cmd = cmd->substitute('^\%(info\|man\)', Rep, '')
    elseif cmd =~ '^\%(CSI\|OSC\|DCS\)\s'
        cmd = cmd->substitute('^', 'CtlSeqs /', '')
    elseif cmd =~ '^\$\s'
        cmd = cmd->substitute('^\$', 'Ch', '')
    elseif cmd =~ '^:h\%[elp]\s'
        # nothing to do; `:help` is already a Vim command
    else
        # When can this happen?{{{
        #
        # When  you visually  select some  text  which doesn't  match any  known
        # documentation command.
        #
        # Or when you refactor `GetCmd()` to support a new kind of documentation
        # command, but you forget to refactor this function to "vimify" it.
        #}}}
        echo 'not a documentation command (:help, $ cmd, man, info, CSI/OSC/DCS)'
        cmd = ''
    endif
    return cmd
enddef

def SetSearchRegister(topic: string) #{{{2
    # Populate the search register with  the topic if it doesn't contain
    # any offset, or with the last offset otherwise.
    if topic =~ '/;/'
        setreg('/', [topic->matchstr('.*/;/\zs.*')], 'c')
    # remove leading `/`
    else
        setreg('/', [topic[1 :]], 'c')
    endif
enddef

def HelpTopic(): string #{{{2
    var line: string = getline('.')
    var col: number = col('.')
    var charcol: number = charcol('.')
    var pat_pre: string
    if line[charcol - 1] =~ '\k'
        pat_pre = '.*\ze\<\k*\%.c'
    else
        pat_pre = '.*\%.c.'
    endif
    var pat_post: string = '\%.c\k*\>\zs.*'
    var pre: string = line->matchstr(pat_pre)
    var post: string = line->matchstr(pat_post)

    var syntax_item: string = synstack('.', col)
        ->mapnew((_, v: number): string => synIDattr(v, 'name'))
        ->reverse()
        ->get(0, '')
    var cword: string = expand('<cword>')

    if syntax_item == 'markdownCodeBlock'
        return cword
    elseif syntax_item == 'vimFuncName'
        || syntax_item == 'vim9FuncNameBuiltin'
        return cword .. '()'
    elseif syntax_item == 'vimOption'
        || syntax_item == 'vim9IsOption'
        return "'" .. cword .. "'"
    # `-bar`, `-nargs`, `-range`...
    elseif syntax_item == 'vimUserAttrbKey'
        || syntax_item == 'vim9UserAttrbKey'
        return ':command-' .. cword
    # `<silent>`, `<unique>`, ...
    elseif syntax_item == 'vimMapModKey'
        || syntax_item == 'vim9MapModKey'
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
        return 'v' .. post->matchstr(':\w\+')

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
    return index([
        'awk',
        'c',
        'markdown',
        'python',
        'sh',
        'tmux',
        'vim'
    ], &filetype) >= 0
enddef

def Error(msg: string) #{{{2
    echohl ErrorMsg
    echomsg msg
    echohl NONE
enddef

def OnCommentedLine(): bool #{{{2
    var cml: string = GetCml()
    if cml == ''
        return false
    endif
    return getline('.') =~ '^\s*' .. cml
enddef

def FiletypeEnabledOnDevdocs(): bool #{{{2
    return index(DEVDOCS_ENABLED_FILETYPES, &filetype) >= 0
enddef

def GetCml(): string #{{{2
    var cml: string
    if &filetype == 'markdown'
        cml = ''
    elseif &filetype == 'vim'
        cml = '["#]'
    else
        cml = '\V' .. &l:commentstring->matchstr('\S*\ze\s*%s')->escape('\') .. '\m'
    endif
    return cml
enddef

def VisualSelectionContainsShellCode(type: string): bool #{{{2
    return type == 'vis' && &filetype == 'sh' && !OnCommentedLine()
enddef

def NotInDocumentationBuffer(): bool #{{{2
    return index(['help', 'info', 'man'], &filetype) == -1
        && expand('%:t') != 'ctlseqs.txt.gz'
enddef

