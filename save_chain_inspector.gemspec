# frozen_string_literal: true

require_relative 'lib/save_chain_inspector/version'

Gem::Specification.new do |spec|
  spec.name = 'save_chain_inspector'
  spec.version = SaveChainInspector::VERSION
  spec.authors = ['Shinichi Maeshima']
  spec.email = ['netwillnet@gmail.com']

  spec.summary = 'A tool to investigate the order in which the saves of related models are executed.'
  spec.description = 'When you execute save on a model in Active Record, the saves of related models with pre-set hooks are also executed. SaveChainInspector provides a way to know which models and which hooks have been executed specifically.'
  spec.homepage = 'https://github.com/willnet/save_chain_inspector'
  spec.license = 'MIT'
  spec.required_ruby_version = '>= 3.0.0'

  spec.metadata['homepage_uri'] = spec.homepage
  spec.metadata['source_code_uri'] = 'https://github.com/willnet/save_chain_inspector'
  spec.metadata['changelog_uri'] = 'https://github.com/willnet/save_chain_inspector/releases'

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  gemspec = File.basename(__FILE__)
  spec.files = IO.popen(%w[git ls-files -z], chdir: __dir__, err: IO::NULL) do |ls|
    ls.readlines("\x0", chomp: true).reject do |f|
      (f == gemspec) ||
        f.start_with?(*%w[bin/ test/ spec/ features/ .git .github appveyor Gemfile])
    end
  end
  spec.bindir = 'exe'
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ['lib']

  # Uncomment to register a new dependency of your gem
  # spec.add_dependency "example-gem", "~> 1.0"

  # For more information and examples about making a new gem, check out our
  # guide at: https://bundler.io/guides/creating_gem.html
end
