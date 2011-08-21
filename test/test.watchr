require 'autowatchr'

Autowatchr.new(self) do |config|
  config.test_re = '^%s.+/.+\_test.rb$' % config.test_dir
  config.test_file = "unit/%s_test.rb"
end
