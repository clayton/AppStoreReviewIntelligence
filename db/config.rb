require 'yaml'
require 'erb'

db_config = YAML.load(ERB.new(File.read('db/config.yml')).result)