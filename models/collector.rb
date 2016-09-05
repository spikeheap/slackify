class Collector < Sequel::Model
  many_to_one :account
  many_to_one :login
end