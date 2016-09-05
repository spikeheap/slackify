class Login < Sequel::Model
  many_to_one :account
  one_to_many :collectors
end