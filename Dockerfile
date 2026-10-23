# Build stage
FROM golang:1.22-alpine AS build
WORKDIR /src

COPY go.mod ./
RUN go mod download

COPY main.go ./
COPY internal ./internal
RUN CGO_ENABLED=0 GOOS=linux go build -trimpath -ldflags="-s -w" -o /out/event-service .

# Runtime stage
FROM gcr.io/distroless/static-debian12:nonroot
COPY --from=build /out/event-service /event-service

ENV PORT=8080 \
    ENV=dev \
    PROCESSING_DELAY_MS=1000

EXPOSE 8080
USER nonroot:nonroot
ENTRYPOINT ["/event-service"]
