FROM ruby:3.4.5
WORKDIR /dtext

RUN <<EOS
  apt-get update
  apt-get install ragel=6.10-4
EOS

COPY --link dtext_rb.gemspec lib/dtext/version.rb Gemfile Gemfile.lock .
COPY --link lib/dtext/version.rb lib/dtext/version.rb
RUN bundle install

COPY . .
RUN bin/rake compile

CMD bash
