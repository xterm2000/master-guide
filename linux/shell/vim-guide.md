#vim #guide 
 
## Vim guide 
## Navigation

| Command      | Description                              |
| ------------ | ---------------------------------------- |
| `shift + g`  | End of the file                          |
| `j`          | Next line                                |
| `number + j` | Go down a defined number of lines        |
| `w`          | Skip to next word                        |
| `b`          | Skip back a word                         |
| `W`          | Skip to next section                     |
| `B`          | Skip back to previous section            |
| `$`          | Go to end of the line                    |
| `0`          | Go to beginning of the line              |
| `shift + h`  | Go to top of the screen                  |
| `shift + l`  | Go to bottom of the screen               |
| `5w`         | Forward multiple words                   |
| `5l`         | Forward multiple letters                 |
| `5h`         | Back multiple letters                    |
| `fy`         | Forward to the next 'y' (case sensitive) |

## Editing

| Command     | Description                             |
| ----------- | --------------------------------------- |
| `u`         | Undo                                    |
| `ctrl + r`  | Redo                                    |
| `i`         | Inserting text where the cursor is      |
| `I`         | Inserting text at the start of the line |
| `shift + a` | Insert at the end of the line           |
| `yy` or `Y` | Copy entire line                        |
| `p`         | Paste copied line                       |
| `5cw`       | Change multiple words                   |
| `A`         | Insert at the end of the line           |
| `r`         | Replace character                       |

## Deleting

| Command              | Description                                                      |
| -------------------- | ---------------------------------------------------------------- |
| `d ←`                | Delete current and left character                                |
| `d$`                 | Delete from current position to end of line                      |
| `d^`                 | Delete from current backward to first non-white-space character  |
| `d0`                 | Delete from current backward to beginning of line                |
| `dw`                 | Delete current to end of current word (including trailing space) |
| `db`                 | Delete current to beginning of current word                      |
| `dd`                 | Delete current line                                              |
| `shift + j`          | Join the line below                                              |
| `cw`                 | Delete entire word                                               |
| `shift + C`          | Delete to the end of the line                                    |
| `d + number + enter` | Delete multiple lines                                            |
| `d[line number]G`    | Delete from current position to a specific line number           |
| `:g/^pattern/d`      | Delete all items in a file that start with a pattern             |
| `:g/^\s*$/d`         | Delete all lines that are empty or contain only whitespace       |

## Selecting

| Command    | Description            |
| ---------- | ---------------------- |
| `V`        | Select the entire line |
| `v`        | Select a range of text |
| `ctrl + v` | Select a column        |
| `gv`       | Reselect a block       |
| `ggVG`     | Select all             |

## Find and Replace

| Command                      | Description      |
| ---------------------------- | ---------------- |
| `%s/pattern/text to replace` | Find and replace |


In Vim, search and replace uses the `:substitute` command:

**Basic syntax:**

```
:[range]s/search/replace/[flags]
```

**Common examples:**

```vim
:s/foo/bar/        " replace first match on current line
:s/foo/bar/g       " replace all matches on current line
:%s/foo/bar/g      " replace all matches in entire file
:%s/foo/bar/gc     " replace all, confirm each one
:5,10s/foo/bar/g   " replace in lines 5–10
:'<,'>s/foo/bar/g  " replace in visual selection
```

**Useful flags:**

|Flag|Meaning|
|---|---|
|`g`|All occurrences per line (not just first)|
|`c`|Confirm each replacement|
|`i`|Case-insensitive|
|`I`|Case-sensitive (overrides `ignorecase`)|

**Tips:**

- Use `\<word\>` for whole-word matching: `:%s/\<foo\>/bar/g`
- The `matchpairs` setting you have doesn't affect search/replace - it only changes what `%` jumps between
- During `gc` confirm mode: `y` yes, `n` no, `a` all remaining, `q` quit, `l` replace this one then quit


## Saving

| Command | Description            |
| ------- | ---------------------- |
| `:w`    | Save the file          |
| `:wq`   | Save the file and quit |
| `:q!`   | Quit without saving    |

## Views

| Command         | Description               |
| --------------- | ------------------------- |
| `:sp filename`  | Use horizontal split      |
| `:vsp filename` | Use vertical split        |
| `ctrl + w + j`  | Switch from top to bottom |
| `ctrl + w + l`  | Switch from left to right |
| `ctrl + w + j`  | Switch from bottom to top |
| `ctrl + w + h`  | Switch from right to left |

## Search

| Command         | Description                  |
| --------------- | ---------------------------- |
| `f + <item>`    | Search while on current line |
| `/word + enter` | Search for word in file      |
| `n`             | Find next search result      |
| `N`             | Search backwards             |
| `ggn`           | Go to first result           |
| `GN`            | Go to last result            |
| `:noh`          | Remove search highlighting   |

## Modes

| Mode         | 
| ------------ |
| Normal       |
| Insert       |
| Visual       |
| Replace      |
| Command Line |

## Multiple Files

| Command           | Description                                  |
| ----------------- | -------------------------------------------- |
| `:e filename`     | Edit a file in a new buffer                  |
| `:bnext` or `:bn` | Go to next buffer                            |
| `:bprev` or `:bp` | Go to previous buffer                        |
| `:bd`             | Delete a buffer (close a file)               |
| `:sp filename`    | Open a file in a new buffer and split window |
| `ctrl + ws`       | Split windows                                |
| `ctrl + ww`       | Switch between windows                       |
| `ctrl + wq`       | Quit a window                                |
| `ctrl + wv`       | Split windows vertically                     |

## Indenting

| Command     | Description                            |
| ----------- | -------------------------------------- |
| `set paste` | Fix indenting when pasting (in .vimrc) |
| `< >`       | Indenting in visual mode               |
| `.`         | Repeat indenting                       |

## Commenting/Uncommenting

| Command              | Description                                             |
| -------------------- | ------------------------------------------------------- |
| `ctrl + v` then `I#` | Comment: visual block select then insert # at beginning |
| `ctrl + v` then `X`  | Uncomment: visual block select then delete first symbol |

## Visual Mode

| Command                               | Description                   |
| ------------------------------------- | ----------------------------- |
| `ctrl + v + shift + i + action + esc` | Change multiple lines of text |
| `v + / + content`                     | Select elements in paragraph  |

## Display Settings

| Command      | Description                 |
| ------------ | --------------------------- |
| `:set nu`    | Turn on line numbers        |
| `:syntax on` | Turn on syntax highlighting |

## Resetting Vim Settings


### Reseting Vim Settings

```bash
cd
mv .vimrc .vimrc-old
mv .vim .vim-old
touch .vimrc; mkdir .vim
```

### Help

- To get help: :h `<topic>`
- To exit help: :bd


### Removing blocks of text in code files

- `c + i + t` will remove the code between HTML tags, such as: `<div>Some content</div>`
- `c + i + }` will remove the code inside of a JavaScript function

## vimrc

yaml plugin
```bash
git clone https://github.com/Yggdroot/indentLine.git ~/.vim/pack/vendor/start/indentLine
vim -u NONE -c "helptags  ~/.vim/pack/vendor/start/indentLine/doc" -c "q"
```
this goes in the .vimrc
`let g:indentLine_char_list = ['|', '¦', '┆', '┊']`

```vim
" Don't try to be vi compatible
set nocompatible

" Helps force plugins to load correctly when it is turned back on below
filetype off

" TODO: Load plugins here (pathogen or vundle)

" Turn on syntax highlighting
syntax on

" For plugins to load correctly
filetype plugin indent on

" TODO: Pick a leader key
" let mapleader = ","

" Security
set modelines=0

" Show line numbers
set number

" Show file stats
set ruler

" Blink cursor on error instead of beeping (grr)
" set visualbell

" Encoding
set encoding=utf-8

" Whitespace
set wrap
set textwidth=79
set formatoptions=tcqrn1
set tabstop=2
set shiftwidth=2
set softtabstop=2
set expandtab
set noshiftround

" Cursor motion
set scrolloff=3
set backspace=indent,eol,start
set matchpairs+=<:> " use % to jump between pairs
runtime! macros/matchit.vim

" Move up/down editor lines
nnoremap j gj
nnoremap k gk

" Allow hidden buffers
set hidden

" Rendering
set ttyfast

" Status bar
set laststatus=2

" Last line
set showmode
set showcmd

" Searching
nnoremap / /\v
vnoremap / /\v
set hlsearch
set incsearch
set ignorecase
set smartcase
set showmatch
map <leader><space> :let @/=''<cr> " clear search

" Remap help key.
inoremap <F1> <ESC>:set invfullscreen<CR>a
nnoremap <F1> :set invfullscreen<CR>
vnoremap <F1> :set invfullscreen<CR>

" Textmate holdouts

" Formatting
map <leader>q gqip

" Visualize tabs and newlines
set listchars=tab:▸\ ,eol:¬
" Uncomment this to enable by default:
" set list " To enable by default
" Or use your leader key + l to toggle on/off
map <leader>l :set list!<CR> " Toggle tabs and EOL

" Color scheme (terminal)
set t_Co=256
set background=dark
let g:solarized_termcolors=256
let g:solarized_termtrans=1
" put https://raw.github.com/altercation/vim-colors-solarized/master/colors/solarized.vim
" in ~/.vim/colors/ and uncomment:
" colorscheme solarized
```
