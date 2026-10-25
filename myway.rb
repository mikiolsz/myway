# frozen_string_literal: true

require 'sinatra'
require 'rack/protection'
require 'yaml'
require 'digest/sha2'
require 'open3'
require './backend_yaml'
require './data_model'

# enable method-like access for keys
class Hash
  def method_missing(name, *args, &block)
    name.end_with?('=') ? self[name.to_s[0..-2]] = args[0] : self[name.to_s]
  end
end

class String
  def human_readable
    self.gsub(/\\W/, ' ').capitalize
  end
end

module Myway
class Application < Sinatra::Base
  enable :sessions
  set :session_store, Rack::Session::Pool
  set :session_secret, File.read('.session.secret')
  set :admin_secret, File.read('.admin.secret')

  use Rack::Session::Pool, :expire_after => 2592000, :key => 'myway.session'
  use Rack::Protection
  use Rack::Protection::RemoteToken
  use Rack::Protection::SessionHijacking

  def in_context(*options, **parameters)
    @context ||= {}
    @context.collections = @backend.all_collections(@context.user) if options.include?(:collections)
    collection_name = parameters[:collection] || @context.collection_name
    if parameters.include?(:collection)
      @context.collection_name = collection_name
      @context.collection = @backend.collection_data(collection_name)
    end

    @context.galleries = Hash[@backend.available_galleries(collection_name).collect { |g| [g, YAML.load_file(@backend.gallery_file(collection_name, g))] } ] if options.include?(:galleries)
    gallery_name = parameters[:gallery] || @context.gallery_name
    if parameters.include?(:gallery)
      @context.gallery_name = gallery_name
      @context.gallery = @backend.gallery_data(collection_name, gallery_name)

      @context.images = @backend.gallery_details(collection_name, gallery_name) if options.include?(:images) || parameters[:image]
      image_name = parameters[:image] || @context.image_name
      if parameters.include?(:image)
        @context.image_name = image_name
        index = @context.images.find_index { |i| i.data_name == image_name }
        @context.image = @context.images[index]
        @context.image.index = index
        @context.image.total = @context.images.size
        @context.image.next = '/' + ['collection', collection_name, gallery_name, @context.images[index+1].data_name].join('/') unless index >= @context.images.size
        @context.image.previous = '/' + ['collection', collection_name, gallery_name, @context.images[index-1].data_name].join('/') unless index <= 0
      end
    end

    # update user information (as it depends on what already is in the context)
    @auth ||= Rack::Auth::Basic::Request.new(request.env)
    has_credentials = @auth.provided? && @auth.basic? && @auth.credentials
    is_admin = has_credentials && @config.admin.login == @auth.credentials[0] && @config.admin.password == Digest::SHA512.hexdigest(@auth.credentials.join(":#{settings.admin_secret}:"))
    if is_admin
      @context.user = {'login' => @config.admin.login, 'name' => @config.admin.name, 'admin' => true}
    else
      @context.user = {}
      user = has_credentials && @context.collection && @context.collection&.visitors&.find {|v| v.login == @auth.credentials[0] && v.password == Digest::SHA512.hexdigest(@auth.credentials.join(":#{@context.collection_name}:")) }
      if user
        @context.user.login = user.login
        @context.user.name = user.name
      end
    end
  end

  def authenticate_in_response
    response['WWW-Authenticate'] = %(Basic realm="#{@config.title}")
    throw(:halt, [401, "Login and password required.\n"])
  end

  def admin_auth!
    authenticate_in_response unless @context.user.admin
  end

  def user_auth!
    authenticate_in_response unless @context.user.login && (@context.user.admin || @context.collection&.operations&.allow_visitors)
  end

  def can_change_collection?
    @context.collection_name && (@context.user.admin || @context.user.login == @context.collection.owner)
  end

  def can_access?(collection_name)
    @context.collection.password.nil? ||
      @context.user.admin ||
      (@context.collection.visitors || []).include?(@context.user.login) ||
      session[collection_name] == @context.collection.title
  end

  before do
    @backend = Backend.new
    @config = @backend.load_config
    @data_model = DataModel.new(@backend, @config.admin.login, @config.theme) if @config

    in_context # initialise context
  end

  get '/setup' do
    halt 401 if @config

    erb :setup, :layout => :admin, :locals => { :available_themes => @backend.available_themes, :config => {}, :user_errors => [] }
  end

  post '/setup' do
    halt 401 if @config

    current_config = {'title' => params['title'], 'theme' => params['theme'], 'admin' => {'login' => params['login'], 'name' => params['name']}}

    user_errors = []
    user_errors << 'Incorrect title.' unless params['title']&.length&.between?(3, 64)
    user_errors << 'No default theme.' unless params['theme']&.length&.positive?
    user_errors << 'Invalid user login.' unless params['login']&.match?(/[a-z]{3,16}/)
    user_errors << 'Invalid password.' unless params['password']&.length > 8
    user_errors << 'Passwords do not match.' unless params['retype-password'] == params['password']
    if user_errors.empty?
      current_config.admin.password = Digest::SHA512.hexdigest([current_config.admin.login, settings.admin_secret, params['password']].join(':'))
      @backend.update_setup(current_config)
      redirect to('/')
    else
      erb :setup, layout: :admin, locals: {available_themes: @backend.available_themes, config: current_config, user_errors: user_errors }
    end
  end

  get '/admin' do
    admin_auth!
    redirect to('/')
  end

  get '/admin/collection' do
    admin_auth!
    erb :new_collection, layout: :admin, locals: {collection_errors: [], collection: {}}
  end

  post '/admin/collection' do
    admin_auth!

    collection_errors, new_collection = @data_model.build_collection_from params

    if collection_errors.empty?
      @backend.update_collection(params['name'], new_collection)
      Thread.new(new_collection, params['name'], params['source']) do |collection, name, source|
        begin
          @backend.init_collection(name, source, "#{collection.miniature.max_width}x#{collection.miniature.max_height}", "#{collection.full.max_width}x#{collection.full.max_height}")
        rescue => e
          warn "problems indexing collection #{name}, error of type #{e.class}: #{e.message}"
        end
      end
      redirect to('/')
    else
      erb :new_collection, layout: :admin, locals: {collection_errors: collection_errors, collection: new_collection}
    end
  end

  get '/' do
    redirect to('/setup') unless @config
    in_context :collections

    erb (@context.collections.empty? ? :no_collections : :collection_list), views: 'views/themes/' + @config.theme, layout: :site_layout
  end

  post '/collection' do
    # password protection is sent here
    halt 400 unless params['password'] && params['name']
    halt 404 unless @backend.available_collections.include? params['name']
    in_context :collections, :collection => params['name']

    if @data_model.valid_password?(@context.collection.password, params['password'], @context.collection_name)
      session[@context.collection_name] = @context.collection.title
      redirect to('/collection/' + @context.collection_name)
    else
      erb :password_protected, views: 'views/themes/' + (@context.collection.theme || @config.theme), layout: :site_layout, locals: {incorrect_password: true}
    end
  end

  get '/collection/:name?' do |collection_name|
    halt 404 unless @backend.available_collections.include?(collection_name)

    in_context :collections, :collection => collection_name

    view_to_render = if can_access?(collection_name)
                       in_context :galleries
                       :collection
                     elsif @context.collection.password
                       :password_protected
                     else halt 500
                     end

    erb view_to_render, views: 'views/themes/' + (@context.collection.theme || @config.theme), layout: :site_layout, locals: {incorrect_password: false}
  end

  get '/collection/:collection_name/:gallery_name' do |collection_name, gallery_name|
    halt 404 unless @backend.available_collections.include?(collection_name) && @backend.available_galleries(collection_name).include?(gallery_name)
    in_context :collections, :collection => collection_name

    view_to_render = if can_access?(collection_name)
                       in_context :galleries, :images, :gallery => gallery_name
                       :gallery
                     else
                       :password_protected
                     end

    erb view_to_render, views: 'views/themes/' + (@context.collection.theme || @config.theme), layout: :site_layout
  end

  get '/collection/:collection_name/:gallery_name/:image_name' do |collection_name, gallery_name, image_name|
    halt 404 unless @backend.available_collections.include?(collection_name) && @backend.available_galleries(collection_name).include?(gallery_name) && @backend.available_images(collection_name, gallery_name).include?(image_name)
    in_context :collections, :collection => collection_name
    view_to_render = if can_access?(collection_name)
                       in_context :galleries, :images, :gallery => gallery_name, :image => image_name
                       :image
                     else
                       :password_protected
                     end
    erb view_to_render, views: 'views/themes/' + (@context.collection.theme || @config.theme), layout: :site_layout
  end

  get '/edit/:collection_name' do |collection_name|
    halt 404 unless @backend.available_collections.include?(collection_name)
    in_context :collections, :galleries, :collection => collection_name
    halt 403 unless can_change_collection?

    erb :edit_collection, layout: :admin, locals: {collection_errors: [], collection: @context.collection}
  end

  post '/edit/:collection_name' do |collection_name|
    user_auth!

    halt 400 unless collection_name == params['name']
    halt 404 unless @backend.available_collections.include?(collection_name)
    in_context :collections, :collection => collection_name
    halt 403 unless can_change_collection?

    collection_errors, new_collection = @data_model.build_collection_from(params, true)

    if collection_errors.empty?
      @backend.update_collection(collection_name, new_collection)
      Thread.new(new_collection, collection_name, @context.collection.source) do |collection, name, source|
        begin
          @backend.reinit_collection(name, source, "#{collection.miniature.max_width}x#{collection.miniature.max_height}", "#{collection.full.max_width}x#{collection.full.max_height}")
        rescue => e
          warn "problems reindexing collection #{name}, error of type #{e.class}: #{e.message}"
        end
      end
      redirect to('/collection/' + collection_name)
    else
      erb :edit_collection, layout: :admin, locals: {collection_errors: collection_errors, collection: new_collection}
    end

  end

end

end
