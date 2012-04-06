require 'rubygems'
require 'rake'
require 'rake/testtask'
require 'rake/rdoctask'
require 'rake/gempackagetask'
require 'spec'
require 'spec/rake/spectask'

desc 'Default: run test.'
task :default => :spec

desc 'Test the ao_locked gem.'
Spec::Rake::SpecTask.new(:spec) do |t|
	t.spec_files = FileList['spec/**/*_spec.rb']
	t.spec_opts = ['-c','-f','nested']
end

desc 'Generate documentation for the ao_locked gem.'
Rake::RDocTask.new(:rdoc) do |rdoc|
  rdoc.rdoc_dir = 'rdoc'
  rdoc.title    = 'ConnectionPool'
  rdoc.options << '--line-numbers' << '--inline-source'
  rdoc.rdoc_files.include('README')
  rdoc.rdoc_files.include('lib/**/*.rb')
end

spec = eval(File.read(File.expand_path("../generic_connection_pool.gemspec", __FILE__)))
Rake::GemPackageTask.new(spec) do |pkg|
  pkg.need_zip = false
  pkg.need_tar = false
end
