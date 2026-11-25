module Themes
  # Colors for clusters, shared by the server-rendered legend and the chart. Based on the Okabe–Ito palette,
  # which stays distinguishable for the common forms of color blindness.
  module Palette
    COLORS = %w[#0072B2 #E69F00 #009E73 #CC79A7 #56B4E9 #D55E00 #F0E442 #000000].freeze

    def self.color_for(position)
      COLORS[position % COLORS.size]
    end
  end
end
