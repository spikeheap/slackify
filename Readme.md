## To do
- [x] protect all management pages with OAuth & session cookie
- [x] Use a consistent secret, so it doesn't need authenticating over and over again.
- [ ] 'remove' button for collectors
- [ ] playlist URI support
- [ ] improve in-page description/docs
- [ ] add bootstrap
- [ ] Input error handling ;)
- [ ] Refactor out of single class
- [ ] Add some tests
- [ ] Review TODOs
- [ ] Blog post
- [ ] Twitter announcement
- [ ] add Slack OAuth
- [ ] create Slack integration automagically.

### Developing/running in Docker

Add a `.env` using the following template (insert your credentials):

```
# Spotify credentials
SPOTIFY_CLIENT_ID=
SPOTIFY_CLIENT_SECRET=

# Docker DB credentials
POSTGRES_HOST=db
POSTGRES_DB=slackify
POSTGRES_USER=slackify
POSTGRES_PASSWORD=

# For secure Rack cookies
SESSION_SECRET=
```

Then run 

```
docker-compose build
docker-compose up
```

# Deploying to Heroku

First, head to Spotify and [create an application](https://developer.spotify.com/my-applications/#!/applications) to get your `SPOTIFY_CLIENT_ID` and `SPOTIFY_CLIENT_SECRET` environment variables.

Then:

[![Deploy](https://www.herokucdn.com/deploy/button.svg)](https://heroku.com/deploy)