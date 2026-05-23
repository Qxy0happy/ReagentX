FROM golang:1.25-alpine AS builder

WORKDIR /build
COPY backend/go.mod backend/go.sum ./
RUN go mod download

COPY backend/ ./
RUN CGO_ENABLED=0 go build -ldflags="-s -w" -o reagent-x-server .

FROM alpine:3.21

RUN apk add --no-cache ca-certificates tzdata
WORKDIR /app
COPY --from=builder /build/reagent-x-server .

EXPOSE 8080
VOLUME ["/app/data", "/app/uploads"]

ENV DB_PATH=/app/data/reagent-x.db
ENV GIN_MODE=release

CMD ["./reagent-x-server"]
