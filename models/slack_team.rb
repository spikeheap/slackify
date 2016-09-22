class SlackTeam < Sequel::Model
  one_to_one :login
end