# frozen_string_literal: true

source 'https://rubygems.org'

# Runtime is stdlib-only on purpose: the daemon runs inside the long-lived
# omarchy shell session and must not drag a vendored bundle with it. Everything
# below is development/test tooling only.
group :development, :test do
  gem 'rake'
  gem 'rspec'
  gem 'rubocop'
  gem 'rubocop-performance'
  gem 'rubocop-rake'
  gem 'rubocop-rspec'
end
