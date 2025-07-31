require 'yaml'
require 'erb'
require 'active_record'
require 'dotenv/load'

db_config = YAML.load(ERB.new(File.read('db/config.yml')).result)
ActiveRecord::Base.establish_connection(db_config['development'])