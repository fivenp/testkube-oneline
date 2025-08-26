## Prerequisites
Can be automated/scripted for the sake of easiness

* docker + minikube (or whatever we prefer)
* tilt.dev
* helm
* (kubectl & or testkube cli)

Steps can be checked + automated within tilt
* install runner into the local cluster
* ENV vars to define runner-id, license-key, etc etc

## Local devloop

### Start
Starts and listens for changes

`tilt up`

### Cleanup
Stops clusters, etc

`tilt down`

### Reset/Destroy
Removes everything

`tilt destroy`


## Meaning for TK

Document + share best practices and rather improve what we have today - e.g. mute executions, etc etc
