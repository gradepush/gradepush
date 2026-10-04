FROM postgres:18.6-bookworm@sha256:3725f4e2499eef5134592b3b4ab79a543ed7f8e533b05b5b637af926630f6650

# TODO: return to the official image when its PCRE2 package includes the Debian
# fix for CVE-2026-103111 and both architectures pass the image security checks.
RUN apt-get update \
    && apt-get install -y --no-install-recommends --only-upgrade libpcre2-8-0=10.42-1+deb12u2 \
    && rm -rf /var/lib/apt/lists/*
