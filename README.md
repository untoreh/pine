# Pine
Alpine Linux on OSTree.

### Install
`flash` pulls the latest image from github and dumps it
on the on specified device.

```
wget  https://min.gitcdn.link/repo/untoreh/pine/master/flash.pine -qO - | sh -s /dev/vda
```


### Server
`serve` re-sets up a tz2 ostree repo from built image and 
starts the server to allow ostree clients to update to
the latest version.

### Usage
`run` creates the image to push on github.

#### TODO
- uproot vars and make them configurable
- make the packed extras optional
