Sequel.migration do
  change do

    alter_table :logins do
      add_column :display_name, String
      set_column_default :expires, false
    end

    create_table :slack_teams do
      primary_key :id
      foreign_key :login_id, :logins
      String      :name
      DateTime   :created_at, :null => false
      DateTime   :updated_at, :null => false
    end

  end
end