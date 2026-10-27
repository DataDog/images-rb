# frozen_string_literal: true

gemfile = "#{RUBY_ENGINE}-#{RUBY_ENGINE_VERSION.split(".").take(2).join(".")}.gemfile"
eval_gemfile "gemfiles/#{gemfile}"

if Gem::Version.new(RUBY_VERSION) >= Gem::Version.new("3.3")
  group :tools do
    gem "rexml"
  end
end
