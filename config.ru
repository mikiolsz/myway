require 'bundler/setup'
Bundler.require(:default)

require 'securerandom'
%w[.session.secret .admin.secret].each { |file| File.write(file, SecureRandom.hex(64)) unless File.exist?(file) }

require './myway'
run Myway::Application
