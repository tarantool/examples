# What is this?
This example demonstrates leader election set up and a simple failover
script.
This example runs a cluster of 3 tarantool instances with leader election
enabled and one router, which generates simple requests and relays them on the
current leader. Once the leader disappears, the router waits till the remaining
instances finish leader election and continues relaying data on a new leader.

All the insertions are done to a synchronous space named `test`.

## Disclaimer

### Synchronous replication and leader election are currently in beta state. You may get the latest tarantool version [here](https://www.tarantool.io/en/download/)
### If you face any issues with these features, please file a bug [here](https://github.com/tarantool/tarantool/issues/)

## How to run
To run an example open 4 terminal windows and issue the following commands in
corresponding terminals:
1:
```
tarantool election.lua 1
```
This'll create a directory `./tnt1` and run the first tarantool instance there.

2:
```
tarantool election.lua 2
```
3:
```
tarantool election.lua 3
```
Similarly, these 2 commands will create directories `./tnt2` and `./tnt3` and run tarantool

4:
```
tarantool router.lua
```
The fourth instance will be a router. The router calls `api_insert` funtion defined on the
data nodes.

You may start multiple routers, they'll all connect to the same set of instances you've started
earlier and generate insertion requests simultaneously.

The three election instances are run in interactive mode, so you may issue `box.space.test:select{}`,
`box.info.election` on them to see what's going on.

In order to see how failover works, you'll have to disable the current cluster leader.
To find which instance is leader, you need to issue `box.info.election.state` and
find the one which state is `"leader"`. Alternatively, you may look at router's output.
It polls each instance's `box.info.election.state` and logs the port at which the leader
is listening:
```
Connection to instance at 3301 established
Connection to instance at 3303 established
Connection to instance at 3302 established
Leader found at 3302
````
The instance started with `tarantool election.lua 2` is listening on port `3302`, so this is
the instance we're going to disable.

There are two ways to trigger a new leader election:
1. We may ask the current leader to resign by issuing `box.cfg{election_mode="voter"}` on it
2. We may simply stop it. `Ctrl+C` or `os.exit()` will be enough (you may restart the
   instance anytime with the same command `tarantool election.lua 2`

Once the old leader dies or resigns, the remaining two instances start leader election.
The router waits till they finish all the negotiations and continues relaying data on the
new leader:
```
test:insert{1575} - success
{1575} took 0.00099086761474609 seconds
test:insert{1576} - fail
Peer closed
No connection to instance at 3302
Leader found at 3301
test:insert{1576} - success
{1576} took 0.55057501792908 seconds
test:insert{1577} - success
{1577} took 0.001101016998291 seconds
```
The router logs time since it first tried to insert data and till it succeeded.
When everything is ok (insertion 1575), insertion into a synchronous space takes
a fraction of a second.
During insertion 1576 old leader was stopped, but failover happened in half a second
and insertions continued at the same rate on the new leader.
With our on-board leader election algorithm failover is a matter of seconds.

## Configuration
Let's walk you through the configuration options needed to get an instance with
leader election up and running:

`box.cfg{replication_synchro_quorum=2}` - quorum is the number of instances that need
to vote for a candidate so that it becomes a leader. It is also a number of instances
that need to receive a synchronous transaction before the leader commits it.

`box.cfg{election_mode="candidate"}` - candidate instances participate in elections and
may become leaders themselves

`box.cfg{election_mode="voter"}` - voters participate in elections but never become
leaders themselves. Such instances are needed to achieve votinig quorum

`box.cfg{replication_timeout=0.25}` - replication_timeout determines the frequency with
which instances exchange heartbeats. A leader is considered dead if no other instance
hears from it for `4 * replication_timeout` seconds

`box.cfg{election_timeout=0.25}` - timeout between election rounds. Elections are restarted
once in `election_timeout` if a split vote occurs.
