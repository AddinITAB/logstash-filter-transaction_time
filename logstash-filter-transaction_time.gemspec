Gem::Specification.new do |s|
  s.name          = 'logstash-filter-transaction_time'
  s.version       = '1.0.7'
  s.licenses      = ['Apache-2.0','Apache License (2.0)']
  s.summary       = 'Writes the time difference between two events in a transaction to a new event'
  s.description   = 'This gem is a Logstash plugin required to be installed on top of the Logstash core pipeline using $LS_HOME/bin/logstash-plugin install gemname. This gem is not a stand-alone program. Source-code and documentation available at github: https://github.com/AddinITAB/logstash-filter-transaction_time'
  s.homepage      = 'http://addinit.se/'
  s.authors       = ['Tommy Welleby']
  s.email         = 'tommy.welleby@addinit.se'
  s.require_paths = ['lib']

  # Files
  s.files = Dir['lib/**/*','spec/**/*','vendor/**/*','*.gemspec','*.md','CONTRIBUTORS','Gemfile','LICENSE','NOTICE.TXT']
   # Tests
  s.test_files = s.files.grep(%r{^(test|spec|features)/})

  # Special flag to let us know this is actually a logstash plugin
  s.metadata = { "logstash_plugin" => "true", "logstash_group" => "filter" }

  # Gem dependencies
  s.add_runtime_dependency "logstash-core-plugin-api", "~> 2.0"
  s.add_development_dependency 'logstash-devutils'
end
