# frozen_string_literal: true

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
      [public_images_dir(collection, gallery), 'mini.'+file].join('/')
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
      Dir.glob(File.join(image_data_dir(collection, gallery, image), 'comment.*.yml')).collect { |path| YAML.load_file(path) rescue nil }.compact
    end

    def gallery_details(collection, gallery)
      Dir.glob(File.join(gallery_dir(collection, gallery), '*.yml'))
         .collect { |path| File.basename(path, '.*') }
         .collect do |image_name|

        details = { 'data_file' => image_data_file(collection, gallery, image_name), 'data_name' => image_name }
        details.data = YAML.load_file(image_data_file(collection, gallery, image_name))
        details.comments = image_comments(collection, gallery, image_name)
        details.reactions = image_reactions(collection, gallery, image_name)
        details.file_path = {'miniature' => image_miniature_file(collection, gallery, details.data.filename), 'full' => image_full_file(collection, gallery, details.data.filename)}
        details.url_path = {'miniature' => image_miniature_url(collection, gallery, details.data.filename), 'full' => image_full_url(collection, gallery, details.data.filename)}
        details
      end
    end

    def reinit_collection(collection_name, path_to_scan, miniature_size_string, full_size_string)
      warn 'this has not been implemented yet'
    end

    def init_collection(collection_name, path_to_scan, miniature_size_string, full_size_string)
      # get galleries - one directory per gallery
      gallery_dirs = Dir.glob(File.join(path_to_scan, '*')).select { |path| File.directory?(path) && File.readable?(path) && !path.start_with?('.') }.collect { |path| path.split('/').last }
      ensure_collection_dir collection_name

      gallery_dirs.each do |dir|
        # prepare gallery info
        gallery_info = {'title' => dir.to_s.human_readable}
        ensure_gallery_dir(collection_name, dir)
        File.write(gallery_file(collection_name, dir), YAML.dump(gallery_info))

        # process image files found in the gallery
        images = Dir.glob(File.join(path_to_scan, dir,'*.*')).select { |path| file_supported?(path) && !path.start_with?('.') }.collect { |path| File.basename(path) }
        images.each do |full_filename|
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
          }
          ensure_image_data_dir(collection_name, dir, just_filename)

          # image data file
          File.write(image_data_file(collection_name, dir, just_filename), YAML.dump(file_info))
        end

      end
    end

    def update_setup(config)
      %w{collections public public/images}.each {|dir| Dir.mkdir(dir) unless Dir.exist?(dir) }
      File.write(MAIN_CONFIG_FILE, YAML.dump(config))
    end

    def update_collection(name, data)
      ensure_collection_dir(name)
      File.write(collection_file(name), YAML.dump(data))
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
