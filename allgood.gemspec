# frozen_string_literal: true

require_relative "lib/allgood/version"

Gem::Specification.new do |spec|
  spec.name = "allgood"
  spec.version = Allgood::VERSION
  spec.authors = ["rameerez"]
  spec.email = ["rubygems@rameerez.com"]

  spec.summary = "Add quick, simple, and beautiful health checks to your Rails application."
  spec.description = "Define custom health checks for your app (as in: are there any new users in the past 24 hours) and see the results in a simple /healthcheck page that you can use to monitor your production app with UptimeRobot, Pingdom, or other monitoring services. It's also useful as a drop-in replacement for the default `/up` health check endpoint for Kamal deployments."
  spec.homepage = "https://github.com/rameerez/allgood"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.0.0"

  spec.metadata["allowed_push_host"] = "https://rubygems.org"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://github.com/rameerez/allgood"
  spec.metadata["changelog_uri"] = "https://github.com/rameerez/allgood/blob/main/CHANGELOG.md"

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  gemspec = File.basename(__FILE__)
  spec.files = IO.popen(%w[git ls-files -z], chdir: __dir__, err: IO::NULL) do |ls|
    ls.readlines("\x0", chomp: true).reject do |f|
      (f == gemspec) ||
        f.start_with?(*%w[bin/ test/ spec/ features/ .git appveyor Gemfile])
    end
  end
  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_dependency "rails", ">= 6.0.0"
end
