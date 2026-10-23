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
      Hash[available_collections.collect { |entry| [entry, (YAML.load_file(collection_file(entry)) rescue nil)] }.reject { |a| a[1].nil? }.filter { |a| user.admin || a[1].password.nil? || a[1].visitors.any? {|v| v.login == user.login} }]
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

    def collection_file(name)
      ('collections/' + name + '/.collection.yml').freeze
    end
    def collection_dir(name)
      'collections/' + name
    end
    def ensure_collection_dir(name)
      path = collection_dir(name)
      Dir.mkdir(path) unless Dir.exist?(path)
    end

    def gallery_file(collection, gallery)
      ['collections', collection, gallery, '.gallery.yml'].join('/')
    end
    def gallery_dir(collection, gallery)
      ['collections', collection, gallery].join('/')
    end
    def ensure_gallery_dir(collection, gallery)
      path = gallery_dir(collection, gallery)
      Dir.mkdir(path) unless Dir.exist?(path)
    end

    def image_data_file(collection, gallery, file)
      ['collections', collection, gallery, file + '.yml'].join('/')
    end
    def image_miniature_file(collection, gallery, file)
      ['collections', collection, gallery, 'mini.'+file].join('/')
    end
    def image_full_file(collection, gallery, file)
      ['collections', collection, gallery, 'full.'+file].join('/')
    end

    def reinit_collection(collection_name, path_to_scan, miniature_size_string)
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
        images = Dir.glob(File.join(path_to_scan, dir,'*.*')).select { |path| file_supported?(path) && !path.start_with?('.') }.collect { |path| path.split('/').last }
        images.each do |filename|
          {image_miniature_file(collection_name, dir, filename) => miniature_size_string, image_full_file(collection_name, dir, filename) => full_size_string}.each do |file, size|
            # create image miniature and "full size"
            _out, _err, _status = Open3.capture3(
              "magick",
              File.join(path_to_scan, dir, filename),
              "-resize", size,
              file
            )
            end
          file_info = {'title' => filename.to_s, 'reactions' => [], 'comments' => []}

          # image data file
          File.write(image_data_file(collection_name, dir, filename), YAML.dump(file_info))
        end

      end
    end

    def update_setup(config)
      Dir.mkdir('collections') unless Dir.exist?('collections')
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
