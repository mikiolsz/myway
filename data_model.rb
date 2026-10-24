# frozen_string_literal: true

module Myway
  class DataModel
    def initialize(backend, default_owner, default_theme = 'default')
      @backend = backend
      @default_theme = default_theme
      @default_owner = default_owner
    end

    def valid_source?(path)
      path != '.' && path != '..' && path != '/' && !path&.include?('..') && !path&.include?('//') && path&.length > 2 && File.directory?(path) && File.readable?(path)
    end

    def build_collection_from(params, updating = false)
      collection_errors = []
      collection_errors << 'Incorrect collection name.' unless params['name']&.match?(/[a-z0-9_-]{3,16}/) && (@backend.collection_exist?(params['name']) == updating)
      collection_errors << 'Invalid source directory.' unless valid_source?(params['source'])
      collection_errors << 'Incorrect collection title.' unless params['title']&.match?(/.{3,64}/)
      collection_errors << 'Incorrect password.' unless params['password'].nil? || params['password'].empty? || params['password']&.length&.between?(8, 32)

      new_collection = {
        'source' => params['source'],
        'title' => params['title'],
        'description' => params['description'],
        'operations' => {
          'allow_visitors' => params['allow_visitors'] == 'true',
          'allow_reactions' => params['allow_reactions'] == 'true',
          'allow_comments' => params['allow_comments'] == 'true',
          'reactions' => params['allowed_reactions'].split(' ')
        },
        'theme' => @default_theme,
        'owner' => @default_owner
      }
      new_collection.password = Digest::SHA512.hexdigest([params['name'], params['password']].join(':'))  unless params['password'].nil? || params['password'].empty?
      new_collection.miniature = {'max_width' => 320, 'max_height' => 240}
      new_collection.full = {'max_width' => 2000, 'max_height' => 1500}

      [collection_errors, new_collection]
    end

    def valid_password?(expected_encrypted_password, provided_password, collection_name, gallery_name = nil)
      expected_encrypted_password == Digest::SHA512.hexdigest([collection_name, gallery_name, provided_password].compact.join(':'))
    end
  end


end

