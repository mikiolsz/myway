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

class Array
  def maybe_reverse(maybe)
    maybe ? reverse : self
  end
end

class String
  def human_readable
    self.gsub(/\\W/, ' ').capitalize
  end
end

class Time
  def time_ago
    case seconds_ago = Time.now-self
    when 0...10 then 'now'
    when 10...60 then 'less than a minute ago'
    when 60...3600 then '%d minutes ago' % [seconds_ago/60]
    when 3600...7200 then 'about an hour ago'
    when 7200...172800 then '%d hours ago' % [seconds_ago/3600]
    when 172800...1209600 then '%d days ago' % [seconds_ago/86400]
    when 1209600...31449600 then '%d weeks ago' % [seconds_ago/604800]
    else 'more than a year ago'
    end
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

    @context.galleries = Hash[@backend.available_galleries(collection_name)
                                      .collect { |g| [g, YAML.load_file(@backend.gallery_file(collection_name, g))] }
                                      .sort_by { |g| g[1][@context.collection.sort_galleries_by || 'name'] }
                                      .maybe_reverse(@context.collection.reverse_gallery_sort)] if options.include?(:galleries)
    gallery_name = parameters[:gallery] || @context.gallery_name
    if parameters.include?(:gallery)
      @context.gallery_name = gallery_name
      @context.gallery = @backend.gallery_data(collection_name, gallery_name)

      if options.include?(:images) || parameters[:image]
        @context.images = @backend.gallery_details(collection_name, gallery_name).sort_by { |i| i[@context.collection.sort_images_by || 'name'] }.maybe_reverse(@context.collection.reverse_image_sort)
        # modify the raw data to be more meaningful
        @context.images.each do |image|
          by_type = Hash.new { |h, k| h[k] = [] }
          image.all_reactions.each { |rf| rf.each { |reaction|  by_type[reaction.reaction] << reaction.login } }
          image.reactions = by_type
        end

        image_name = parameters[:image] || @context.image_name
        if parameters.include?(:image)
          @context.image_name = image_name
          index = @context.images.find_index { |i| i.name == image_name }
          @context.image = @context.images[index]
          @context.image.index = index
          @context.image.total = @context.images.size
          @context.image.next = '/' + ['collection', collection_name, gallery_name, @context.images[index+1].name].join('/') unless index >= @context.images.size - 1
          @context.image.previous = '/' + ['collection', collection_name, gallery_name, @context.images[index-1].name].join('/') unless index <= 0
        end
      end
    end

    if collection_name && session[collection_name] && session[collection_name].user && (session_authenticated = @context.collection&.visitors&.find {|v| v.login == session[collection_name].user})
      @context.user = {'login' => session_authenticated.login, 'name' => session_authenticated.name}
    else
      # update user information (as it depends on what already is in the context)
      @auth ||= Rack::Auth::Basic::Request.new(request.env)
      has_credentials = @auth.provided? && @auth.basic? && @auth.credentials
      is_admin = has_credentials && @config.admin.login == @auth.credentials[0] && @config.admin.password == DataModel.encrypt_password(@auth.credentials[0], settings.admin_secret, @auth.credentials[1])
      if is_admin
        @context.user = {'login' => @config.admin.login, 'name' => @config.admin.name, 'admin' => true}
      else
        @context.user = {}
        user = has_credentials && @context.collection && @context.collection&.visitors&.find {|v| v.login == @auth.credentials[0] && v.password == DataModel.encrypt_password(@auth.credentials[0], @context.collection_name, @auth.credentials[1]) }
        if user
          @context.user.login = user.login
          @context.user.name = user.name
        end
      end
    end

    # update user reactions into a manageable form
    @context.images.each { |image| image.user_reactions = Hash[@context.collection.operations.reactions.collect { |allowed_reaction| [allowed_reaction, image.reactions[allowed_reaction].include?(@context.user.login)] }] } if @context.user.login && @context.images && @context.collection.operations.allow_reactions

    admin_auth! if @context.collection_name && session[@context.collection_name] && session[@context.collection_name].user == @config.admin.login
  end

  def authenticate_in_response
    response['WWW-Authenticate'] = %(Basic realm="#{@config.title}")
    throw(:halt, [401, "Login and password required.\n"])
  end

  def admin_auth!
    session.clear # remove all session-based auth when logging in as admin
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
      session[collection_name]&.title == @context.collection.title
  end

  before do
    @backend = Backend.new
    @config = @backend.load_config
    @data_model = DataModel.new(@backend, @config.admin.login, @config.theme) if @config

    in_context # initialise context

    Application.set :views, 'views/themes/' + (@context.collection&.theme || @config&.theme || 'default')
  end

  get '/setup' do
    halt 401 if @config
    # use @config to make layout work (still, original file-based config does not exist)
    @config = {'title' => 'Myway setup', 'theme' => 'default', 'admin' => {}}
    erb :setup, :locals => { :available_themes => @backend.available_themes, :config => @config, :user_errors => [] }
  end

  post '/setup' do
    admin_auth! if @config

    current_config = {
      'title' => params['title'],
      'theme' => params['theme'],
      'admin' => {'login' => params['login'], 'name' => params['name']},
      'site_information' => params['site-information'],
      'site_description' => params['site-description']
    }

    user_errors = []
    user_errors << 'Incorrect title.' unless params['title']&.length&.between?(3, 64)
    user_errors << 'No default theme.' unless params['theme']&.length&.positive?
    user_errors << 'Invalid user login.' unless params['login']&.match?(/^[a-z]{3,16}$/)
    user_errors << 'Invalid password.' unless params['password']&.length >= 8
    user_errors << 'Passwords do not match.' unless params['retype-password'] == params['password']
    if user_errors.empty?
      current_config.admin.password = DataModel.encrypt_password(current_config.admin.login, settings.admin_secret, params['password'])
      @backend.update_setup(current_config)
      redirect to('/')
    else
      erb :setup, locals: {available_themes: @backend.available_themes, config: current_config, user_errors: user_errors }
    end
  end

  get '/admin' do
    admin_auth!
    redirect to('/')
  end

  get '/admin/setup' do
    admin_auth!
    erb :setup, locals: {available_themes: @backend.available_themes, config: @config, user_errors: [] }
  end

  get '/admin/collection' do
    admin_auth!
    erb :new_collection, locals: {collection_errors: [], collection: {}}
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
      erb :new_collection, locals: {collection_errors: collection_errors, collection: new_collection}
    end
  end

  get '/' do
    if !@config
      erb :no_setup, :layout => false
    else
      in_context :collections

      erb @context.collections.empty? ? :no_collections : :collection_list
    end
  end

  post '/collection' do
    # password protection is sent here
    halt 400 unless params['password'] && params['name']
    halt 404 unless @backend.available_collections.include? params['name']
    in_context :collections, :collection => params['name']

    if @data_model.valid_password?(@context.collection.password, params['password'], @context.collection_name)
      session[@context.collection_name] = {'title' => @context.collection.title}
      redirect to('/collection/' + @context.collection_name)
    else
      erb :password_protected, locals: {incorrect_password: true}
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

    erb view_to_render, locals: {incorrect_password: false}
  end

  get '/login/:name?' do |collection_name|
    halt 404 unless @backend.available_collections.include?(collection_name)
    in_context :collections, :collection => collection_name
    user_auth!
    in_context # update user info
    session[collection_name] = {'title' => @context.collection.title, 'user' => @context.user.login} # store in session
    redirect to('/collection/' + collection_name)
  end

  get '/register/:name?' do |collection_name|
    halt 404 unless @backend.available_collections.include?(collection_name)
    in_context :collections, :collection => collection_name
    erb :register, locals: {login_after_submission: true, visitor: {}, visitor_errors: [], ask_collection_password: session[collection_name]&.title.nil?}
  end

  post '/register/:collection_name?' do |collection_name|
    halt 404 unless @backend.available_collections.include?(collection_name)
    in_context :collections, :collection => collection_name
    halt 400 unless @context.collection.operations.allow_visitors
    visitor_errors, new_visitor = @data_model.build_visitor_from(params, [@config.admin.login] + (@context.collection.visitors&.collect {|v| v.login} || []), @context.collection.password, collection_name, session[collection_name]&.title.nil?)
    if visitor_errors.empty?
      @backend.update_visitor(collection_name, new_visitor)
      if params['login-after-submission']
        redirect to('/login/' + collection_name)
      else
        redirect to('/edit/' + collection_name)
      end
    else
      erb :register, locals: {login_after_submission: params['login_after_submission'], visitor: new_visitor, visitor_errors: visitor_errors, ask_collection_password: session[collection_name]&.title.nil?}
    end
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

    erb view_to_render, locals: {incorrect_password: false}
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
    erb view_to_render, locals: {incorrect_password: false}
  end

  post '/react/:collection_name/:gallery_name/:image_name' do |collection_name, gallery_name, image_name|
    halt 404 unless @backend.available_collections.include?(collection_name) && @backend.available_galleries(collection_name).include?(gallery_name) && @backend.available_images(collection_name, gallery_name).include?(image_name)
    content_type :json
    in_context :collections, :collection => collection_name
    user_auth!
    if can_access?(collection_name)
      in_context :galleries, :images, :gallery => gallery_name, :image => image_name
      reaction = request.body.read.force_encoding(Encoding::UTF_8)
      halt 400, "invalid data encoding; expected utf-8" unless reaction.valid_encoding?

      previous_state = @context.image.user_reactions[reaction]
      previous_count = @context.image.reactions[reaction].count
      @backend.user_reaction(collection_name, gallery_name, image_name, reaction, @context.user.login)
      {reacted: !previous_state, count: previous_state ? previous_count - 1 : previous_count + 1}.to_json
    else
      halt 403
    end
  end

  post '/comment/:collection_name/:gallery_name/:image_name' do |collection_name, gallery_name, image_name|
    halt 400 unless params['collection'] == collection_name && params['gallery'] == gallery_name && params['image'] == image_name
    halt 404 unless @backend.available_collections.include?(collection_name) && @backend.available_galleries(collection_name).include?(gallery_name) && @backend.available_images(collection_name, gallery_name).include?(image_name)
    in_context :collection, :collection => collection_name
    user_auth!
    halt 403 unless can_access?(collection_name)
    in_context :galleries, :images, :gallery => gallery_name, :image => image_name
    comment = @data_model.build_comment_from(params, @context.user.login, @context.user.name, request.ip)
    @backend.user_comment(collection_name, gallery_name, image_name, comment) if comment
    redirect to('/collection/' + collection_name + '/' + gallery_name + '/' + image_name)
  end

  get '/edit/:collection_name' do |collection_name|
    halt 404 unless @backend.available_collections.include?(collection_name)
    in_context :collections, :galleries, :collection => collection_name
    halt 403 unless can_change_collection?

    erb :edit_collection, locals: {collection_errors: [], collection: @context.collection}
  end

  post '/edit/:collection_name' do |collection_name|
    halt 400 unless collection_name == params['name']
    halt 404 unless @backend.available_collections.include?(collection_name)
    in_context :collections, :collection => collection_name

    user_auth!
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
      erb :edit_collection, locals: {collection_errors: collection_errors, collection: new_collection}
    end

  end

  get '/edit/:collection_name/:gallery_name' do |collection_name, gallery_name|
    halt 404 unless @backend.available_collections.include?(collection_name) && @backend.available_galleries(collection_name).include?(gallery_name)
    in_context :collections, :galleries, :collection => collection_name, gallery: gallery_name
    halt 403 unless can_change_collection?

    erb :edit_gallery, locals: {gallery_errors: [], collection: @context.collection, gallery: @context.gallery}
  end

  post '/edit/:collection_name/:gallery_name' do |collection_name, gallery_name|
    halt 400 unless collection_name == params['collection'] && gallery_name == params['name']
    halt 404 unless @backend.available_collections.include?(collection_name) && @backend.available_galleries(collection_name).include?(gallery_name)
    in_context :collections, :galleries, :collection => collection_name, gallery: gallery_name
    user_auth!
    halt 403 unless can_change_collection?

    gallery_errors, new_gallery = @data_model.build_gallery_from(params, true)

    if gallery_errors.empty?
      @backend.update_gallery(collection_name, gallery_name, new_gallery)
      redirect to('/collection/' + collection_name + '/' + gallery_name)
    else
      erb :edit_gallery, locals: {gallery_errors: gallery_errors, collection: @context.collection, gallery: new_gallery}
    end
  end

  get '/edit/:collection_name/:galler_name/:image_name' do |collection_name, gallery_name, image_name|
    halt 404 unless @backend.available_collections.include?(collection_name) && @backend.available_galleries(collection_name).include?(gallery_name) && @backend.available_images(collection_name, gallery_name).include?(image_name)
    in_context :collections, :galleries, :images, :collection => collection_name, gallery: gallery_name, image: image_name
    halt 403 unless can_change_collection?

    erb :edit_image, locals: {image_errors: [], collection: @context.collection, gallery: @context.gallery, image: @context.image}
  end

  post '/edit/:collection_name/:gallery_name/:image_name' do |collection_name, gallery_name, image_name|
    halt 400 unless collection_name == params['collection'] && gallery_name == params['gallery'] && image_name == params['name']
    halt 404 unless @backend.available_collections.include?(collection_name) && @backend.available_galleries(collection_name).include?(gallery_name) && @backend.available_images(collection_name, gallery_name).include?(image_name)
    in_context :collections, :galleries, :images, :collection => collection_name, gallery: gallery_name, image: image_name
    halt 400 unless @context.image.filename == params['filename']
    user_auth!
    halt 403 unless can_change_collection?

    _, new_image = @data_model.build_image_data_from(params, image_name)

    @backend.update_image(collection_name, gallery_name, image_name, new_image)
    redirect to('/collection/' + collection_name + '/' + gallery_name + '/' + image_name)
  end

  get '/download/:collection_name/:gallery_name/:image_name' do |collection_name, gallery_name, image_name|
    halt 404 unless @backend.available_collections.include?(collection_name) && @backend.available_galleries(collection_name).include?(gallery_name) && @backend.available_images(collection_name, gallery_name).include?(image_name)
    in_context :collections, :collection => collection_name
    halt 403 unless @context.collection.operations.allow_downloads
    if can_access?(collection_name)
      in_context :galleries, :images, :gallery => gallery_name, :image => image_name
      original_file = File.join(@context.collection.source, gallery_name, @context.image.filename)
      halt 404 unless File.exist?(original_file) && File.readable?(original_file)
      send_file original_file, filename: @context.image.filename, type: 'image', disposition: 'attachment'
    else
      erb :password_protected, locals: {incorrect_password: false}
    end


  end

end

end
