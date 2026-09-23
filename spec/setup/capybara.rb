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

RSpec.configure do |config|
  # Cuprite leaves Chrome to a finalizer, which runs after every at_exit hook. Once anything in the
  # suite forks - the eval worker specs do - the debug gem adds an at_exit hook that waits for every
  # child process, so a Chrome still open at that point holds the suite open forever.
  config.after(:suite) do
    Capybara.using_driver(:cuprite) { Capybara.current_session.driver.quit }
  end
end
