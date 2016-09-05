## To do
- ORM
- protect all management pages with OAuth

- one user account has one spotify account and one slack account
- user logs in with spotify or slack credentials
- list of all connections for that user

accounts
  - email

logins
  - provider
  - token
  - refresh_token
  - expires_at
  - expires (boolean)

connections
  - validation_token
  - spotify_login_id
  - playlist_owner_id
  - playlist_id # must belong to login owner.


### Installation

Add a `.env` with your credentials:

```
# Slack credentials
SLACK_TOKEN=

# Spotify credentials
SPOTIFY_CLIENT_ID=
SPOTIFY_CLIENT_SECRET=

# Playlist
SPOTIFY_PLAYLIST_USER=
SPOTIFY_PLAYLIST_ID=

```