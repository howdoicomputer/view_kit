require 'open-uri'
require 'contracts'
require 'zlib'
require 'pathname'

# Top level module.
#
module ViewKit
  # A module to help create files.
  #
  module FileHelper
    extend self

    include Contracts::Core
    include Contracts::Builtin

    # Generate a file of arbitrary size.
    #
    # @params path [String] The path to the file.
    # @params size [Integer] The size of the file in megabytes.
    # @params name [String] The name of the file.
    # @return [String] The path of the file.
    #
    Contract KeywordArgs[path: String, size: Num, name: String] => String
    def generate_file(path:, size:, name:)
      size *= 1_048_576

      file_size = 0
      string = 'abcdefghijklmnopqrstuvwxyz123456'

      File.open("#{path}/#{name}", 'w') do |file|
        while file_size < size
          file.write(string)
          file_size += string.size
        end
      end

      "#{path}/#{name}"
    end

    # Fetches a file from a remote location.
    #
    # @params url [String] The URL to pull from.
    # @params file_path [String] The name of the file to pull to.
    # @return [String] The path of the file.
    #
    Contract KeywordArgs[url: Num, file_name: String] => String
    def fetch_file(url:, file_name:)
      open(url) do |content|
        File.open(file_name, 'w') do |file|
          file.puts content.read
        end
      end
    end

    # Compress file *before* splitting it into chunks to be stored into
    # memcache.
    #
    # @param file_path [String] The path to the file that is to be compressed.
    # @return [String] A compressed string.
    #
    Contract KeywordArgs[file_path: String] => String
    def compress_file(file_path:)
      file = File.read(file_path)
      Zlib::Deflate.deflate(file)
    end

    # Chunk a single file into 1 MB segments and then store those segments in
    # memory as an array.
    #
    # NOTE: String.unpack reference table refers to 'a' as an unterminated
    # binary string.
    #
    # @param content [String] The 'stuff' to chunkify.
    # @param chunk_size [Integer] The size of the chunks.
    # @return [Array<String>] An array of chunks.
    #
    Contract KeywordArgs[content: String, chunk_size: Integer] => Array
    def chunkify(content:, chunk_size:)
      return [content] if content.size < chunk_size
      content.unpack("a#{chunk_size}" * (content.size / chunk_size))
    end
  end
end
