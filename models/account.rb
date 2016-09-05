class Account < Sequel::Model
  one_to_many :collectors
  one_to_many :logins
end