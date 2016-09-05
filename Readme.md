## To do
- protect all management pages with OAuth & session cookie
- add bootstrap
- add Slack OAuth
- create Slack integration automagically.
- Input error handling ;)
- Use a consistent secret, so it doesn't need authenticating over and over again.

### Installation

Add a `.env` with your credentials:

```
# Spotify credentials
SPOTIFY_CLIENT_ID=
SPOTIFY_CLIENT_SECRET=

# Docker DB credentials
POSTGRES_HOST=
POSTGRES_DB=
POSTGRES_USER=
POSTGRES_PASSWORD=

# For secure Rack cookies
SESSION_SECRET=
```

# Deploying to Heroku

First, head to Spotify and [create an application](https://developer.spotify.com/my-applications/#!/applications) to get your `SPOTIFY_CLIENT_ID` and `SPOTIFY_CLIENT_SECRET` environment variables.
```
heroku create
heroku addons:create heroku-postgresql:hobby-dev
```

Or just use this button:

[![Deploy](https://www.herokucdn.com/deploy/button.svg)](https://heroku.com/deploy)