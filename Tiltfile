# Use your local k8s context if you already have one; otherwise this is just for Tilt state
k8s_context('docker-desktop')  # or any; not used by the local_resources below

# Path to your workflow file
WORKFLOW = 'mytest.yaml'       # change or pass via TILT_ARGS, see below

# Build the helper image (same as `docker build -t testkube-local:latest .`)
local_resource(
  'build-image',
  'docker build -t testkube-local:latest .',
  deps=['Dockerfile', 'entrypoint.sh'],   # add other files if they affect the build
)

# Run once automatically when the workflow file changes (install-if-needed + run)
local_resource(
  'apply+run',
  './tk_run.sh ' + WORKFLOW,
  deps=[WORKFLOW, 'tk_run.sh'],
  resource_deps=['build-image'],
)

# Manual “Run now” button (doesn’t rebuild image)
local_resource(
  'run-now',
  './tk_run.sh ' + WORKFLOW + ' --logs',
  trigger_mode='manual',
)

# Manual “Destroy cluster” button
local_resource(
  'destroy',
  './tk_run.sh ' + WORKFLOW + ' --destroy',
  trigger_mode='manual',
)
