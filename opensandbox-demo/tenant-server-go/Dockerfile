FROM gcr.io/distroless/static-debian12:nonroot
COPY tenant-server-linux-amd64 /tenant-server
USER nonroot:nonroot
ENTRYPOINT ["/tenant-server"]
