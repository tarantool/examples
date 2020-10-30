This example runs a cluster of 3 tarantool instances with leader election
enabled and one router, which generates simple requests and relays them on the
current leader. Once the leader disappears, the router waits till the remaining
instances finish leader election and continues relaying data on a new leader.

To run an example:
```
mkdir 1
mkdir 2
mkdir 3
ln -s election.lua ./1/election1.lua
ln -s election.lua ./2/election2.lua
ln -s election.lua ./3/election3.lua
cd 1 && tarantool election1.lua && cd ..
cd 2 && tarantool election2.lua && cd ..
cd 3 && tarantool election3.lua && cd ..
tarantool router.lua
```
