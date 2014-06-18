#!/usr/bin/env ruby

require 'erb'
require 'find'
require 'git'
require 'yaml'
require 'optparse'

MODULE_FILES_DIR = 'moduleroot/'

# Assume this directory is at the same level as module directories
PROJ_ROOT = File.expand_path(File.join(File.dirname(__FILE__), '..'))

class ForgeModuleFile
  def initialize(rvms=[])
    @rvms = rvms
  end
end

def parse_config(config_file)
  YAML.load_file(config_file)
end

def parse_opts(args)
  options = {}
  opt_parser = OptionParser.new do |opts|
    opts.banner = "Usage: sync.rb -m <commit message>"
    opts.on('-m', '--message <msg>',
            'Commit message to apply to updated modules') do |msg|
      options[:message] = msg
    end
    options[:help] = opts.help
  end.parse!

  options.fetch(:message) do
    puts options[:help]
    puts "A commit message is required."
    exit
  end

  options
end

def build(from_erb_template)
  erb_obj = ERB.new(File.read(from_erb_template), nil, '-')
  erb_obj.filename = from_erb_template.chomp('.erb')
  erb_obj.def_method(ForgeModuleFile, 'render()')
  erb_obj
end

def render(template, options = {})
  ForgeModuleFile.new(options['rvms']).render()
end

def sync(template, to_file)
  File.open(to_file, 'w') do |file|
    file.write(template)
  end
end

def update_repo(name, files, message)
  repo = Git.open("#{PROJ_ROOT}/#{name}")
  repo.branch('master').checkout
  repo.pull
  repo.add(files)
  begin
    repo.commit(message)
    # TODO: repo.push
  rescue Git::GitExecuteError => git_error
    puts "There were no files to update in #{name}. Not committing." if git_error.message.include? "nothing to commit, working directory clean"
  end
end


configs  = parse_config('config.yml')
defaults = configs['default']
options  = parse_opts(ARGV)

local_files = Find.find(MODULE_FILES_DIR).collect { |file| file if !File.directory?(file) }.compact
module_files = local_files.map { |file| file.sub(/#{MODULE_FILES_DIR}/, '') }

configs.reject {|k,v| k == 'default'}.each do |puppet_module, moduleconfigs|
  puts "Syncing #{puppet_module}"
  module_configs = defaults.merge(module_configs || {})
  local_files.each do |file|
    erb = build(file)
    template = render(erb, configs[puppet_module])
    sync(template, "#{PROJ_ROOT}/#{puppet_module}/#{file.sub(/#{MODULE_FILES_DIR}/, '')}")
  end
  update_repo(puppet_module, module_files, options[:message])
end
