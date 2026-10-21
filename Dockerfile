# syntax = docker/dockerfile:1

# Production image for the Upright host app.
# HTTP probes only by default. Browser probes need:
#   docker build --build-arg INSTALL_PLAYWRIGHT=1 -t upright .
ARG RUBY_VERSION=3.4.11
FROM docker.io/library/ruby:$RUBY_VERSION-slim AS base

WORKDIR /rails

# Runtime packages for HTTP / traceroute probes. Node and Chromium stay out
# of this layer so the HTTP-only image stays a few hundred MB.
RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y curl libjemalloc2 sqlite3 iputils-ping mtr-tiny && \
    rm -rf /var/lib/apt/lists /var/cache/apt/archives

ENV RAILS_ENV="production" \
    BUNDLE_DEPLOYMENT="1" \
    BUNDLE_PATH="/usr/local/bundle" \
    BUNDLE_WITHOUT="development:test"

FROM base AS build

RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y build-essential git pkg-config libssl-dev libyaml-dev rustc cargo libclang-dev && \
    rm -rf /var/lib/apt/lists /var/cache/apt/archives

COPY Gemfile Gemfile.lock ./
RUN --mount=type=secret,id=GITHUB_TOKEN,required=false \
    TOKEN="$(cat /run/secrets/GITHUB_TOKEN 2>/dev/null || true)" && \
    if [ -n "$TOKEN" ]; then export BUNDLE_GITHUB__COM="${TOKEN}:x-oauth-basic"; fi && \
    bundle install && \
    rm -rf ~/.bundle/ "${BUNDLE_PATH}"/ruby/*/cache "${BUNDLE_PATH}"/ruby/*/bundler/gems/*/.git && \
    bundle exec bootsnap precompile --gemfile && \
    bundle exec ruby -e "require 'upright/version'; puts Upright::PLAYWRIGHT_VERSION" > /tmp/playwright_version

COPY . .

RUN bundle exec bootsnap precompile app.rb probes/

# These values exist only for this build step. The running container still
# requires the real UPRIGHT_HOSTNAME and PROMETHEUS_OTLP_TOKEN.
RUN SECRET_KEY_BASE_DUMMY=1 \
    UPRIGHT_HOSTNAME=build.local \
    PROMETHEUS_OTLP_TOKEN=build \
    ./bin/rails assets:precompile && \
    rm -rf tmp/cache tmp/pids tmp/sockets log/*

FROM base

# Re-declare: ARG before the first FROM is not visible in later stages.
ARG INSTALL_PLAYWRIGHT=0

COPY --from=build /tmp/playwright_version /tmp/playwright_version
ENV PLAYWRIGHT_BROWSERS_PATH=/ms-playwright

# Chromium + Node is ~1.3G. Keep it off until DATEV browser probes (#902).
RUN if [ "$INSTALL_PLAYWRIGHT" = "1" ]; then \
      apt-get update -qq && \
      apt-get install --no-install-recommends -y nodejs npm && \
      PLAYWRIGHT_VERSION=$(cat /tmp/playwright_version) && \
      npm install -g "playwright@~${PLAYWRIGHT_VERSION}.0" && \
      playwright install --with-deps chromium && \
      npm cache clean --force && \
      rm -rf /var/lib/apt/lists /var/cache/apt/archives /root/.npm && \
      chmod -R o+rx /ms-playwright; \
    fi

COPY --from=build --chown=1000:1000 "${BUNDLE_PATH}" "${BUNDLE_PATH}"
COPY --from=build --chown=1000:1000 /rails /rails

RUN groupadd --system --gid 1000 rails && \
    useradd rails --uid 1000 --gid 1000 --create-home --shell /bin/bash && \
    mkdir -p storage tmp && \
    chown rails:rails storage tmp
USER 1000:1000

ENTRYPOINT ["/rails/bin/docker-entrypoint"]

EXPOSE 3000 9394
CMD ["./bin/rails", "server"]
