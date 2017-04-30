# Pine
Alpine Linux on OSTree.

### Install
`flash` pulls the latest image from github and dumps it
on the on specified device.

```
wget https://cdn.rawgit.com/untoreh/pine/997ef562/flash.pine -qO - | sh -s /dev/vda
```
Environment variables can be used:

- `IFACE`,`ADDRESS`,`GATEWAY`,`NETMASK `for network configuration
- `PARTS` comma separated list of partition sizes, eg `2G,256M` 

if partitions are specified no filesystems are created on them, otherwise a default
configuration of 5G,2

### Server
`serve` re-sets up a tz2 ostree repo from built image and 
starts the server to allow ostree clients to update to
the latest version.

### Usage
`run` creates the image to push on github.

#### TODO
- uproot vars and make them configurable
- make the packed extras optional
