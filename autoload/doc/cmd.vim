vim9script noclear

if exists('loaded') | finish | endif
var loaded = true

# Init {{{1

# Could we get it programmatically?{{{
#
# You could use `findfile()`:
#
#     :echo findfile('ctlseqs.txt.gz', '/usr/share/**')
#                                                  ^^
#                                                  could append a small number to limit the recursiveness
#                                                  and make the command faster
# Or `find(1)`:
#
#     :echo system('find /usr -path "*/xterm/*ctlseqs.txt.gz"')->trim("\n", 2)
#
# But those commands take some time.
# Not sure it's worth it for the moment.
#}}}
const PATH_TO_CTLSEQS: string = '/usr/share/doc/xterm/ctlseqs.txt.gz'

# Interface {{{1
def doc#cmd#ch(shell_cmd: string) #{{{2
    var cmd: string
    if shell_cmd == ''
        cmd = getline('.')
    else
        cmd = shell_cmd
    endif
    # The bang suppresses an error in case we've visually a command with an unterminated string:{{{
    #
    #     awk '{print $1}'
    #     ^-------^
    #     selection; the closing quote is missing
    #}}}
    sil! systemlist('ch ' .. cmd .. ' 2>/dev/null')->setreg('o', 'c')
    echo @o
enddef

def doc#cmd#ctlseqs() #{{{2
    if CtlseqsFileIsAlreadyDisplayed()
        FocusCtlseqsWindow()
    else
        exe 'noswapfile sp +1 ' .. PATH_TO_CTLSEQS
    endif
    if expand('%:t') == 'ctlseqs.txt.gz'
        nno <buffer><expr><nowait> q reg_recording() != '' ? 'q' : '<cmd>q!<cr>'
    endif
enddef

def doc#cmd#info(topic: string) #{{{2
    new
    exe ':.!info ' .. topic
    if bufname('%') != ''
        return
    endif
    # the filetype needs to be `info`, otherwise `doc#mapping#main` would return
    # too early when there is a pattern to search
    setl ft=info bh=delete bt=nofile nobl noswf nowrap
    nno <buffer><expr><nowait> q reg_recording() != '' ? 'q' : '<cmd>q<cr>'
enddef

def doc#cmd#doc(keyword = '', filetype = '') #{{{2
    if keyword == '' && filetype == ''
        || (keyword == '--help' || keyword == '-h')
        var usage: list<string> =<< trim END
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

    var cmd: string = 'xdg-open'
    # For the syntax of the query, see this link:
    # https://devdocs.io/help#search
    var url: string = 'http://devdocs.io/?q='

    var args: string = filetype == ''
        ? url .. &ft .. ' ' .. keyword
        : url .. filetype .. ' ' .. keyword

    sil system(cmd .. ' ' .. shellescape(args))
enddef
#}}}1
# Core {{{1
def FocusCtlseqsWindow() #{{{2
    var bufnr: number = bufnr('ctlseqs\.txt.\gz$')
    var winids: list<number> = win_findbuf(bufnr)
    var tabpagenr: number = tabpagenr()
    winids
        ->filter((_, v: number): bool => getwininfo(v)[0]['tabnr'] == tabpagenr)
        ->get(0)
        ->win_gotoid()
enddef
#}}}1
# Utilities {{{1
def CtlseqsFileIsAlreadyDisplayed(): bool #{{{2
    return tabpagebuflist()
        ->mapnew((_, v: number): string => bufname(v))
        ->match('ctlseqs\.txt\.gz$') >= 0
enddef

