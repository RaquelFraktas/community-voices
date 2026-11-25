module Themes
  # What a labeler sees of one cluster: every member's post title, and Themes::ClusterExample values for the
  # chunks closest to its centroid.
  ClusterDescription = Data.define(:titles, :examples)
end
