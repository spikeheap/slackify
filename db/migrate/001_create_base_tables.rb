  Sequel.migration do
    change do
      create_table :accounts do
        primary_key :id
        String      :display_name
        String      :email
        String      :spotify_id
        DateTime   :created_at, :null => false
        DateTime   :updated_at, :null => false
      end

      create_table :logins do
        primary_key :id
        foreign_key :account_id, :accounts
        String      :provider
        String      :token
        String      :refresh_token
        DateTime    :expires_at
        Boolean     :expires
        DateTime   :created_at, :null => false
        DateTime   :updated_at, :null => false
      end

      create_table :collectors do
        primary_key :id
        foreign_key :account_id, :accounts
        foreign_key :login_id, :logins
        String      :playlist_name
        String      :validation_token
        String      :playlist_owner_spotify_id
        String      :playlist_spotify_id
        DateTime   :created_at
        DateTime   :updated_at
      end
    end
  end