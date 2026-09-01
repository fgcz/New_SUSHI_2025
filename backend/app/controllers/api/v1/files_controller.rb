module Api
  module V1
    # Read-only gStore browser. Legacy exposes the same tree through its
    # /import/*dataset page; this serves it as data.
    #
    # Two rules make it safe to point at a shared filesystem: the resolved path
    # must stay under the configured gStore directory, and its first segment must
    # be a project directory the caller is authorized for. The root therefore
    # lists exactly the caller's own projects, never every project on disk.
    class FilesController < BaseController
      # GET /api/v1/files?path=p1001/FastQC_2026-01-15
      def index
        requested = normalize(params[:path])

        return render_root if requested.empty?

        number = project_number_of(requested)
        if number.nil? || !authorized_project_numbers.map(&:to_i).include?(number)
          return render json: { error: 'Path not accessible' }, status: :forbidden
        end

        real = resolve_within_gstore(requested)
        return render json: { error: 'Path not found' }, status: :not_found unless real

        items = entries(real)
        render json: {
          currentPath: requested,
          parentPath: parent_of(requested),
          totalItems: items.size,
          items: items
        }
      end

      private

      def render_root
        items = authorized_project_numbers.map { |number| "p#{number}" }.filter_map do |dir|
          path = File.join(gstore_root, dir)
          next unless File.directory?(path)

          { name: dir, type: 'folder', lastModified: mtime(path), size: nil }
        end

        render json: {
          currentPath: '/',
          parentPath: nil,
          totalItems: items.size,
          items: items.sort_by { |item| item[:name] }
        }
      end

      def entries(dir)
        Dir.children(dir).filter_map do |name|
          path = File.join(dir, name)
          next if File.symlink?(path) && !File.exist?(path)

          directory = File.directory?(path)
          {
            name: name,
            type: directory ? 'folder' : 'file',
            lastModified: mtime(path),
            size: directory ? nil : File.size(path)
          }
        end.sort_by { |item| [item[:type] == 'folder' ? 0 : 1, item[:name]] }
      rescue SystemCallError
        []
      end

      def mtime(path)
        File.mtime(path).strftime('%Y-%m-%d %H:%M:%S')
      rescue SystemCallError
        nil
      end

      def normalize(path)
        path.to_s.gsub(%r{\A/+|/+\z}, '')
      end

      def parent_of(path)
        parts = path.split('/').reject(&:empty?)
        return nil if parts.size <= 1

        parts[0..-2].join('/')
      end

      # 'p35611/o35755_Fastqc' -> 35611
      def project_number_of(path)
        first = path.split('/').first.to_s
        return nil unless first =~ /\Ap(\d+)\z/

        Regexp.last_match(1).to_i
      end

      # Resolves symlinks and '..' before checking containment, so a path that
      # climbs out of gStore is refused however it is spelled.
      def resolve_within_gstore(path)
        real = File.realpath(File.join(gstore_root, path))
        return nil unless File.directory?(real)
        return nil unless real == gstore_root || real.start_with?("#{gstore_root}/")

        real
      rescue SystemCallError
        nil
      end

      def gstore_root
        @gstore_root ||= begin
          dir = SushiConfigHelper.gstore_dir
          File.realpath(dir)
        rescue SystemCallError
          File.expand_path(dir)
        end
      end
    end
  end
end
