Hey, guys!

Anyway, so this is my semi-cheating submission for storing a file into Memcached.

This is somewhat of an improvement of [this](https://gist.github.com/giampaolo/7e8a1bba6a10940077481110684e637d).

Assumptions:

1. That the max size for a Memcache key's value hasn't been increased beyond 1MB.
2. That the files being stored are ASCII text.

So breaking a file into chunks was a pretty fundamental approach - not much I can do about changing that - but there were a few ways I thought I could improve what is linked in the above gist.

## Where to Look

Relevant code is mostly located:

* `lib/view_kit/file_helper.rb` - Generating files, compressing files, fetching files from a URL, etc.
* `lib/view_kit/memcached_helper.rb` - Putting and getting files into/from memcache.
* `spec/view_kit_spec.rb` - Tests.

## File Uniqueness

Anywhosal, the Python code doesn't account for file name uniqueness. That is, if you have two files named foobar then the identical key prefixes may cause storage and retrieval problems as two separate instances of the code run simultaneously - and that's no bueno. To address any name collision edge cases, I instead adopted a key/value structure that looks like this:

```
{
  key: file_name:MD5:index_of_chunk,
  value: chunk
}
```

In fact, Dalli has a built in `namespace` option that can be supplied when you instantiate the client. In regards to Memcache and Dalli, a namespace is just a fancy prefix that is added onto every key. This meant that I could 'reserve' a namespace for every file stored... like so:

```
@memcached_options[:namespace] = "#{file_name}:#{file_digest}"
dalli_client = Dalli::Client.new(@memcached_address, @memcached_options)
```

## Validation

The original Python code used `assert` to check to see if the file stored and the file retrieved had the same lengths and the same characters. However, the file was populated with only a single character that repeated until the size was N length... so that made the assertion pretty easy to write. In order to make validation a teensy bit more robust, I calculated an MD5 digest for a file *pre-compression* and then compared that digest to the reassembled file after it came out of the cache.

## Compression

Iterating over file contents and storing it is pretty straightforward way of solving this problem and I can see why it was done in a thirty minut session. However, what is more efficient is compressing a file *before* it is split into chunks. In fact, using the file in the Python gist, only one key would be needed if compression was used because a single character repeating endlessly could easily be represented as two bites (character to whatever power).

When the chunks are retrieved from the cache, decompression occurs before digests are compared.

## Other Notes

I tried fumbling around with stuff like unicode and MIME types. Eh, nobody ain't got time for that. ASCII is good enough.

In my code I'm using [Ruby contracts](https://github.com/egonSchiele/contracts.ruby). Contracts are kind of like `assert` on steroids. They're a way to codify functions signatures in a fashion that makes Ruby somewhat strictly typed. Contracts can't really be used in production because they slow down Ruby code tremendously, but they do help me catch runtime errors during testing.

## Things to Do/Improve

* Eh, I was lazy and, instead of iterating until all keys storing file chunks are gone... I pass in the known amount of chunks that are returned from the `put_file` function. This was mostly so I could use the `Dalli::Client.get_multi` function.
* Monkeypatching the `Dalli::Client` class to include the `get_file` and `put_file` functions may have been cleaner.
* Figuring out unicode and other string types.
* The `get_file` and `put_file` methods are kinda big-ish and can be broken down into smaller chunks for readability/organizational purposes.
* Dalli is EventMachine compatible. While I can't do much for IO bound performance (I think), making the network calls to Dalli asynchronous could be neato burrito.
* Some of the code could be written more tersly
* Account for larger value sizes. While I don't know the finer details of tuning Memcache, it'd be neat to have the code take in a max value size and then calculate the size of the chunks accordingly.

## Testing

Tests are written in RSpec. There could be more. They validate that a random file is generated, that it's stored in Memcache, and that the retrieved file matches the one that is local.

`bundle exec rspec`

Output:

```
✔︎ view_kit (master) bundle exec rspec

ViewKit
  has a version number
  should generate a file
  should split a file into chunks
  should store a file into memcache
  should raise an error if the file is already stored
  should retrieve a file from memcache

Finished in 0.27045 seconds (files took 0.06822 seconds to load)
6 examples, 0 failures
```

I tested against whatever Memcache version is in Arch Linux's repositories and against CouchBase with the Memcache interface enabled. Tested both on Windows and Linux.

---
