ARG BUILD_FROM
FROM ${BUILD_FROM}

ENV LANG=C.UTF-8

# Node und Buildwerkzeuge fuer die nativen Abhaengigkeiten
RUN apk add --no-cache nodejs npm \
    && apk add --no-cache --virtual .build-deps python3 make g++ \
    && npm install -g --omit=dev eufy-security-ws@latest \
    && npm cache clean --force \
    && apk del .build-deps

COPY rootfs /
RUN chmod a+x /run.sh

CMD [ "/run.sh" ]
