# syntax=docker/dockerfile:1

########################  builder  ########################
FROM debian:bookworm AS builder

ARG WFB_NG_REF=2631e0d26fe070341cc945c3d12c85d24ed2e007
ARG FPVD_REF=98c73b7dc0bd73bdc1f2d067a9569746bbd6beae

RUN apt-get update && apt-get install -y --no-install-recommends \
        git ca-certificates build-essential g++ make \
        python3 python3-venv python3-pip \
        libpcap-dev libsodium-dev libevent-dev \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /src

# wfb-ng binaries. Keep .git so the Makefile's version.py step resolves a
# version; make all_bin builds wfb_rx wfb_tx wfb_keygen wfb_tx_cmd wfb_tun.
RUN git clone https://github.com/gilankpam/wfb-ng.git wfb-ng \
    && git -C wfb-ng checkout "${WFB_NG_REF}"
RUN make -C wfb-ng all_bin

# fpvd wheel. fpvdgs is pure stdlib, so --no-deps yields a complete wheel.
RUN git clone https://github.com/gilankpam/fpvd.git fpvd \
    && git -C fpvd checkout "${FPVD_REF}"
RUN python3 -m venv /opt/venv \
    && /opt/venv/bin/pip install --no-cache-dir --upgrade pip setuptools wheel \
    && /opt/venv/bin/pip wheel --no-deps --no-cache-dir -w /wheels ./fpvd/gs

########################  runtime  ########################
FROM debian:bookworm-slim AS runtime

RUN apt-get update && apt-get install -y --no-install-recommends \
        python3 python3-venv \
        openssh-client iproute2 \
        libpcap0.8 libsodium23 libevent-2.1-7 libevent-pthreads-2.1-7 \
    && rm -rf /var/lib/apt/lists/*

# wfb binaries must live in /usr/bin (graph.WFB_BIN_DIR is hard-coded).
COPY --from=builder /src/wfb-ng/wfb_rx     /usr/bin/wfb_rx
COPY --from=builder /src/wfb-ng/wfb_tx     /usr/bin/wfb_tx
COPY --from=builder /src/wfb-ng/wfb_tun    /usr/bin/wfb_tun
COPY --from=builder /src/wfb-ng/wfb_tx_cmd /usr/bin/wfb_tx_cmd
COPY --from=builder /src/wfb-ng/wfb_keygen /usr/bin/wfb_keygen

# fpvd venv (fpvd + fpvd-stats console scripts).
COPY --from=builder /opt/venv /opt/venv
COPY --from=builder /wheels /wheels
RUN /opt/venv/bin/pip install --no-cache-dir --no-index --find-links /wheels fpvdgs \
    && rm -rf /wheels
ENV PATH="/opt/venv/bin:${PATH}"

EXPOSE 8080/tcp 5600/udp
ENTRYPOINT ["fpvd", "--config", "/etc/fpvd/config.json", "--port", "8080"]
