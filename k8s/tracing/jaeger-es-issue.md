# Jaeger + Elasticsearch Debugging Runbook

## Problem Summary

Jaeger was running (collector, query, operator all healthy) but no traces appeared in the UI.
Root cause: a manually created `jaeger` index template had `startTimeMillis` mapped as `long`,
which conflicted with Jaeger 1.19.2 trying to write it as a `date` with `epoch_millis` format
on Elasticsearch 7.9.1. Every span write was rejected with a `mapper_parsing_exception`.

---

## Diagnosis

### 1. Check ES cluster version

```
kubectl exec -n curl <curl-pod-name> -- curl -s "http://elasticsearch-master:9200/"
```

Returns version info. We were on **ES 7.9.1** (Lucene 8.6.2).

---

### 2. List all indices

```
kubectl exec -n curl <curl-pod-name> -- curl -s "http://elasticsearch-master:9200/_cat/indices?v"
```

Shows all indices with doc counts. Key observation: `jaeger-service-*` indices existed and had
docs (services were registering), but **no `jaeger-span-*` indices existed** — spans were being
silently dropped.

---

### 3. Check index mapping on a specific index

```
kubectl exec -n curl <curl-pod-name> -- curl -s "http://elasticsearch-master:9200/jaeger-span-2026-05-28/_mapping"
```

Revealed `startTimeMillis` was mapped as `"type": "long"` instead of `"type": "date"`.
This is the conflicting mapping that caused every span write to fail.

---

### 4. Check index templates

```
kubectl exec -n curl <curl-pod-name> -- curl -s "http://elasticsearch-master:9200/_cat/templates?v"
```

Lists all templates. Found a `jaeger` template matching `jaeger-*` with **order 10**,
meaning it takes precedence over Jaeger's own templates (order 0).

---

### 5. Inspect the offending template

```
kubectl exec -n curl <curl-pod-name> -- curl -s "http://elasticsearch-master:9200/_template/jaeger"
```

Revealed the catch-all `jaeger` template with `startTimeMillis: { "type": "long" }` —
the root cause. This template was manually created years ago and had been poisoning
every new `jaeger-span-*` index ever since.

---

### 6. Check a specific named template

```
kubectl exec -n curl <curl-pod-name> -- curl -s "http://elasticsearch-master:9200/_template/jaeger-span"
```

Used to inspect whether a more specific `jaeger-span` template existed and what its
mapping looked like.

---

## Fix

### Step 1 — Scale collectors to zero (prevent index recreation during cleanup)

```bash
kubectl scale deployment/tracing-jaeger-operator-jaeger-collector -n tracing --replicas=0
kubectl rollout status deployment/tracing-jaeger-operator-jaeger-collector -n tracing
```

---

### Step 2 — Delete all Jaeger indices (clean slate)

```
kubectl exec -n curl <curl-pod-name> -- curl -s -X DELETE "http://elasticsearch-master:9200/_all"
```

Wipes all indices. Safe here because ES was Jaeger-only (confirmed in step 2 of diagnosis).

---

### Step 3 — Delete stale templates

```
kubectl exec -n curl <curl-pod-name> -- curl -s -X DELETE "http://elasticsearch-master:9200/_template/jaeger-span"
kubectl exec -n curl <curl-pod-name> -- curl -s -X DELETE "http://elasticsearch-master:9200/_template/jaeger-service"
```

Removes any Jaeger-managed templates so they get recreated correctly on next startup.

---

### Step 4 — Fix the offending catch-all template

This was the critical fix. Updated `startTimeMillis` from `long` to `date` (no `format`
parameter — omitting `epoch_millis` avoids the ES 7.9.1 rejection bug):

```bash
kubectl exec -n curl <curl-pod-name> -- curl -s -X PUT \
  "http://elasticsearch-master:9200/_template/jaeger" \
  -H 'Content-Type: application/json' \
  -d '{
    "order": 10,
    "index_patterns": ["jaeger-*"],
    "settings": {
      "index": {
        "number_of_replicas": "0"
      }
    },
    "mappings": {
      "properties": {
        "traceID":         { "type": "keyword" },
        "spanID":          { "type": "keyword" },
        "duration":        { "type": "long" },
        "operationName":   { "type": "keyword" },
        "serviceName":     { "type": "keyword" },
        "startTimeMillis": { "type": "date" },
        "process": {
          "properties": {
            "serviceName": { "type": "keyword" }
          }
        }
      }
    }
  }'
```

Key decisions:
- `"type": "date"` without `"format": "epoch_millis"` — ES 7.9.1 rejects the `format`
  parameter in this context; omitting it lets ES accept epoch millisecond values natively
- `"number_of_replicas": "0"` preserved — intentional setting for this single-node cluster
- `order: 10` preserved — this template still needs to win over Jaeger's own (order 0)
  so the replica setting applies

---

### Step 5 — Confirm template is correct

```
kubectl exec -n curl <curl-pod-name> -- curl -s "http://elasticsearch-master:9200/_template/jaeger"
```

Verify `startTimeMillis` shows `"type": "date"` with no `format` key.

---

### Step 6 — Scale collectors back up

```bash
kubectl scale deployment/tracing-jaeger-operator-jaeger-collector -n tracing --replicas=5
kubectl rollout status deployment/tracing-jaeger-operator-jaeger-collector -n tracing
```

Jaeger recreates its own `jaeger-span` and `jaeger-service` templates (order 0) on startup.
The catch-all `jaeger` template (order 10) applies on top, overriding `startTimeMillis`
to `date` before any index is written.

---

### Step 7 — Verify with a test span (Zipkin format)

```bash
kubectl exec -n curl <curl-pod-name> -- curl -s -X POST \
  "http://tracing-jaeger-operator-jaeger-collector.tracing.svc:9411/api/v2/spans" \
  -H 'Content-Type: application/json' \
  -d '[{
    "traceId": "deadbeef00000000deadbeef00000007",
    "id": "deadbeef00000007",
    "name": "template-fix-test",
    "timestamp": '"$(date +%s%6N)"',
    "duration": 1000,
    "localEndpoint": { "serviceName": "template-fix-test" }
  }]'
```

Expected response: `HTTP 202 Accepted`

Then confirm the span landed in ES:

```
kubectl exec -n curl <curl-pod-name> -- curl -s "http://elasticsearch-master:9200/_cat/indices?v"
```

`jaeger-span-<today>` should appear with `docs.count > 0`.

Query via Jaeger API to confirm end-to-end:

```
kubectl exec -n curl <curl-pod-name> -- curl -s "http://tracing-jaeger-operator-jaeger-query:16686/api/traces/deadbeef00000000deadbeef00000007"
```

---

## Secondary Issue: Apps Sending to Wrong Endpoint

Some services were logging:

```
failed to flush Jaeger spans to server: write udp ...->100.103.76.234:6831: connection refused
```

These apps are using the **jaeger-client UDP reporter** pointed at a jaeger-agent that
doesn't exist at that IP. Port 6831 (UDP compact thrift) is a jaeger-agent port, not
a collector port.

Fix options:
- Point apps directly at the collector via HTTP: `JAEGER_ENDPOINT=http://tracing-jaeger-operator-jaeger-collector:14268/api/traces`
- Or deploy a jaeger-agent DaemonSet so port 6831 UDP is reachable on each node's host IP

---

## Collector Ports Reference

| Port  | Protocol | Purpose                        |
|-------|----------|--------------------------------|
| 9411  | HTTP     | Zipkin v2 spans                |
| 14268 | HTTP     | Jaeger thrift spans            |
| 14250 | gRPC     | Jaeger proto spans (from agent)|
| 14267 | TCP      | Jaeger thrift (legacy)         |
| 14269 | HTTP     | Admin/healthcheck              |

---

## Why This Happened

The `jaeger` catch-all template was created manually (likely years ago during initial cluster
setup with an older Jaeger version that used `long` for `startTimeMillis`). When Jaeger was
later upgraded to 1.19.2, it started writing `startTimeMillis` as a `date` with `epoch_millis`
format — but the high-order template always won, forcing `long` onto every new index first.
ES then rejected the type conflict on every span write. The `jaeger-service-*` indices were
unaffected because service records don't use `startTimeMillis`.
