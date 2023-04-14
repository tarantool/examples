This is a showcase repository where you can find demo applications and
usage examples for [Tarantool](https://www.tarantool.io/) and its
derivatives.

The repo is organized by directories:

* `cache` contains an application for storing user accounts.
  Here we implement caches of different types:

  * a simple cache with LRU (least-recently-used) eviction algorithm
  * a cache for a MySQL storage
  * a cache for a Tarantool disk storage (based on Tarantool's Vinyl engine)

  This app is based on the [opensource](https://www.tarantool.io/en/developers/)
  version of Tarantool and the
  [Tarantool Cartridge](https://www.tarantool.io/en/cartridge/) framework.

* `profile-storage` contains an application for storing user profiles.
  Here, on top of the basic create/change/read/delete features, we implement
  user password check to disallow profile-related operations for anyone except
  the user.

  Again, this app is based on the [opensource](https://www.tarantool.io/en/developers/)
  version of Tarantool and the
  [Tarantool Cartridge](https://www.tarantool.io/en/cartridge/) framework.

* `tdg` contains examples of using
  [Tarantool Data Grid](https://www.tarantool.io/en/datagrid/):

  1. Uploading data
  2. Uploading data via a connector
  3. Creating a service
  4. Changing the data model
  5. Using affinities to process related data on a single node
  6. Getting started with Kafka and troubleshooting Kafka connection

  These examples are based on the
  [enterprise](https://www.tarantool.io/en/product/enterprise/)
  version of Tarantool.

* `cookbook` contains code snippets for typical cases:

  * [batch processing](https://github.com/tarantool/examples/blob/master/cookbook/space/in_batches.lua)
  * [altering the field type](https://github.com/tarantool/examples/blob/master/cookbook/migrations/alter_field_type.lua)
  * and more snippets to arrive...

Feel free to browse, try, and contribute!

Please submit an issue here if you have any problems with the demos.
