This example runs a cluster of 3 tarantool instances with leader election
enabled and one router, which generates simple requests and relays them on the
current leader. Once the leader disappears, the router waits till the remaining
instances finish leader election and continues relaying data on a new leader.

To run an example open 4 terminal windows and issue
1:
```
tarantool election.lua 1
```
2:
```
tarantool election.lua 2
```
3:
```
tarantool election.lua 3
```
4:
```
tarantool router.lua
```
