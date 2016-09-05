FROM ruby:2.3.1
RUN apt-get update -qq && apt-get install -y build-essential libpq-dev nodejs

ENV APP_DIR=/app

RUN mkdir $APP_DIR
WORKDIR $APP_DIR

ADD Gemfile Gemfile
ADD Gemfile.lock Gemfile.lock
RUN bundle install

ADD . $APP_DIR