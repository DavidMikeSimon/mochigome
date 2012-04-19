ActionController::Routing::Routes.draw do |map|
  map.report '/report', :controller => 'report', :action => 'show'
  map.report '/report.:format', :controller => 'report', :action => 'show'
  map.edit_report '/report/edit', :controller => 'report', :action => 'edit'
end
