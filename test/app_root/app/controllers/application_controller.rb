class ApplicationController < ActionController::Base
  layout "application"

  # Allows the use of ActionView helper methods elsewhere
  # i.e. help.pluralize(3, "banana")
  class Helper
    include Singleton
    include ActionView::Helpers
    include ApplicationHelper
  end
  def self.help
    Helper.instance
  end
  def help
    self.class.help
  end
end
