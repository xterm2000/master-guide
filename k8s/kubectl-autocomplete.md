Simple and clean:

##  install bash-completion
```bash
sudo dnf install bash-completion -y
```


## Create the file

```bash
cat > ~/.kube_auto_complete << 'EOF'
# ~/.kube_auto_complete
# Kubernetes shell completion and aliases
# Source this from ~/.bashrc

# Load bash-completion if not already loaded
if [ -f /usr/share/bash-completion/bash_completion ]; then
    source /usr/share/bash-completion/bash_completion
fi

# kubectl completion
source <(kubectl completion bash)

# kubectl alias with completion
alias k=kubectl
complete -o default -F __start_kubectl k
EOF
```

## Add to `.bashrc`

```bash
echo '[ -f ~/.kube_auto_complete ] && source ~/.kube_auto_complete' >> ~/.bashrc
```

## Apply now

```bash
source ~/.kube_auto_complete
```

That's it. Next time you open a terminal it loads automatically, and the `-f` guard means it won't error if the file is ever missing.


## Test
```bash
type _init_completion 2>/dev/null && echo "OK" || echo "bash-completion not loaded"
```