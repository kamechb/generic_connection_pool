require File.expand_path('../lib/connection_pool', __FILE__)
require 'rake/gempackagetask'


Gem::Specification.new do |s|

  #### Basic information.

  s.name = 'generic_connection_pool'
  s.version = ConnectionPool::VERSION
  s.summary = <<-EOF
    Always network clients require a connection pool, like database connection, cache connection and others.
Generic connection pool can be used with anything. It is inspired from ActiveRecord ConnectionPool.
Sharing a limited number of network connections among many threads.
Connections are created delayed.
  EOF
  s.description = <<-EOF
    Always network clients require a connection pool, like database connection, cache connection and others.
Generic connection pool can be used with anything. It is inspired from ActiveRecord ConnectionPool.
Sharing a limited number of network connections among many threads.
Connections are created delayed.
  EOF

  #### Which files are to be included in this gem?  Everything!  (Except CVS directories.)

  s.files = FileList[
      "lib/**/*", "spec/**/*", "Rakefile", "README", "Gemfile", "LICENSE"
  ]

  #### Load-time details: library and application (you will need one or both).

  s.require_path = 'lib'

  s.add_runtime_dependency('activesupport')
  s.add_development_dependency('rspec')

  #### Author and project details.

  s.authors = ["kame"]
  s.email = ["kamechb@gmail.com"]
end
