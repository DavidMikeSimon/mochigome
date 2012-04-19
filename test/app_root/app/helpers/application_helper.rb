module ApplicationHelper
  # Creates an xsl xpath match attribute for a tag with the given HTML class
  # http://pivotallabs.com/users/alex/blog/articles/427-xpath-css-class-matching
  # TODO: Move this into Morpheus
  def xpath_class(cls)
    "contains(concat(' ',normalize-space(@class),' '),' #{cls} ')"
  end
end
