ARG BUILD_FROM
FROM ${BUILD_FROM}

ENV LANG=C.UTF-8
ENV EUFY_DIR=/opt/eufy

# Node und Buildwerkzeuge fuer die nativen Abhaengigkeiten
RUN apk add --no-cache nodejs npm jq \
    && apk add --no-cache --virtual .build-deps python3 make g++ \
    && mkdir -p "${EUFY_DIR}" \
    && cd "${EUFY_DIR}" \
    && npm install --omit=dev eufy-security-ws@latest \
    && npm cache clean --force \
    && apk del .build-deps \
    && ls -l "${EUFY_DIR}/node_modules/eufy-security-ws/dist/bin/server.js"

# Neue Kameramodelle nachruesten, die eufy-security-client noch nicht kennt.
# Laeuft nach der Installation, damit der Patch bei jedem Neubau frisch
# angewandt wird.
COPY patch-devices.js /opt/patch-devices.js
RUN node /opt/patch-devices.js \
    "${EUFY_DIR}/node_modules/eufy-security-ws/node_modules/eufy-security-client" \
    || node /opt/patch-devices.js \
    "${EUFY_DIR}/node_modules/eufy-security-client"

COPY rootfs /
RUN chmod a+x /run.sh

CMD [ "/run.sh" ]
