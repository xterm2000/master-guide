# Heredocs (`<<`) — Multi-line Input Guide

## Basic Syntax

```bash
cat > file.txt << EOF
line 1
line 2
EOF
```

Everything between the opening `<< EOF` and a line containing only `EOF` becomes the command's stdin. The delimiter name is arbitrary — `EOF`, `DOC_END`, `SQL`, anything — the shell just needs the opening and closing tokens to match exactly.

---

## Delimiter Quoting — the part that actually matters

| Form | Variable / command substitution inside the body? |
|---|---|
| `<<EOF` (unquoted) | **Enabled** — `$var`, `` `cmd` ``, `$(cmd)` all expand, same rules as a double-quoted string |
| `<<"EOF"` | Disabled |
| `<<'EOF'` | Disabled |
| `<<\EOF` | Disabled |

The last three are **functionally identical**. Any form of quoting on the delimiter word — double quotes, single quotes, or a backslash before any character of it — disables expansion inside the body. Which one you use is pure style, not behavior. `.git/hooks/pre-rebase.sample` used the backslash form (`<<\DOC_END`), which is rarer to see than `<<'EOF'` but does exactly the same thing.

```bash
name=world

cat << EOF
Hello $name
EOF
# -> Hello world

cat << 'EOF'
Hello $name
EOF
# -> Hello $name        (literal — no substitution happened)
```

---

## Stripping Leading Tabs — `<<-`

```bash
if true; then
	cat <<- EOF
	this line is indented in the source but prints flush left
	EOF
fi
```

`<<-` strips **leading tab characters** (not spaces) from every line of the body and from the closing delimiter line — this lets you indent a heredoc to match the surrounding code's indentation without breaking the closing-delimiter match. It does nothing for spaces; if your editor silently converts tabs to spaces (most do, by default), `<<-` stops working with no visible error.

---

## No Command in Front = Block Comment Trick

```bash
<<\DOC_END
Anything in here is inert text — never executed, never printed.
A poor-man's block comment for shells that have no /* */ syntax.
DOC_END
```

This is exactly what `.git/hooks/pre-rebase.sample` does at the bottom of the file. A bare redirection with no command still opens stdin for a no-op, so the shell reads and silently discards the whole block. Combined with the backslash-quoting above (so nothing inside it gets expanded/executed), it's a clean way to leave long-form documentation inside a script that otherwise has no comment-block syntax.

---

## Heredoc Into a Variable

```bash
read -r -d '' block << 'EOF'
line one
line two
EOF
echo "$block"
```

`read -d ''` sets the delimiter to NUL, which normally never appears in text — so `read` keeps consuming until the heredoc ends, capturing the whole multi-line block (newlines included) into one variable instead of printing it.

---

## Herestrings `<<<` — the One-Line Cousin

```bash
grep "foo" <<< "$myvar"      # feed an already-expanded variable's value as stdin
```

Not technically a heredoc, but easy to confuse with one — a herestring feeds a single string (already fully expanded) as stdin, no delimiter or multi-line block needed. Useful when you just want to pipe a variable into something that expects stdin, without a temp file or `echo | ...`.

---

## Practical Patterns Seen in This Repo

```bash
# Remote multi-line script execution over SSH (k8s/kubespray-bastion-aws-ec2.md)
ssh host 'bash -s' << 'EOF'
sudo dnf install -y podman
echo "done"
EOF

# Generating a YAML manifest with variable substitution
cat > cluster-issuer.yaml << EOF
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-prod
spec:
  acme:
    email: ${EMAIL}
EOF

# Embedding another language's script inline
python3 << 'PYEOF'
print("no shell expansion happens in here")
PYEOF
```

---

## Gotchas

- **The closing delimiter must be alone on its line, at the very start**, with no trailing whitespace and no trailing characters (unless using `<<-`, which only tolerates leading tabs). A stray space after `EOF` or before it (without `<<-`) means the shell never recognizes the close, and it keeps reading — often swallowing the rest of the script and producing a confusing "unexpected EOF" error far from the real cause.
- **Quoting is all-or-nothing for the whole body** — you can't selectively expand some variables and leave others literal within a single heredoc. If you need a mix, either escape individual `$` signs (`\$`) in an unquoted heredoc, or split the content across separate heredocs.
- **Picking a generic delimiter name** (`EOF` nested inside another `EOF`) gets confusing fast in scripts with more than one heredoc — prefer descriptive names (`SQL_EOF`, `YAML_EOF`) when there's more than one in the same file.
- **A heredoc with no preceding command isn't an error** — it's valid syntax (see the block-comment trick above), which is exactly why it can look mysterious the first time you encounter it in someone else's script.

---

## See Also

- `sed.md` (in-place editing) and `awk.md` (`BEGIN`/`END`) for other ways this repo constructs/transforms multi-line text
- `../ssh/` guides for the remote heredoc pattern (`ssh host 'bash -s' << EOF`) in actual use
