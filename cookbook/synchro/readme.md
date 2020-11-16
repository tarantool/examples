# Synchronous replication

This example shows a two instance setup with one synchronous master and one replica.
The cluster has a synchronous space called `banking_data`. Insertions to the space
succeed only when the replica is running and receives updates from the master.

## Disclaimer
### Synchronous replication is currently in beta state. You may get the latest tarantool version [here](https://www.tarantool.io/en/download/)
### If you find any issues, please submit a bug [here](https://github.com/tarantool/tarantool/issues)

## How to run
We have two instance files, `master.lua` and `replica.lua`.
To run the cluster, first create working directories for both tarantool instances:
```console
mkdir tnt1 && cp master.lua ./tnt1
```
```console
mkdir tnt2 && cp replica.lua ./tnt2
```
Now start both instances:
```
cd tnt1 && tarantool master.lua
```
```
cd tnt2 && tarantool.replica.lua
```

A synchronous space `banking_data` is created on cluster bootstrap.
```
tarantool> box.space.banking_data.is_sync
---
- true
...
```
You may insert something to it. If both master and replica are alive and well,
the insertion will succeed:
```
tarantool> box.space.banking_data:insert{1}
---
- [1]
...
```

Now stop the replica and try to insert something else to the synchronous space:
```
tarantool> box.space.banking_data:insert{2}
---
- error: Quorum collection for a synchronous transaction is timed out
...
```
Master won't commit transactions unless a quorum of instances including itself
receive the transactions. In this example quorum is set to 2, so replica must
be alive for the master to succeed in insertion.

## Configuration
`box.cfg{replication_synchro_quorum=2}` - a number of instances that have to receive
the transaction for it to be committed

`box.cfg{replication_synchro_timeout=5}` - quorum is collected during this timeout.
If master doesn't receive transaction confirmation from a quorum of instances during
this timeout, the transaction is rolled back.
