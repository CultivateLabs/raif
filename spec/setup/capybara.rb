# frozen_string_literal: true

require "capybara/cuprite"

Capybara.javascript_driver = :cuprite
Capybara.register_driver(:cuprite) do |app|
  headless = ENV["HEADLESS"] != "false"
  browser_options = { "no-sandbox": nil }

  opts = {
    browser_options: browser_options,
    flatten: false,
    process_timeout: 25,
    window_size: [1440, 900],
    headless: headless,
  }

  opts[:slowmo] = 0.01 unless headless
  Capybara::Cuprite::Driver.new(app, opts)
end

Capybara.disable_animation = true
