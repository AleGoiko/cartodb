# encoding: utf-8
require_relative './ogr2ogr'
require_relative './exceptions'
require_relative './format_linter'
require_relative './csv_normalizer'
require_relative './shp_normalizer'
require_relative './json2csv'
require_relative './xlsx2csv'
require_relative './xls2csv'
require_relative './georeferencer'
require_relative '../importer/post_import_handler'
require_relative './geometry_fixer'
require_relative './typecaster'
require_relative 'importer_stats'

module CartoDB
  module Importer2
    class Loader
      SCHEMA            = 'cdb_importer'
      TABLE_PREFIX      = 'importer'
      NORMALIZERS       = [FormatLinter, CsvNormalizer, Xls2Csv, Xlsx2Csv, Json2Csv]

      # Files matching any of this regexps will be forcibly normalized
      # @see services/datasources/lib/datasources/search/twitter.rb -> table_name
      FORCE_NORMALIZER_REGEX = [
        /^twitter_(.*)\.csv/
      ]
      DEFAULT_ENCODING  = 'UTF-8'

      def self.supported?(extension)
        !(%w{ .tif .tiff .sql }.include?(extension))
      end

      def initialize(job, source_file, layer=nil, ogr2ogr=nil, georeferencer=nil)
        self.job            = job
        self.source_file    = source_file
        self.layer          = 'track_points' if source_file.extension =~ /\.gpx/
        self.ogr2ogr        = ogr2ogr
        self.georeferencer  = georeferencer
        self.options        = {}
        @post_import_handler = nil
        @importer_stats = ImporterStats.instance
      end

      def set_importer_specs(importer_stats)
        @importer_stats = importer_stats
      end

      def run(post_import_handler_instance=nil)
        @importer_stats.timing('loader') do

          @post_import_handler = post_import_handler_instance

          @importer_stats.timing('normalize') do
            normalize
          end

          job.log "Detected encoding #{encoding}"
          job.log "Using database connection with #{job.concealed_pg_options}"

          @importer_stats.timing('ogr2ogr') do
            run_ogr2ogr
          end

          @importer_stats.timing('post_ogr2ogr_tasks') do
            post_ogr2ogr_tasks
          end

          self
        end
      end

      def streamed_run_init
        normalize
        job.log "Detected encoding #{encoding}"
        job.log "Using database connection with #{job.concealed_pg_options}"
        job.log "Running in append mode"
        run_ogr2ogr
      end

      def streamed_run_continue(new_source_file)
        @ogr2ogr.filepath = new_source_file.fullpath
        run_ogr2ogr(append_mode=true)
      end

      def streamed_run_finish(post_import_handler_instance=nil)
        @post_import_handler = post_import_handler_instance

        post_ogr2ogr_tasks
      end

      def post_ogr2ogr_tasks
        georeferencer.mark_as_from_geojson_with_transform if post_import_handler.has_transform_geojson_geom_column?

        job.log 'Georeferencing...'
        georeferencer.run
        job.log 'Georeferenced'

        if post_import_handler.has_fix_geometries_task?
          job.log 'Fixing geometry...'
          # At this point the_geom column is renamed
          GeometryFixer.new(job.db, job.table_name, SCHEMA, 'the_geom', job).run
        end
      end

      def normalize
        converted_filepath = normalizers_for(source_file.extension)
          .inject(source_file.fullpath) { |filepath, normalizer_klass|
            normalizer = normalizer_klass.new(filepath, job)

            FORCE_NORMALIZER_REGEX.each { |regex|
              normalizer.force_normalize if regex =~ source_file.path
            }

            normalizer.run
                      .converted_filepath
          }
        layer = source_file.layer
        @source_file = SourceFile.new(converted_filepath)
        @source_file.layer = layer
        self
      end

      def ogr2ogr
        @ogr2ogr ||= Ogr2ogr.new(
          job.table_name, @source_file.fullpath, job.pg_options, @source_file.layer, ogr2ogr_options
        )
      end

      def ogr2ogr_options
        ogr_options = { encoding: encoding }
        unless options[:ogr2ogr_binary].nil?
          ogr_options.merge!(ogr2ogr_binary: options[:ogr2ogr_binary])
        end
        unless options[:ogr2ogr_csv_guessing].nil?
          ogr_options.merge!(ogr2ogr_csv_guessing: options[:ogr2ogr_csv_guessing])
        end
        unless options[:quoted_fields_guessing].nil?
          ogr_options.merge!(quoted_fields_guessing: options[:quoted_fields_guessing])
        end

        if source_file.extension == '.shp'
          ogr_options.merge!(shape_encoding: shape_encoding)
        end
        ogr_options
      end

      def encoding
        normalizer = [ShpNormalizer, CsvNormalizer].find { |normalizer|
          normalizer.supported?(source_file.extension)
        }
        return DEFAULT_ENCODING unless normalizer
        normalizer.new(source_file.fullpath, job).encoding
      end

      def shape_encoding
        normalizer = [ShpNormalizer].find { |normalizer|
          normalizer.supported?(source_file.extension)
        }
        return nil unless normalizer
        normalizer.new(source_file.fullpath, job).shape_encoding
      end

      def georeferencer
        @georeferencer ||= Georeferencer.new(job.db, job.table_name, SCHEMA, job, geometry_columns)
      end

      def post_import_handler
        @post_import_handler ||= PostImportHandler.new
      end

      def typecaster
        @typecaster ||= Typecaster.new(job.db, job.table_name, SCHEMA, job, ['postedtime'])
      end

      def geometry_columns
        ['wkb_geometry'] if @source_file.extension == '.shp'
      end

      def valid_table_names
        [job.table_name]
      end

      def normalizers_for(extension)
        NORMALIZERS.find_all { |klass|
          klass.supported?(extension)
        }
      end

      def osm?(source_file)
        source_file.extension =~ /\.osm/
      end

      attr_accessor   :source_file, :options

      private

      attr_writer     :ogr2ogr, :georeferencer
      attr_accessor   :job, :layer

      def run_ogr2ogr(append_mode=false)
        ogr2ogr.run(append_mode)

        # too verbose in append mode
        unless append_mode
          job.log "ogr2ogr call:      #{ogr2ogr.command}"
          job.log "ogr2ogr output:    #{ogr2ogr.command_output}"
          job.log "ogr2ogr exit code: #{ogr2ogr.exit_code}"
        end

        raise InvalidGeoJSONError.new(job.logger) if ogr2ogr.command_output =~ /nrecognized GeoJSON/
        raise MalformedCSVException.new(job.logger) if ogr2ogr.command_output =~ /tables can have at most 1600 columns/

        if ogr2ogr.exit_code != 0
          # OOM
          if ogr2ogr.exit_code == 256 && ogr2ogr.command_output =~ /calloc failed/
            raise FileTooBigError.new(job.logger)
          end
          # Could be OOM, could be wrong input
          if ogr2ogr.exit_code == 35584 && ogr2ogr.command_output =~ /Segmentation fault/
            raise LoadError.new(job.logger)
          end
          if ogr2ogr.exit_code == 256 && ogr2ogr.command_output =~ /Unable to open(.*)with the following drivers/
            raise UnsupportedFormatError.new(job.logger)
          end
          raise LoadError.new(job.logger)
        end
      end
    end
  end
end

