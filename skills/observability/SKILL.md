---
name: observability
description: Designing logging, metrics, and tracing into a system so you can debug production without a debugger. Covers structured logging, metric type selection (counter/gauge/histogram), trace span hygiene, OpenTelemetry basics, cardinality discipline, and the anti-patterns (log-and-rethrow, log-and-swallow, log-everything). Pairs with `debugging-workflow` (which is reactive — observability is the proactive instrumentation that makes debugging tractable) and `error-handling-strategies` (errors are a primary log/metric signal). Trigger when designing logging for a new service, instrumenting a hot path with metrics, adding tracing across a request boundary, deciding what log level a message should be, or critiquing existing observability.
---

# Observability

Observability is what lets you debug a system you don't have a debugger on. The instrumentation you wish you'd added — at the time you needed it — is what this skill is about adding *before* you need it, in a form that's actually useful.

## The three pillars

Each answers a different question.

| Pillar | Answers | Cardinality budget | Example |
|---|---|---|---|
| **Logs** | "What happened?" (per event) | Unlimited (you can log unique IDs) | "user 1234 failed login: bad password" |
| **Metrics** | "How much / how often / how slow?" (aggregated) | Strictly bounded — high cardinality kills systems | `http_requests_total{method="GET",status="200"}` |
| **Traces** | "Where did the time go in this request?" (per request, sampled) | Bounded by sampling rate | One span per RPC, with parent links |

The ratio in production: **you'll have lots of logs, fewer metric series, very few traces (sampled)**. Wire up all three; don't try to do tracing's job with logs or metrics' job with traces.

## Structured logging

The single biggest observability upgrade. Every log line is a record with **named fields**, not a printf string.

```python
# Bad
log.info(f"user {user_id} failed login from {ip}: {reason}")

# Good
log.info("login_failed", user_id=user_id, ip=ip, reason=reason)
```

Why structured wins:

- **Searchable**: `WHERE event = "login_failed" AND reason = "bad_password"` works. Regex-grepping unstructured logs doesn't scale.
- **Aggregatable**: counts per reason, per IP, per hour — without re-parsing every line.
- **Stable**: changes to the human-readable phrasing don't break dashboards.
- **PII-aware**: it's clearer which fields might contain sensitive data when they're named.

Per language:

- **Python**: `structlog`, `logging` with `extra={...}` and a JSON formatter, or `loguru`.
- **C/C++**: `spdlog` with a JSON sink, or roll a small one.
- **Zig**: `std.log` is unstructured by default; wrap it.
- **Go**: `log/slog` (1.21+) is the modern choice.

## Log levels — what they actually mean

Use them consistently. The standard set:

| Level | Means | Action |
|---|---|---|
| `TRACE` / `DEBUG` | Internal detail, only useful when actively debugging | Off in prod by default |
| `INFO` | Normal events. State transitions, config loaded, request received/completed | On in prod |
| `WARN` | Something unexpected but recoverable. Retried successfully, fell back to default | On in prod, low volume |
| `ERROR` | Operation failed. Caller should see it. Should usually correlate with a metric increment and possibly an alert | On in prod, very low volume — every ERROR should be actionable |
| `FATAL` / `CRITICAL` | Process is exiting. Out-of-memory, can't open primary DB, unhandled panic | Pages someone |

**Anti-pattern: every error logs at WARN to "stay quiet."** That just teaches the team to ignore WARNs. Match the level to the severity.

**Anti-pattern: log + rethrow at every layer.** The exception is caught → logged → rethrown → caught at next layer → logged → rethrown. The same error appears six times in the log. Pick **one** site (typically the boundary that decides whether to retry / surface / give up) and log there.

**Anti-pattern: log + swallow.** Almost always wrong. See `error-handling-strategies` for the test.

## What to log

In every meaningful operation:

- **At entry**: the operation name and the input shape (with PII redacted). `INFO` level usually.
- **On error**: what was attempted, what failed, what context (user, request id, file path).
- **At completion**: outcome and latency for slow operations. Optional — metrics handle "how slow" better.
- **At a state transition**: leader elected, config reloaded, connection pool exhausted, circuit opened.

What **not** to log:

- Every successful trivial operation. The signal-to-noise ratio drops fast.
- Secrets, tokens, passwords, full auth headers. Even "redacted" — strip before logging.
- Full request/response bodies in production. Usually too large; usually contain PII.
- Stack traces at INFO. They go at ERROR or above.

## Correlation IDs

Every request that crosses process boundaries should carry a unique ID. The receiver logs it on every line. Now you can grep one ID and reconstruct the request.

- HTTP: `X-Request-Id` header. Generate at the edge if absent; propagate downstream.
- Internal RPC: in the metadata.
- Async work: pass through the queue message envelope.

Without correlation IDs, multi-service incidents are debugged by timestamp guessing. With them, you grep one string.

## Metrics — types and when to use them

### Counter

Monotonic. Only goes up. "How many?"

`http_requests_total{method, status}` — sum over time = total requests.

Rate-of-change = `rate(metric[5m])` is what you usually graph.

### Gauge

A value at a moment. Goes up and down. "How many right now?"

`active_connections`, `queue_depth`, `cpu_temp_celsius`.

### Histogram

Distribution of values. "How fast were the requests?"

`http_request_duration_seconds_bucket` — pre-aggregated buckets (le=0.005, le=0.01, ..., le=+Inf). Lets you compute percentiles.

For latency, **always** use a histogram, not a gauge or a "average" counter. Averages hide tail latency, which is where most production problems live.

### Summary

Like a histogram but client-side-aggregated. Less flexible, can't aggregate across replicas. Avoid in distributed systems.

## Cardinality discipline

**The rule: metrics labels must have a small, bounded set of values.**

```python
# OK — bounded set
http_requests.inc(method="GET", status="200")

# Disaster — unbounded
http_requests.inc(method="GET", url=request.url)  # unique URL per query string
http_requests.inc(method="GET", user_id=user_id)  # unique per user
```

Each unique combination of label values is a separate time series. Unbounded labels = infinite time series = your metrics backend dies.

**Bounded values**:

- HTTP method (5–10 values)
- HTTP status class (`2xx`, `3xx`, `4xx`, `5xx` — 4 values; not the full status code)
- Endpoint name (~50–500, manageable)
- Region, environment, service name

**Unbounded — don't use as labels**:

- User IDs
- Request URLs (use endpoint name instead)
- Trace IDs
- Timestamps

If you need per-user data: use logs (unlimited cardinality) or a sampled trace, not metrics.

## Tracing

A trace is a tree of *spans*. Each span has a parent, a duration, an operation name, and arbitrary tags.

### Span hygiene

- **Operation name** is the *category* (`http.handler`, `db.query`, `cache.get`), not the specifics. Use tags for specifics.
- **Tags** are `key=value` annotations on the span: `http.method=GET`, `db.table=users`, `cache.hit=false`. Use the OTel semantic conventions when possible.
- **Don't put PII in tags.** Same rule as logs.
- **Don't span everything.** A span for every function call generates noise. Span at meaningful boundaries: RPC entry, RPC exit, DB query, cache call, expensive computation.

### Sampling

Tracing every request is expensive. Standard policies:

- **Probabilistic** (sample 1% of requests): cheap, works for high-volume services, may miss rare errors.
- **Tail-based** (collect all spans, decide after the request whether to keep): catches errors/slowness, more expensive.
- **Head-based**: decide at the entry whether to sample. Standard for OTel.

**Always force-sample errors and slow requests.** Sampling can miss them otherwise.

## OpenTelemetry (OTel) basics

The standard. Vendor-agnostic API, multiple backends (Jaeger, Tempo, Honeycomb, Datadog).

```python
from opentelemetry import trace
tracer = trace.get_tracer(__name__)

with tracer.start_as_current_span("process_order") as span:
    span.set_attribute("order.id", order_id)
    ...
    if failed:
        span.record_exception(exc)
        span.set_status(trace.StatusCode.ERROR)
```

OTel also covers metrics and logs with auto-correlation (a log emitted inside a span gets the trace_id automatically). Worth setting up the SDK once and using all three pillars from one place.

## Logs ↔ metrics ↔ traces

The three pillars work together:

- A **log line** at ERROR level should usually correspond to a **metric increment** (`error_count{type=...}`) so dashboards can count them.
- A **trace span** that errored should also produce a log entry (with the trace_id) so the log search finds it.
- Each request should have a **correlation ID** that appears in all three.

Without these correlations you're triaging in three separate UIs. With them, you start with one and pivot.

## Production readiness checklist

For a service to be production-ready, observability requirements:

1. ✅ Structured logging in JSON or equivalent.
2. ✅ Log level configurable at runtime (env var, signal, admin endpoint).
3. ✅ Request/correlation IDs propagate across process boundaries.
4. ✅ The standard RED metrics (Rate, Errors, Duration) for every endpoint.
5. ✅ Tracing instrumentation on RPC, DB, cache boundaries.
6. ✅ Health endpoint (`/healthz`, `/readyz`) for liveness/readiness.
7. ✅ Graceful shutdown that drains in-flight requests.
8. ✅ Alert on the symptoms (error rate, latency p99) — not the causes.

## Anti-patterns recap

- **Log everything**: noise, signal lost.
- **Log nothing**: blind in production.
- **Log + rethrow at every layer**: same error six times.
- **Log + swallow**: bug hidden.
- **Unbounded label values**: backend dies.
- **Average latency as the metric**: tails invisible.
- **Stack traces at INFO**: noise.
- **PII in logs/metrics/tags**: legal problem and possibly safety problem.
- **Logging behind a feature flag, defaulting off**: instrumentation that's not on isn't instrumentation.

## What to instrument first

If you're adding observability to a service that has none, in this order:

1. **Structured logging** with correlation IDs.
2. **RED metrics** for the public API.
3. **Health/readiness endpoints**.
4. **Database query duration histogram** (the universal slow point).
5. **Tracing** if you have a distributed system.
6. **Custom metrics** for the specific business logic.

Don't try to do all six on day one. Get the structured logs in first; the rest pays back faster once you can search.
