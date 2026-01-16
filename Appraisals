# frozen_string_literal: true

# Note: Rails < 7.2 is not compatible with Ruby 3.4
# (Logger became a bundled gem in Ruby 3.4, and only Rails 7.2+ handles this)
# See: https://stdgems.org/logger/

# Test against Rails 7.2 (minimum version compatible with Ruby 3.4)
appraise "rails-7.2" do
  gem "rails", "~> 7.2.0"
end

# Test against Rails 8.0
appraise "rails-8.0" do
  gem "rails", "~> 8.0.0"
end

# Test against Rails 8.1 (latest)
appraise "rails-8.1" do
  gem "rails", "~> 8.1.0"
end
