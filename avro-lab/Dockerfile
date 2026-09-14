# syntax=docker/dockerfile:1
# check=error=true

ARG RUBY_VERSION=4.0.5

# Production image for the Avro Lab experiment (part of the ddia-labs monorepo).
# Build: docker build -t ddia-labs ./avro-lab
# No database, no jobs: a pure request/response Rails app plus a Go encoder
# sidecar process that the /go ingress route targets directly. Runs as non-root
# UID 1000; Rails listens on PORT (default 3000, cluster sets 8080) and the Go
# sidecar on 0.0.0.0:8081.

# Go encoder build stage: vet + test + static binary (no CGO).
FROM docker.io/library/golang:1.25-alpine AS gobuild
WORKDIR /build/go
COPY go/go.mod go/go.sum ./
RUN go mod download
COPY go/ ./
RUN go vet ./... && \
    go test ./... && \
    CGO_ENABLED=0 GOOS=linux go build -trimpath -ldflags="-s -w" -o /out/goavro-lab .

FROM docker.io/library/ruby:$RUBY_VERSION-slim AS base

# Rails app lives here
WORKDIR /rails

# Install base packages
RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y curl libjemalloc2 && \
    ln -s /usr/lib/$(uname -m)-linux-gnu/libjemalloc.so.2 /usr/local/lib/libjemalloc.so && \
    rm -rf /var/lib/apt/lists /var/cache/apt/archives

# Set production environment variables and enable jemalloc for reduced memory usage and latency.
ENV RAILS_ENV="production" \
    BUNDLE_DEPLOYMENT="1" \
    BUNDLE_PATH="/usr/local/bundle" \
    BUNDLE_WITHOUT="development:test" \
    LD_PRELOAD="/usr/local/lib/libjemalloc.so"

# Throw-away build stage to reduce size of final image
FROM base AS build

# Install packages needed to build gems
RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y build-essential git libyaml-dev pkg-config && \
    rm -rf /var/lib/apt/lists /var/cache/apt/archives

# Install application gems
COPY vendor/* ./vendor/
COPY Gemfile Gemfile.lock ./

RUN bundle install && \
    rm -rf ~/.bundle/ "${BUNDLE_PATH}"/ruby/*/cache "${BUNDLE_PATH}"/ruby/*/bundler/gems/*/.git && \
    # -j 1 disable parallel compilation to avoid a QEMU bug: https://github.com/rails/bootsnap/issues/495
    bundle exec bootsnap precompile -j 1 --gemfile

# Copy application code
COPY . .

# Precompile bootsnap cache for faster boot; assets without requiring runtime secrets.
RUN bundle exec bootsnap precompile -j 1 app/ lib/ && \
    SECRET_KEY_BASE_DUMMY=1 ./bin/rails assets:precompile

# Final stage for app image
FROM base

# Run and own only the runtime files as a non-root user for security
RUN groupadd --system --gid 1000 rails && \
    useradd rails --uid 1000 --gid 1000 --create-home --shell /bin/bash
USER 1000:1000

# Copy built artifacts: gems, application
COPY --chown=rails:rails --from=build "${BUNDLE_PATH}" "${BUNDLE_PATH}"
COPY --chown=rails:rails --from=build /rails /rails

# Copy the static Go encoder binary from the go build stage.
COPY --chown=rails:rails --from=gobuild /out/goavro-lab /rails/bin/goavro-lab

# Start the Go sidecar, wait for it, then the Rails server (see bin/start).
EXPOSE 8080
CMD ["bin/start"]