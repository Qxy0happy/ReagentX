FROM golang:1.25-alpine AS builder

WORKDIR /build
COPY backend/go.mod backend/go.sum ./
RUN go mod download

COPY backend/ ./
RUN CGO_ENABLED=0 go build -ldflags="-s -w" -o ReagentX-server .

FROM alpine:3.21

RUN apk add --no-cache ca-certificates tzdata
WORKDIR /app
COPY --from=builder /build/ReagentX-server .

EXPOSE 8080
VOLUME ["/app/data", "/app/uploads"]

ENV DB_PATH=/app/data/ReagentX.db
ENV GIN_MODE=release

CMD ["./ReagentX-server"]
