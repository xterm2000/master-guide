# Kubectl alias

 
### Convention

`<kubectl>` `<command>` `<kind>`

e.g.

* `kubectl get deployment`   -> `kgd`
* `kubectl get replicaset`   -> `kgrs`
* `kubectl delete pod`       -> `kdp`
* `kubectl describe service` -> `kdess`
* `kubectl edit namespace`   -> `kens` 



### Usage

Clone project and add to `~/.bashrc` file ->

1. Clone repo
1. `vim ~/.bashrc`
3. paste (edit file location):
    ```
    if [ -f <path-to-cloned-repo>/kubectl_aliases ]; then
        source <path-to-cloned-repo>/kubectl_aliases
    fi
    ```

#### BASIC

| alias   | command                 | 
| ------- | ----------------------- |
| `k`     | `kubectl`               |
| `kl`    | `kubectl logs`          |
| `kexec` | `kubectl exec -it`      |
| `kpf`   | `kubectl port-forward`  |
| `kaci`  | `kubectl auth can-i`    |
| `katt`  | `kubectl attach`        |
| `kapir` | `kubectl api-resources` |
| `kapiv` | `kubectl api-versions`  |

#### GET

| alias   | command                           |
| ------- | --------------------------------- |
| `kg`    | `kubectl get`                     |
| `kgns`  | `kubectl get namespaces`          |
| `kgp`   | `kubectl get pods`                |
| `kgd`   | `kubectl get deployments`         |
| `kgs`   | `kubectl get secret`              |
| `kgrs`  | `kubectl get replicasets`         |
| `kgss`  | `kubectl get statefulsets`        |
| `kgds`  | `kubectl get daemonsets`          |
| `kgsvc` | `kubectl get services -o wide`    |
| `kgn`   | `kubectl get nodes -o wide`       |
| `kgcm`  | `kubectl get configmaps`          |
| `kgcj`  | `kubectl get cronjobs`            |
| `kgj`   | `kubectl get jobs`                |
| `kgsa`  | `kubectl get serviceaccounts`     | 
| `kgr`   | `kubectl get roles`               |
| `kgrb`  | `kubectl get rolebindings`        |
| `kgcr`  | `kubectl get clusterroles`        |
| `kgcrb` | `kubectl get clusterrolebindings` |
 
#### DESCRIBE

| alias   | command                                |
| ------- | -------------------------------------- |
| `kd`    | `kubectl describe`                     | 
| `kdns`  | `kubectl describe namespaces`          |
| `kdp`   | `kubectl describe pods`                |
| `kdd`   | `kubectl describe deployments`         |
| `kds`   | `kubectl describe secret`              |
| `kdrs`  | `kubectl describe replicasets`         |
| `kdss`  | `kubectl describe statefulsets`        |
| `kdds`  | `kubectl describe daemonsets`          |
| `kdsvc` | `kubectl describe services -o wide`    |
| `kdn`   | `kubectl describe nodes -o wide`       |
| `kdcm`  | `kubectl describe configmaps`          |
| `kdcj`  | `kubectl describe cronjobs`            |
| `kdj`   | `kubectl describe jobs`                |
| `kdsa`  | `kubectl describe serviceaccounts`     |
| `kdr`   | `kubectl describe roles`               |
| `kdrb`  | `kubectl describe rolebindings`        |
| `kdcr`  | `kubectl describe clusterroles`        |
| `kdcrb` | `kubectl describe clusterrolebindings` |

#### EDIT

| alias   | command                            |
| ------- | ---------------------------------- |
| `ke`    | `kubectl edit`                     |
| `kens`  | `kubectl edit namespaces`          |
| `ked`   | `kubectl edit deployments`         |
| `kers`  | `kubectl edit replicasets`         |
| `kes`   | `kubectl edit secret`              |
| `kess`  | `kubectl edit statefulsets`        |
| `keds`  | `kubectl edit daemonsets`          |
| `kesvc` | `kubectl edit services`            |
| `kecm`  | `kubectl edit configmaps`          |
| `kecj`  | `kubectl edit cronjobs`            |
| `kesa`  | `kubectl edit serviceaccounts`     |
| `ker`   | `kubectl edit roles`               |
| `kerb`  | `kubectl edit rolebindings`        |
| `kecr`  | `kubectl edit clusterroles`        |
| `kecrb` | `kubectl edit clusterrolebindings` | 

#### DELETE

| alias     | command                              |
| --------- | ------------------------------------ |
| `kdel`    | `kubectl delete`                     |
| `kdelns`  | `kubectl delete namespaces`          |
| `kdelp`   | `kubectl delete pods`                | 
| `kdeld`   | `kubectl delete deployments`         |
| `kdelrs`  | `kubectl delete replicasets`         |
| `kdelss`  | `kubectl delete statefulsets`        |
| `kdelds`  | `kubectl delete daemonsets`          |
| `kdelsvc` | `kubectl delete services`            |
| `kdels`   | `kubectl delete secret`              |
| `kdelcm`  | `kubectl delete configmaps`          |
| `kdelcj`  | `kubectl delete cronjobs`            |
| `kdelj`   | `kubectl delete jobs`                |
| `kdelsa`  | `kubectl delete serviceaccounts`     |
| `kdelr`   | `kubectl delete roles`               |
| `kdelrb`  | `kubectl delete rolebindings`        |
| `kdelcr`  | `kubectl delete clusterroles`        |
| `kdelcrb` | `kubectl delete clusterrolebindings` |

 

#### CONFIG

| alias         | command                                            |
| ------------- | -------------------------------------------------- |
| `kcfg`        | `kubectl config`                                   |
| `kcfgv`       | `kubectl config view`                              |
| `kcfgns`      | `kubectl config set-context --current --namespace` |
| `kcfgcurrent` | `kubectl config current-context`                   |
| `kcfgsc`      | `kubectl config set-context`                       |
| `kcfggc`      | `kubectl config get-contexts`                      |
| `kcfguc`      | `kubectl config use-context`                       |


```bash
# BASIC
alias k=kubectl
alias kl="kubectl logs"
alias kexec="kubectl exec -it"
alias kpf="kubectl port-forward"
alias kaci="kubectl auth can-i"
alias katt="kubectl attach"
alias kapir="kubectl api-resources"
alias kapiv="kubectl api-versions"

# GET
alias kg="kubectl get"
alias kgns="kubectl get namespaces"
alias kgp="kubectl get pods"
alias kgd="kubectl get deployments"
alias kgs="kubectl get secret"
alias kgrs="kubectl get replicasets"
alias kgss="kubectl get statefulsets"
alias kgds="kubectl get daemonsets"
alias kgsvc="kubectl get services -o wide"
alias kgn="kubectl get nodes -o wide"
alias kgcm="kubectl get configmaps"
alias kgcj="kubectl get cronjobs"
alias kgj="kubectl get jobs"
alias kgsa="kubectl get serviceaccounts"
alias kgr="kubectl get roles"
alias kgrb="kubectl get rolebindings"
alias kgcr="kubectl get clusterroles"
alias kgcrb="kubectl get clusterrolebindings"

# DESCRIBE
alias kd="kubectl describe"
alias kdns="kubectl describe namespaces"
alias kdp="kubectl describe pods"
alias kdd="kubectl describe deployments"
alias kds="kubectl describe secret"
alias kdrs="kubectl describe replicasets"
alias kdss="kubectl describe statefulsets"
alias kdds="kubectl describe daemonsets"
alias kdsvc="kubectl describe services -o wide"
alias kdn="kubectl describe nodes -o wide"
alias kdcm="kubectl describe configmaps"
alias kdcj="kubectl describe cronjobs"
alias kdj="kubectl describe jobs"
alias kdsa="kubectl describe serviceaccounts"
alias kdr="kubectl describe roles"
alias kdrb="kubectl describe rolebindings"
alias kdcr="kubectl describe clusterroles"
alias kdcrb="kubectl describe clusterrolebindings"

# EDIT
alias ke="kubectl edit"
alias kens="kubectl edit namespaces"
alias ked="kubectl edit deployments"
alias kers="kubectl edit replicasets"
alias kes="kubectl edit secret"
alias kess="kubectl edit statefulsets"
alias keds="kubectl edit daemonsets"
alias kesvc="kubectl edit services"
alias kecm="kubectl edit configmaps"
alias kecj="kubectl edit cronjobs"
alias kesa="kubectl edit serviceaccounts"
alias ker="kubectl edit roles"
alias kerb="kubectl edit rolebindings"
alias kecr="kubectl edit clusterroles"
alias kecrb="kubectl edit clusterrolebindings"

# DELETE
alias kdel="kubectl delete"
alias kdelns="kubectl delete namespaces"
alias kdelp="kubectl delete pods"
alias kdeld="kubectl delete deployments"
alias kdelrs="kubectl delete replicasets"
alias kdelss="kubectl delete statefulsets"
alias kdelds="kubectl delete daemonsets"
alias kdelsvc="kubectl delete services"
alias kdels="kubectl delete secret"
alias kdelcm="kubectl delete configmaps"
alias kdelcj="kubectl delete cronjobs"
alias kdelj="kubectl delete jobs"
alias kdelsa="kubectl delete serviceaccounts"
alias kdelr="kubectl delete roles"
alias kdelrb="kubectl delete rolebindings"
alias kdelcr="kubectl delete clusterroles"
alias kdelcrb="kubectl delete clusterrolebindings"

 

# CONFIG
alias kcfg="kubectl config"
alias kcfgv="kubectl config view"
alias kcfgns="kubectl config set-context --current --namespace"
alias kcfgcurrent="kubectl config current-context"
alias kcfgsc="kubectl config set-context"
alias kcfggc="kubectl config get-contexts"
alias kcfguc="kubectl config use-context"
```

