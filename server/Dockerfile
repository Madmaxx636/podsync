# syntax=docker/dockerfile:1

# ---- build: a static binary, no C compiler needed (the SQLite driver is pure Go) ----
ARG GO_VERSION=1.26
FROM golang:${GO_VERSION}-alpine AS build
WORKDIR /src
COPY go.mod go.sum ./
RUN go mod download
COPY *.go ./
ARG VERSION=dev
RUN CGO_ENABLED=0 go build -trimpath -ldflags "-s -w -X main.version=${VERSION}" -o /out/podsync-server .

# ---- run ----
FROM alpine:3.22
# A fixed non-root user owns the data folder, so a named volume starts out writable.
RUN adduser -D -u 10001 podsync && mkdir /data && chown podsync /data
COPY --from=build /out/podsync-server /usr/local/bin/podsync-server
USER podsync
ENV PODSYNC_ADDR=:8080 \
    PODSYNC_DB=/data/podsync.db
VOLUME /data
EXPOSE 8080
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD ["podsync-server", "healthcheck"]
ENTRYPOINT ["podsync-server"]
CMD ["serve"]
