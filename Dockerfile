FROM amd64/alpine:3.16

ENV TOOL="/tool"

COPY ./wrapper.sh /wrapper.sh
COPY ./tool ${TOOL}

RUN apk add --update --no-cache curl ca-certificates bash jq openjdk11 libreoffice && \
    adduser -D -g cgi cgi && \
    chown -R cgi:cgi ${TOOL} && \
    chmod +x -R ${TOOL} && \
    chmod +x /wrapper.sh

USER cgi

ENTRYPOINT /wrapper.sh
