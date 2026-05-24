# Stage 1: Build
FROM golang:1.25-alpine AS builder
WORKDIR /app
COPY go.mod go.sum .
RUN go mod download
COPY . .
RUN CGO_ENABLED=0 go build -ldflags="-s -w" -o reagentx-server .

# Stage 2: Run
FROM alpine:3.21
RUN apk add --no-cache ca-certificates
RUN mkdir -p /data/uploads
WORKDIR /data
COPY --from=builder /app/reagentx-server .
EXPOSE 8081
ENV LISTEN_ADDR=:8081
ENV DB_PATH=/data/reagentx.db
CMD ["./reagentx-server"]
