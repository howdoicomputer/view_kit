require 'spec_helper'
require 'fileutils'

RSpec.describe ViewKit do
  before(:all) do
    @expected_size = 10 * 1_048_576
    @file = ViewKit::FileHelper.generate_file(
      path: Dir.tmpdir,
      size: 10,
      name: 'foobar.txt'
    )
    @client = ViewKit::MemcachedHelper.new(
      memcached_address: 'localhost:11211',
      memcached_options: { compress: true }
    )
  end

  it 'has a version number' do
    expect(ViewKit::VERSION).not_to be nil
  end

  it 'should generate a file' do
    file_size = File.stat(@file).size
    expect(file_size).to eq @expected_size
  end

  it 'should split a file into chunks' do
    content = File.open(@file, 'rb').read
    chunks = ViewKit::FileHelper.chunkify(
      content: content,
      chunk_size: (1_048_576 - 4096)
    )

    expect(chunks).to be_a(Array)
    expect(chunks.size).to be > 0
  end

  it 'should store a file into memcache' do
    operation_metadata = @client.put_file(file_path: @file)
    expect(operation_metadata[:number_of_chunks]).to eq 1
  end

  it 'should raise an error if the file is already stored' do
    expect { @client.put_file(file_path: @file) }.to raise_error(RuntimeError)
  end

  it 'should retrieve a file from memcache' do
    file_path = ViewKit::FileHelper.generate_file(
      path: Dir.tmpdir,
      size: 10,
      name: 'foobar1.txt'
    )

    put_meta = @client.put_file(file_path: file_path)

    get_meta = @client.get_file(
      memcached_namespace: "foobar.txt:#{put_meta[:file_digest]}",
      number_of_chunks: put_meta[:number_of_chunks],
      file_name: 'foobar2.txt',
      destination_path: Dir.tmpdir
    )

    expect(put_meta[:file_digest]).to eq get_meta[:file_digest].to_s
  end

  after(:all) do
    dalli_client = Dalli::Client.new('localhost')
    dalli_client.flush

    ['foobar.txt', 'foobar1.txt', 'foobar2.txt'].each do |f|
      File.delete("#{Dir.tmpdir}/#{f}")
    end
  end
end
