FROM alpine:3.4
MAINTAINER Kontena, Inc. <info@kontena.io>

ENV RUBY_GC_HEAP_GROWTH_FACTOR=1.1
ENV RUBY_GC_MALLOC_LIMIT=4000100
ENV RUBY_GC_MALLOC_LIMIT_MAX=16000100
ENV RUBY_GC_MALLOC_LIMIT_GROWTH_FACTOR=1.1
ENV RUBY_GC_MALLOC_LIMIT=16000100
ENV RUBY_GC_OLDMALLOC_LIMIT_MAX=16000100

RUN apk update && apk --update add ruby ruby-irb ruby-bigdecimal \
    ruby-io-console ruby-json ca-certificates libssl1.0 openssl libstdc++

ADD Gemfile /app/
ADD Gemfile.lock /app/

RUN apk --update add --virtual build-dependencies ruby-dev build-base openssl-dev && \
    gem install bundler --no-ri --no-rdoc && \
    cd /app ; bundle install --without development test && \
    apk del build-dependencies

WORKDIR /app
ADD . /app

CMD ["bundle", "exec", "thin", "-C", "app/config/thin.yml", "start"]
