require 'contracts'
require 'dalli'
require 'digest'
require 'zlib'

# Helper functions for doing memcached stuff.
#
module ViewKit
  # Methods for storing files into Memcached
  #
  class MemcachedHelper < Dalli::Client
    include Contracts::Core
    include Contracts::Builtin

    attr_reader :memcached_address
    attr_reader :memcached_options

    def initialize(memcached_address:, memcached_options:)
      @memcached_address = memcached_address
      @memcached_options = memcached_options
    end

    # Store a file in memcache. The file gets a namespace that is based on
    # the file name. Each chunk of the file gets a key that is based on the
    # index for the chunk as it sits within an array of chunks.
    #
    # NOTE: Taking into account Dalli's namespacing, full naming convention will
    # render a key/value pair like so:
    #
    #   {
    #     key:   #{file_name}:#{file_digest}:#{index_integer},
    #     value: #{1MB_chunk_of_file_content}
    #   }
    #
    # @param file_path [String]
    # @return [Hash] File metadata.
    #
    Contract KeywordArgs[file_path: String] => Hash
    def put_file(file_path:)
      compressed_file_content = ViewKit::FileHelper.compress_file(
        file_path: file_path
      )

      file_digest = Digest::MD5.file(file_path)

      chunks = ViewKit::FileHelper.chunkify(
        content: compressed_file_content, chunk_size: (1_048_576 - 4096)
      )

      file_name = Pathname.new(file_path).basename

      @memcached_options[:namespace] = "#{file_name}:#{file_digest}"
      dalli_client = Dalli::Client.new(@memcached_address, @memcached_options)

      raise 'File *looks* like it is already stored.' unless
        dalli_client.get(0).nil?

      chunks.each_with_index do |chunk, index|
        dalli_client.set(index, chunk)
      end

      {
        local_path_of_file_stored: file_path,
        number_of_chunks: chunks.size,
        file_digest: file_digest,
        memcached_namespace: @memcached_options[:namespace]
      }
    end

    # Grab a file from memcache. Every file will have its own namespace and
    # every namespace will consist of only the segments the file has been
    # separated into.
    #
    # @param memcached_namespace [String] The namespace that designates file
    # identitiy.
    # @param number_of_chunks [Integer] The number of chunks the file has.
    # @param digest [String] An MD5 sum used to verify that the contents are OK.
    # @param path [String] The destination path for the pulled file.
    # @param file_name [String] Override the name found in the namespace.
    # @return [Hash] File metadata.
    #
    Contract KeywordArgs[
              memcached_namespace: String,
              number_of_chunks: Num,
              destination_path: String,
              file_name: String,
            ] => Hash
    def get_file(memcached_namespace:, number_of_chunks:, destination_path:, file_name: nil)
      @memcached_options[:namespace] = memcached_namespace
      dalli_client = Dalli::Client.new(@memcached_address, @memcached_options)

      keys = (0..number_of_chunks)
      file_chunks = dalli_client.get_multi(*keys)
      file_content = []

      file_chunks.each { |key, _| file_content << file_chunks[key] }
      complete_file = Zlib::Inflate.inflate(file_content.join)

      file_name = memcached_namespace.split(':').first unless file_name
      full_path = "#{destination_path}/#{file_name}"
      File.open(full_path, 'w') do |file|
        file.write(complete_file)
      end

      {
        path: full_path,
        file_digest: Digest::MD5.file(full_path)
      }
    end
  end
end
