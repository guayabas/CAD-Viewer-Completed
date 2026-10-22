# syntax=docker/dockerfile:1
# check=error=true

# One image with everything the deployed app needs: the Rails API (web/), the C++ tessellator
# (tessellator/), the connected viewer (viewer/, served by Rails at "/"), and the NIST sample
# used by db/seeds.rb. Build from the repo root:
#
#   docker build -t cad-viewer .
#   docker run --rm -p 3000:3000 -e RAILS_MASTER_KEY=$(cat web/config/master.key) \
#     -e DATABASE_URL=postgres://... -e ACTIVE_STORAGE_SERVICE=local -e FORCE_SSL=false cad-viewer
#
# Every stage starts FROM base, so the tessellator is compiled against the same Debian and the
# same OCCT the final image runs. Debian bookworm ships OCCT 7.6.3, like the Ubuntu 24.04 used
# in development (newer Debian ships 7.8, whose glTF writer API differs).

ARG RUBY_VERSION=3.4.11
FROM docker.io/library/ruby:${RUBY_VERSION}-slim-bookworm AS base

WORKDIR /rails

# Packages every stage needs at run time (jemalloc: lower memory use for Ruby).
RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y curl libjemalloc2 postgresql-client && \
    ln -s /usr/lib/$(uname -m)-linux-gnu/libjemalloc.so.2 /usr/local/lib/libjemalloc.so && \
    rm -rf /var/lib/apt/lists /var/cache/apt/archives

ENV RAILS_ENV="production" \
    BUNDLE_DEPLOYMENT="1" \
    BUNDLE_PATH="/usr/local/bundle" \
    BUNDLE_WITHOUT="development" \
    LD_PRELOAD="/usr/local/lib/libjemalloc.so"


# --- Stage 1: compile the tessellator ---------------------------------------------------------
FROM base AS tessellator

# OCCT's CMake config checks every OCCT toolkit, so all -dev packages are needed (and TBB,
# which Debian's OCCT is built with). This stage is thrown away, so its size doesn't matter.
RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y build-essential cmake \
      libocct-foundation-dev libocct-modeling-data-dev libocct-modeling-algorithms-dev \
      libocct-ocaf-dev libocct-data-exchange-dev libocct-visualization-dev libocct-draw-dev \
      occt-misc libtbb-dev && \
    rm -rf /var/lib/apt/lists /var/cache/apt/archives

COPY tessellator/ /src/tessellator/
RUN cmake -S /src/tessellator -B /src/build -DCMAKE_BUILD_TYPE=Release && \
    cmake --build /src/build -j "$(nproc)" && \
    /src/build/tessellator --help


# --- Stage 2: gems, Rails assets, and the viewer ------------------------------------------------
FROM base AS build

RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y build-essential git libpq-dev libyaml-dev pkg-config && \
    rm -rf /var/lib/apt/lists /var/cache/apt/archives

# Node: for Rails' jsbundling (esbuild) and for building the viewer (Vite).
ARG NODE_VERSION=24.22.1
ARG YARN_VERSION=1.22.22
ENV PATH=/usr/local/node/bin:$PATH
RUN curl -sL https://github.com/nodenv/node-build/archive/master.tar.gz | tar xz -C /tmp/ && \
    /tmp/node-build-master/bin/node-build "${NODE_VERSION}" /usr/local/node && \
    npm install -g yarn@$YARN_VERSION && \
    rm -rf /tmp/node-build-master

# Gems first, so this layer is cached until Gemfile.lock changes.
COPY web/Gemfile web/Gemfile.lock ./
COPY web/vendor/ ./vendor/
RUN bundle install && \
    rm -rf ~/.bundle/ "${BUNDLE_PATH}"/ruby/*/cache "${BUNDLE_PATH}"/ruby/*/bundler/gems/*/.git && \
    bundle exec bootsnap precompile -j 1 --gemfile

COPY web/package.json web/yarn.lock ./
RUN yarn install --frozen-lockfile

# The viewer, in connected mode on the same origin as the API (VITE_API_URL=/).
# index.html goes to web/viewer/ (served by ViewerController, no-cache); the hashed JS/CSS and
# the public files go to web/public/ (served by Rails with a long cache).
COPY viewer/package.json viewer/package-lock.json /viewer/
RUN cd /viewer && npm ci --no-audit --no-fund
COPY viewer/ /viewer/
RUN cd /viewer && VITE_API_URL=/ npm run build -- --assetsDir viewer-assets

COPY web/ ./
RUN mkdir -p viewer && \
    mv /viewer/dist/index.html viewer/index.html && \
    cp -r /viewer/dist/. public/ && \
    rm -rf /viewer

RUN bundle exec bootsnap precompile -j 1 app/ lib/
# Precompile assets without the real RAILS_MASTER_KEY.
RUN SECRET_KEY_BASE_DUMMY=1 ./bin/rails assets:precompile && rm -rf node_modules


# --- Final image ---------------------------------------------------------------------------------
FROM base

# OCCT runtime libraries only (they pull in TBB, FreeImage, etc. as dependencies).
RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y \
      libocct-foundation-7.6 libocct-modeling-data-7.6 libocct-modeling-algorithms-7.6 \
      libocct-ocaf-7.6 libocct-data-exchange-7.6 libocct-visualization-7.6 && \
    rm -rf /var/lib/apt/lists /var/cache/apt/archives

# Run as a non-root user.
RUN groupadd --system --gid 1000 rails && \
    useradd rails --uid 1000 --gid 1000 --create-home --shell /bin/bash
USER 1000:1000

COPY --from=tessellator /src/build/tessellator /usr/local/bin/tessellator
COPY --chown=rails:rails --from=build "${BUNDLE_PATH}" "${BUNDLE_PATH}"
COPY --chown=rails:rails --from=build /rails /rails
# db/seeds.rb reads Rails.root/../samples, i.e. /samples.
COPY --chown=rails:rails samples/nist_ctc_01_asme1_ap242-e1.stp /samples/

# Fail the build now, not at the first upload, if an OCCT library is missing.
RUN tessellator --help > /dev/null

ENV TESSELLATOR_BIN=/usr/local/bin/tessellator \
    SOLID_QUEUE_IN_PUMA=true \
    PORT=3000

# Prepares the database (migrate, seed) before starting the server.
ENTRYPOINT ["/rails/bin/docker-entrypoint"]

# Render sets PORT; config/puma.rb listens on it.
EXPOSE 3000
CMD ["./bin/rails", "server"]
