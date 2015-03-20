require 'fileutils'
require 'pathname'
require 'yaml'

require 'thor'
require 'listen'

require 'versacommerce/cli/simple_logger'
require 'versacommerce/theme_api_client'

module Versacommerce
  module CLI
    class Theme < Thor
      class_option :authorization
      class_option :config
      class_option :verbose, type: :boolean

      desc 'download', 'Downloads a complete Theme from the Theme API.'
      option :path, default: Pathname.pwd.join('theme')
      def download
        ensure_authorization!

        path = Pathname.new(options[:path]).expand_path
        logger.info('Downloading Theme to %s' % path)

        client.files(recursive: true).each do |file|
          logger.debug('Downloading %s' % file.path)
          file.reload_content
          file_path = path.join(file.path)
          FileUtils.mkdir_p(file_path.parent)
          File.open(file_path, 'wb') { |f| f.write(file.content) }
        end

        logger.success('Finished downloading Theme')
      end

      desc 'watch', 'Watches a directory and pushes file changes to the Theme API.'
      option :path, default: Pathname.pwd
      def watch
        theme_path = Pathname.new(options[:path]).expand_path
        logger.info 'Watching %s' % theme_path

        listener = Listen.to(theme_path) do |modified, added, removed|
          removed.each { |absolute_path| delete_file(theme_path, absolute_path) }

          modified.concat(added).each do |absolute_path|
            delete_file(theme_path, absolute_path)
            add_file(theme_path, absolute_path)
          end
        end

        listener.start
        sleep
      rescue SystemExit, Interrupt
        logger.info('Stopped watching')
        exit
      end

      private

      def add_file(theme_path, absolute_path)
        relative_path = Pathname.new(absolute_path).relative_path_from(theme_path)
        file = client.files.build(path: relative_path, content: File.read(absolute_path))

        if file.valid?
          logger.debug('Trying to add %s' % relative_path)

          if file.save
            logger.success('Added %s' % relative_path)
          else
            logger.error('Could not add %s:' % relative_path)
            file.errors.full_messages.each { |msg| logger.error('  %s' % msg) }
          end
        else
          logger.error('Could not add %s:' % relative_path)
          file.errors.full_messages.each { |msg| logger.error('  %s' % msg) }
        end
      end

      def delete_file(theme_path, absolute_path, log: true)
        relative_path = Pathname.new(absolute_path).relative_path_from(theme_path)
        client.files.delete(relative_path)
      rescue Versacommerce::ThemeAPIClient::Fetcher::RecordNotFoundError
      end

      def client
        @client ||= ThemeAPIClient.new(authorization: authorization)
      end

      def ensure_authorization!
        unless authorization
          puts 'Could not find authorization.'
          exit 1
        end
      end

      def authorization
        options[:authorization] || explicit_config['authorization'] || ENV['THEME_AUTHORIZATION'] || implicit_config['authorization']
      end

      def explicit_config
        @explicit_config ||= options[:config] ? YAML.load_file(options[:config]) : {}
      end

      def implicit_config
        @implicit_config ||= begin
          config = Pathname.new('~/.config/versacommerce/cli/config.yml').expand_path
          config.file? ? YAML.load_file(config) : {}
        end
      end

      def logger
        @logger ||= SimpleLogger.new(options[:verbose])
      end
    end
  end
end
