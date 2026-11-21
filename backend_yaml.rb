# frozen_string_literal: true

require 'fileutils'

module Myway
  class Backend
    MAIN_CONFIG_FILE = 'collections/.config.yml'.freeze

    def load_config
      result = YAML.load_file(MAIN_CONFIG_FILE)
      result.theme ||= 'default' if result
      result
    rescue
      nil
    end

    def available_themes
      Dir.glob('views/themes/*').select { |entry| File.directory?(entry) && !entry.start_with?('.') }.collect { |dir| dir.split('/').last }
    end
    def available_collections
      Dir.glob('collections/*').select { |dir| File.directory?(dir) && !dir.start_with?('.') }.collect { |dir| dir.split('/').last }
    end
    def all_collections(user = nil)
      Hash[available_collections.collect { |entry| [entry, (YAML.load_file(collection_file(entry)) rescue nil)] }.reject { |a| a[1].nil? }.filter { |a| user.admin || a[1].password.nil? || a[1].visitors&.any? {|v| v.login == user.login} }]
    end
    def collection_data(name)
      YAML.load_file(collection_file(name))
    end
    def gallery_data(collection_name, gallery_name)
      YAML.load_file(gallery_file(collection_name, gallery_name))
    end

    def collection_exist?(name)
      Dir.exist?(collection_dir(name))
    end

    def gallery_exist?(collection, gallery)
      Dir.exist?(gallery_dir(collection, gallery))
    end

    def available_galleries(collection_name)
      Dir.glob(File.join(collection_dir(collection_name), '*')).select { |dir| File.directory?(dir) && !dir.start_with?('.') }.collect { |dir| dir.split('/').last }
    end

    def available_images(collection_name, gallery_name)
      Dir.glob(File.join(gallery_dir(collection_name, gallery_name), '*.yml')).select {|path| File.file?(path)}.collect { |dir| File.basename(dir, '.*') }
    end

    def collection_file(name)
      ('collections/' + name + '/.collection.yml').freeze
    end
    def collection_dir(name)
      'collections/' + name
    end
    def ensure_collection_dir(name)
      [collection_dir(name), public_images_dir, public_images_dir(name)].each { |path| Dir.mkdir(path) unless Dir.exist?(path) }
    end

    def gallery_file(collection, gallery)
      [gallery_dir(collection, gallery), '.gallery.yml'].join('/')
    end
    def gallery_dir(collection, gallery)
      ['collections', collection, gallery].join('/')
    end
    def public_images_dir(collection = nil, gallery = nil)
      ['public', 'images', collection, gallery].compact.join('/')
    end
    def ensure_gallery_dir(collection, gallery)
      [gallery_dir(collection, gallery), public_images_dir(collection, gallery)].each { |dir| Dir.mkdir(dir) unless Dir.exist?(dir) }
    end

    def image_data_file(collection, gallery, image)
      [gallery_dir(collection, gallery), image + '.yml'].join('/')
    end
    def image_miniature_file(collection, gallery, file)
      [public_images_dir(collection, gallery), 'mini.' + file].join('/')
    end
    def image_miniature_url(collection, gallery, file)
      ['/images', collection, gallery, 'mini.'+file].join('/')
    end
    def image_full_file(collection, gallery, file)
      [public_images_dir(collection, gallery), 'full.'+file].join('/')
    end
    def image_full_url(collection, gallery, file)
      ['/images', collection, gallery, 'full.'+file].join('/')
    end

    def image_data_dir(collection, gallery, image)
      ['collections', collection, gallery, image].join('/')
    end
    def ensure_image_data_dir(collection, gallery, image)
      Dir.mkdir(image_data_dir(collection, gallery, image)) unless Dir.exist?(image_data_dir(collection, gallery, image))
    end

    def image_reactions(collection, gallery, image)
      Dir.glob(File.join(image_data_dir(collection, gallery, image), 'reaction.*.yml')).collect { |path| YAML.load_file(path) rescue nil }.compact
    end
    def image_comments(collection, gallery, image)
      Dir.glob(File.join(image_data_dir(collection, gallery, image), 'comment.*.yml')).collect { |path| YAML.load_file(path, permitted_classes: [Time])  }.compact.select { |comment| comment.visible }
    end

    def update_visitor(collection, visitor)
      collection_data = collection_data(collection)
      collection_data.visitors ||= []
      if (existing_visitor = collection_data.visitors.find {|v| v.login == visitor.login})
        existing_visitor.name = visitor.name
        existing_visitor.password = visitor.password
      else
        collection_data.visitors << visitor
      end
      File.write(collection_file(collection), YAML.dump(collection_data))
    end

    def gallery_details(collection, gallery)
      Dir.glob(File.join(gallery_dir(collection, gallery), '*.yml'))
         .collect { |path| File.basename(path, '.*') }
         .collect do |image_name|

        image_data_file = image_data_file(collection, gallery, image_name)
        details = YAML.load_file(image_data_file)
        details.data_file = image_data_file
        details.name = image_name
        details.all_comments = image_comments(collection, gallery, image_name)
        details.all_reactions = image_reactions(collection, gallery, image_name)
        details.file_path = {'miniature' => image_miniature_file(collection, gallery, details.filename), 'full' => image_full_file(collection, gallery, details.filename)}
        details.url_path = {'miniature' => image_miniature_url(collection, gallery, details.filename), 'full' => image_full_url(collection, gallery, details.filename)}
        details
      end
    end

    def user_reaction(collection, gallery, image, reaction, user)
      reaction_file = File.join(image_data_dir(collection, gallery, image), ['reaction', user, 'yml'].join('.'))

      image_reactions = File.exist?(reaction_file) ? YAML.load_file(reaction_file) : []
      found = image_reactions.find { |r| r.reaction == reaction }
      if found
        image_reactions.delete(found)
      else
        image_reactions <<  {'reaction' => reaction, 'login' => user, 'time' => Time.now.utc.to_s}
      end
      if image_reactions.empty?
        File.delete(reaction_file) if File.exist?(reaction_file)
      else
        File.write(reaction_file, YAML.dump(image_reactions))
      end
    end

    def user_comment(collection, gallery, image, comment)
      comment_file = File.join(image_data_dir(collection, gallery, image), ['comment', (comment.timestamp.to_f*1000).to_i.to_s, 'yml'].join('.'))
      File.write(comment_file, YAML.dump(comment))
    end

    def read_directories_from(path_to_scan)
      Dir.glob(File.join(path_to_scan, '*')).select { |path| File.directory?(path) && File.readable?(path) && !path.start_with?('.') }
    end

    def reinit_collection(collection_name, path_to_scan, miniature_size_string, full_size_string)
      # reinitialising: get the tree of existing collection data (directory/file), get the new collection data (directory/file)
      # remove entirely directories that are not present in old, recreate directories and files that are not yet created
      source_galleries = read_directories_from(path_to_scan)
      existing_galleries = read_directories_from(collection_dir(collection_name))

      source_mapped = Hash[source_galleries.map {|dir| [gallery_dir(collection_name, dir.split('/').last), dir]}]

      to_add = (source_mapped.keys - existing_galleries).map {|dir| source_mapped[dir]}
      to_remove = existing_galleries - source_mapped.keys

      # delete recursively the gallery data dir and the public images dir for that gallery
      to_remove.each do |full_path|
        gallery_name = full_path.split('/').last
        FileUtils.rm_rf(gallery_dir(collection_name, gallery_name))
        FileUtils.rm_rf(public_images_dir(collection_name, gallery_name))
      end
      to_add.each do |full_path|
        accept_gallery_dir(full_path, path_to_scan, collection_name, miniature_size_string, full_size_string)
      end

    end

    def init_collection(collection_name, path_to_scan, miniature_size_string, full_size_string)
      # get galleries - one directory per gallery
      gallery_dirs = read_directories_from(path_to_scan)
      ensure_collection_dir collection_name

      gallery_dirs.each do |full_dir_path|
        accept_gallery_dir(full_dir_path, path_to_scan, collection_name, miniature_size_string, full_size_string)
      end
    end

    def accept_gallery_dir(full_dir_path, path_to_scan, collection_name, miniature_size_string, full_size_string)
      dir = full_dir_path.split('/').last
      # prepare gallery info
      gallery_info = {'title' => dir.to_s.human_readable, 'date' => File.mtime(full_dir_path).strftime('%Y-%m-%d %H:%M:%S')}
      ensure_gallery_dir(collection_name, dir)
      File.write(gallery_file(collection_name, dir), YAML.dump(gallery_info))

      # process image files found in the gallery
      images = Dir.glob(File.join(path_to_scan, dir,'*.*')).select { |path| file_supported?(path) && !path.start_with?('.') }
      images.each do |full_path|
        accept_image_file(full_path, collection_name, path_to_scan, dir, miniature_size_string, full_size_string)
      end
    end

    def accept_image_file(full_path, collection_name, collection_path, gallery_name, miniature_size_string, full_size_string)
      dir = gallery_name
      path_to_scan = collection_path
      full_filename = File.basename(full_path)
      {image_miniature_file(collection_name, dir, full_filename) => miniature_size_string, image_full_file(collection_name, dir, full_filename) => full_size_string}.each do |file, size|
        # create image miniature and "full size"
        _out, _err, _status = Open3.capture3(
          "magick",
          File.join(path_to_scan, dir, full_filename),
          "-resize", size,
          file
        )
      end
      just_filename = File.basename(full_filename, '.*')
      file_info = {
        'filename' => full_filename,
        'title' => just_filename,
        'date' => File.mtime(full_path).strftime('%Y-%m-%d %H:%M:%S'),
      }
      ensure_image_data_dir(collection_name, dir, just_filename)

      # image data file
      File.write(image_data_file(collection_name, dir, just_filename), YAML.dump(file_info))
    end

    def update_setup(config)
      %w{collections public public/images}.each {|dir| Dir.mkdir(dir) unless Dir.exist?(dir) }
      File.write(MAIN_CONFIG_FILE, YAML.dump(config))
    end

    def update_collection(name, data)
      ensure_collection_dir(name)
      File.write(collection_file(name), YAML.dump(data))
    end

    def update_gallery(collection, name, data)
      ensure_collection_dir(collection)
      ensure_gallery_dir(collection, name)
      File.write(gallery_file(collection, name), YAML.dump(data))
    end

    def update_image(collection, gallery, name, data)
      ensure_collection_dir(collection)
      ensure_gallery_dir(collection, gallery)
      ensure_image_data_dir(collection, gallery, name)
      File.write(image_data_file(collection, gallery, name), YAML.dump(data))
    end

    def file_supported?(path)
      return false unless File.file?(path)
      output, error, status = Open3.capture3('magick', 'identify', '-format', '%m', path)
      status.success? && %w[JPEG PNG].include?(output.lines.first&.strip)
    rescue Errno::ENOENT
      false
    end
  end

end
