```bash
# strips the logs
kubectl cluster-info dump | sed '/==== START logs/,/==== END logs/d' > cluster-dump.yaml

# This sends stderr progress messages to `messages.log` and the clean dump to `cluster-dump.yaml` simultaneously.
kubectl cluster-info dump 2>messages.log | sed '/==== START logs/,/==== END logs/d' > cluster-dump.yaml

# with clearer separation 
kubectl cluster-info dump 2>messages.log | tee >(grep -A999999 '==== START logs' | grep -B999999 '==== END logs' > logs.txt) | sed '/==== START logs/,/==== END logs/d' > cluster-dump.yaml
```