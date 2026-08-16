ARG BUILD_FROM
FROM ${BUILD_FROM}

ENV LANG=C.UTF-8
ENV EUFY_DIR=/opt/eufy

# Node und Buildwerkzeuge fuer die nativen Abhaengigkeiten
RUN apk add --no-cache nodejs npm \
    && apk add --no-cache --virtual .build-deps python3 make g++ \
    && mkdir -p "${EUFY_DIR}" \
    && cd "${EUFY_DIR}" \
    && npm install --omit=dev eufy-security-ws@latest \
    && npm cache clean --force \
    && apk del .build-deps \
    && ls -l "${EUFY_DIR}/node_modules/eufy-security-ws/dist/bin/server.js"

COPY rootfs /
RUN chmod a+x /run.sh

CMD [ "/run.sh" ]
