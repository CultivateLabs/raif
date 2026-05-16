# frozen_string_literal: true

# Pagy initializer file
# See https://ddnexus.github.io/pagy/api/pagy#backend

# Optionally override some pagy default options
# Pagy::DEFAULT[:items] = 20        # items per page
# Pagy::DEFAULT[:size]  = [1,4,4,1] # nav bar links

# When you are done setting your own default freeze it, so it will not get changed accidentally
# Pagy::DEFAULT.freeze

# Add the pagy backend to a controller or to an object that includes it
# Pagy >= 10 dropped the extras system; the bootstrap helpers live on the
# paginator instance (e.g. `pagy.series_nav(:bootstrap)`).
require "pagy/extras/bootstrap" if defined?(Pagy::Frontend)
