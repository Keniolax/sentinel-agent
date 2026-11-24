# The Sentinel Agent image: the agent, the mock orders API, Ollama 0.40.13 and one pinned model.
# Built for linux/amd64 in CI. Both stages use the same Python base, pinned by digest.

FROM python:3.12-slim-bookworm@sha256:44cf1793efa7c7a476bb0f2cff81443f4a072c90c1cb127e2924933daa3e8c64 AS model
ARG MODEL=qwen2.5:1.5b
ARG MODEL_DIGEST=65ec06548149b04c096a120e4a6da9d4017ea809c91734ea5631e89f96ddc57b
RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates curl zstd \
    && rm -rf /var/lib/apt/lists/*
COPY image/install-ollama.sh /tmp/install-ollama.sh
RUN OLLAMA_HOME_DIR=/opt/ollama OLLAMA_TARBALL=/tmp/ollama.tar.zst sh /tmp/install-ollama.sh
# Pull the model once at build time and refuse to continue unless its registry digest
# matches the pin, so every task runs the same weights.
ENV OLLAMA_MODELS=/opt/models
RUN /opt/ollama/bin/ollama serve >/tmp/serve.log 2>&1 & \
    for i in $(seq 1 30); do curl -fsS http://127.0.0.1:11434/api/version >/dev/null && break; sleep 1; done; \
    ok=; for attempt in 1 2 3 4 5; do /opt/ollama/bin/ollama pull "$MODEL" && ok=1 && break; sleep $((attempt * 15)); done; \
    test -n "$ok" \
    && got=$(curl -fsS http://127.0.0.1:11434/api/tags | python3 -c "import json,sys; print([m['digest'] for m in json.load(sys.stdin)['models'] if m['name']=='$MODEL'][0])") \
    && echo "$MODEL digest $got" && test "$got" = "$MODEL_DIGEST"

FROM python:3.12-slim-bookworm@sha256:44cf1793efa7c7a476bb0f2cff81443f4a072c90c1cb127e2924933daa3e8c64
RUN apt-get update && apt-get upgrade -y && rm -rf /var/lib/apt/lists/* \
    && useradd --uid 10001 --no-create-home --home-dir /tmp --shell /usr/sbin/nologin agent
COPY requirements.lock /tmp/requirements.lock
RUN pip install --no-cache-dir --require-hashes -r /tmp/requirements.lock && rm /tmp/requirements.lock
COPY --from=model /opt/ollama /opt/ollama
COPY --from=model /opt/models /opt/models
COPY app/sentinel /app/sentinel
COPY image/entrypoint.sh /entrypoint.sh
ENV PYTHONPATH=/app OLLAMA_MODELS=/opt/models OLLAMA_HOST=127.0.0.1:11434 HOME=/tmp \
    PYTHONDONTWRITEBYTECODE=1 MODEL=qwen2.5:1.5b
USER 10001
ENTRYPOINT ["/entrypoint.sh"]
CMD ["ask"]
