# ===============================================
# Stage 1: Build the Elixir/Phoenix application
# ===============================================
FROM elixir:1.19-alpine@sha256:b1fd9f99dfb3f56576646c173ff2e75a3b971172a55f624941cc83eafe5aa8fd AS builder

# Install build dependencies
# ffmpeg is required during asset compilation (mix assets.deploy)
RUN apk add --no-cache \
    build-base \
    git \
    python3 \
    nodejs \
    npm \
    zstd \
    ffmpeg

# Set environment variables
ENV MIX_ENV=prod \
    NODE_ENV=production

# Build version argument (can be overridden at build time)
ARG BUILD_VERSION

WORKDIR /app

# Install hex + rebar
RUN mix local.hex --force && \
    mix local.rebar --force

# Install mix dependencies
# Cache mounts avoid re-downloading deps on every build (host-local cache, not in image)
COPY mix.exs mix.lock ./
RUN --mount=type=cache,target=/root/.hex \
    --mount=type=cache,target=/root/.mix \
    mix deps.get --only prod

# Copy config files and compile deps
COPY config/config.exs config/prod.exs config/runtime.exs config/
RUN mix deps.compile

COPY rel rel
COPY priv priv
COPY assets assets

# Copy all application files
COPY lib lib

# Package source files for Sentry source maps
RUN mix sentry.package_source_code

# Preserve original webmanifest before digesting (browsers need exact filename),
# compile assets, then restore it — all in one layer to avoid intermediate state
RUN if [ -f priv/static/site.webmanifest ]; then \
      cp priv/static/site.webmanifest priv/static/site.webmanifest.orig; \
    fi \
    && mix assets.deploy \
    && if [ -f priv/static/site.webmanifest.orig ]; then \
      mv priv/static/site.webmanifest.orig priv/static/site.webmanifest; \
    fi

# Compile the application with BUILD_VERSION set
# BUILD_VERSION is embedded at compile time in Ysc.BuildVersion module
# If BUILD_VERSION arg is not provided, calculate it from git
RUN BUILD_VERSION=${BUILD_VERSION:-$(git describe --first-parent --abbrev=10 --long --tags --dirty 2>/dev/null || echo "unknown")} \
    mix do compile --warnings-as-errors + release

# ===============================================
# Stage 2: Create the final production image
# ===============================================
FROM alpine:3.22@sha256:55ae5d250caebc548793f321534bc6a8ef1d116f334f18f4ada1b2daad3251b2 AS app

# Install runtime dependencies (chromium + fonts for ChromicPDF / TV poster capture)
RUN apk add --no-cache \
    libstdc++ \
    openssl \
    ncurses-libs \
    ca-certificates \
    tini \
    imagemagick \
    chromium \
    nss \
    freetype \
    harfbuzz \
    ttf-freefont

# Create non-root user and working directory in one layer
RUN adduser -D app && mkdir -p /app && chown app /app

WORKDIR /app

# Copy the release from the builder stage (rel/ is build config only; the compiled
# release in _build/prod/rel/ysc already has everything baked in)
COPY --from=builder --chown=app:app /app/_build/prod/rel/ysc ./
COPY --from=builder --chown=app:app /app/priv/static ./priv/static

# Ensure bin scripts have execute permissions
RUN chmod +x bin/* 2>/dev/null || true

# Set environment variables
ENV PORT=4000 \
    LANG=C.UTF-8 \
    LANGUAGE=en_US:en \
    LC_ALL=en_US.UTF-8 \
    PHX_SERVER=true

# Use the non-root user
USER app

EXPOSE 4000

ENTRYPOINT ["/sbin/tini", "-s", "--"]
CMD ["/app/bin/server", "start"]
