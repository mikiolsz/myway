# frozen_string_literal: true

module Myway
  class DataModel
    def self.encrypt_password(*parts)
      Digest::SHA512.hexdigest(parts.compact.join(':'))
    end

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
      collection_errors << 'Incorrect collection name.' unless params['name']&.match?(/^[a-z0-9_-]{3,16}$/) && (@backend.collection_exist?(params['name']) == updating)
      collection_errors << 'Invalid source directory.' unless valid_source?(params['source'])
      collection_errors << 'Incorrect collection title.' unless params['title']&.match?(/.{3,64}/)
      collection_errors << 'Incorrect password.' unless params['password'].nil? || params['password'].empty? || params['password']&.length&.between?(8, 32)

      new_collection = {
        'source' => params['source'],
        'title' => params['title'],
        'description' => params['description'],
        'information' => params['information'],
        'sort_galleries_by' => params['sort_galleries_by'],
        'reverse_gallery_sort' => params['reverse_gallery_sort'] == 'true',
        'sort_images_by' => params['sort_images_by'],
        'reverse_image_sort' => params['reverse_image_sort'] == 'true',
        'operations' => {
          'allow_visitors' => params['allow_visitors'] == 'true',
          'allow_reactions' => params['allow_reactions'] == 'true',
          'allow_comments' => params['allow_comments'] == 'true',
          'reactions' => params['allowed_reactions'].split(' '),
          'allow_downloads' => params['allow_downloads'] == 'true',
        },
        'theme' => @default_theme,
        'owner' => @default_owner
      }
      new_collection.password = Digest::SHA512.hexdigest([params['name'], params['password']].join(':'))  unless params['password'].nil? || params['password'].empty?
      new_collection.miniature = {'max_width' => 320, 'max_height' => 240}
      new_collection.full = {'max_width' => 2000, 'max_height' => 1500}

      [collection_errors, new_collection]
    end

    def build_gallery_from(params, updating = false)
      gallery_errors = []
      gallery_errors << 'Invalid gallery title.' unless params['title'] && params['title'].length > 1
      gallery_errors << 'Invalid gallery or collection name' unless @backend.gallery_exist?(params['collection'], params['name']) == updating

      [gallery_errors, {'title' => params['title'], 'description' => params['description'], 'date' => params['date']}]
    end

    def build_comment_from(params, user_login = nil, user_name = nil, ip = nil)
      {'login' => user_login, 'name' => user_name, 'ip' => ip, 'timestamp' => Time.now.utc, 'comment' => params['comment'], 'visible' => true} if valid_comment_body?(params['comment']) && user_login && user_name && ip
    end

    def build_visitor_from(params, existing_logins, collection_password, collection_name, check_collection_password = true)
      user_errors = []
      user_errors << 'Invalid user login.' unless params['login']&.match?(/^[a-z]{3,16}$/)
      user_errors << 'Login already in use.' if existing_logins.include?(params['login'])
      user_errors << 'Invalid password.' unless params['password']&.length >= 8
      user_errors << 'Passwords do not match.' unless params['retype-password'] == params['password']
      user_errors << 'Incorrect collection password.' if check_collection_password && !valid_password?(collection_password, params['collection-password'], collection_name)

      [user_errors, {'login' => params['login'], 'name' => params['name'].strip.empty? ? params['login'] : params['name'], 'password' => DataModel.encrypt_password(params['login'], collection_name, params['password'])}]
    end

    def build_image_data_from(params, name)
      image_title = params['title']
      image_title = name if image_title.nil? || image_title.strip.empty?
      result = {'title' => image_title, 'filename' => params['filename'], 'date' => params['date']}
      result.description = params['description'].delete('<', '>').gsub(/:\/\//, '') if params['description']
      [[], result]
    end

    def valid_comment_body?(text)
      text && text.length >= 8 && text.length <= 512 && %w[< > :// http ftp .com].none? {|t| text.downcase.include?(t) }
    end

    def valid_password?(expected_encrypted_password, provided_password, collection_name, gallery_name = nil)
      expected_encrypted_password == DataModel.encrypt_password(collection_name, gallery_name, provided_password)
    end
  end

end

